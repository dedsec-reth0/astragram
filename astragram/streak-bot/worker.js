// AstraGram streak bot (Cloudflare Worker + D1).
//
// AstraGram counts a streak (огонёк) on the phone from the chat's messages. When its user connects this bot, the app
// sends here only numbers: the other person's Telegram ID, the streak, how many messages each wrote today and whether
// yesterday can be restored. The bot shows them to the other person (who may not have AstraGram), reminds them in the
// evening and takes their restore requests, which the app picks up on its next sync. Message texts never come here.
//
// Secrets: BOT_TOKEN (Worker secret). The webhook is checked with a secret derived from the token.

const MAX_PAIRS = 300;
const STALE_DAYS = 30;

// The bot's admin: their private chat is the control panel and the support inbox. A plain Telegram user id (not a
// secret): messaging someone needs them to have started the bot.
const ADMIN_ID = 887825713;
// How many messages one invocation sends, kept well under the Workers subrequest limit.
const BROADCAST_BATCH = 25;

function isAdmin(id) {
  return id === ADMIN_ID;
}

async function kvGet(env, key) {
  const row = await env.DB.prepare('SELECT value FROM kv WHERE key = ?').bind(key).first();
  return row ? row.value : '';
}

async function kvSet(env, key, value) {
  await env.DB.prepare('INSERT INTO kv (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at')
    .bind(key, String(value), now()).run();
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function webhookSecret(env) {
  return (await sha256Hex(`${env.BOT_TOKEN}:webhook`)).slice(0, 48);
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

async function tg(env, method, body) {
  const response = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return response.json().catch(() => ({ ok: false }));
}

// Telegram names may carry invisible characters (AstraGram's badge marker is made of them). They are dropped.
function cleanName(name) {
  const cleaned = String(name || '').replace(/[\u200B-\u200F\u2060-\u2064\uFEFF]/g, '').trim();
  return (cleaned || 'AstraGram').slice(0, 64);
}

function now() {
  return Math.floor(Date.now() / 1000);
}

function isRussian(from) {
  const code = (from && from.language_code) || 'ru';
  return !code.startsWith('en');
}

function plural(n, ru) {
  if (!ru) return n === 1 ? '1 day' : `${n} days`;
  const m10 = n % 10;
  const m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return `${n} день`;
  if (m10 >= 2 && m10 <= 4 && !(m100 >= 12 && m100 <= 14)) return `${n} дня`;
  return `${n} дней`;
}

function ago(seconds, ru) {
  const minutes = Math.max(0, Math.floor(seconds / 60));
  if (minutes < 2) return ru ? 'только что' : 'just now';
  if (minutes < 60) return ru ? `${minutes} мин назад` : `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return ru ? `${hours} ч назад` : `${hours} h ago`;
  return ru ? `${Math.floor(hours / 24)} дн назад` : `${Math.floor(hours / 24)} d ago`;
}

// ---------------------------------------------------------------------------------------------------------------
// The app's API

async function ownerFromRequest(request, env) {
  const auth = request.headers.get('authorization') || '';
  const match = auth.match(/^Bearer ([0-9a-f]{48})$/);
  if (!match) return null;
  const hash = await sha256Hex(match[1]);
  return env.DB.prepare('SELECT * FROM owners WHERE token_hash = ?').bind(hash).first();
}

function int(value, min, max, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(n)));
}

async function handleSync(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ error: 'not linked' }, 401);
  if (now() - owner.last_sync < 20) return json({ error: 'too often' }, 429);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const pairs = Array.isArray(body.pairs) ? body.pairs.slice(0, MAX_PAIRS) : [];
  const need = int(body.need, 1, 100, 3);
  const tz = int(body.tz, -14 * 3600, 14 * 3600, 0);
  const t = now();
  const statements = [env.DB.prepare('UPDATE owners SET last_sync = ?, tz = ? WHERE token_hash = ?').bind(t, tz, owner.token_hash)];
  const known = new Set(((await env.DB.prepare('SELECT friend_id FROM pairs WHERE owner_id = ?').bind(owner.tg_id).all()).results || []).map((r) => r.friend_id));
  const friendIds = [];
  for (const pair of pairs) {
    const friend = int(pair.friend, 1, Number.MAX_SAFE_INTEGER, 0);
    if (!friend || friend === owner.tg_id) continue;
    friendIds.push(friend);
    const restorable = pair.restorableDay === undefined || pair.restorableDay === null ? null : int(pair.restorableDay, 0, 1e6, 0);
    statements.push(env.DB.prepare(
      `INSERT INTO pairs (owner_id, friend_id, count, mine, theirs, today_done, restores_left, restorable_day, lost_count, day, need, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (owner_id, friend_id) DO UPDATE SET count = excluded.count, mine = excluded.mine, theirs = excluded.theirs,
         today_done = excluded.today_done, restores_left = excluded.restores_left, restorable_day = excluded.restorable_day,
         lost_count = excluded.lost_count, day = excluded.day, need = excluded.need, updated_at = excluded.updated_at`
    ).bind(owner.tg_id, friend, int(pair.count, 0, 1e5), int(pair.mine, 0, 1e6), int(pair.theirs, 0, 1e6), pair.todayDone ? 1 : 0,
      int(pair.restoresLeft, 0, 7), restorable, int(pair.lostCount, 0, 1e5), int(pair.day, 0, 1e6), need, t));
  }
  // Streaks turned off in the app are gone here too.
  if (friendIds.length > 0) {
    statements.push(env.DB.prepare(`DELETE FROM pairs WHERE owner_id = ? AND friend_id NOT IN (${friendIds.map(() => '?').join(',')})`).bind(owner.tg_id, ...friendIds));
  } else {
    statements.push(env.DB.prepare('DELETE FROM pairs WHERE owner_id = ?').bind(owner.tg_id));
  }
  await env.DB.batch(statements);

  // Whoever started the bot before this streak reached it hears about it now, without pressing anything.
  const fresh = friendIds.filter((id) => !known.has(id));
  if (fresh.length > 0) {
    const listening = (await env.DB.prepare(`SELECT tg_id FROM friends WHERE stopped = 0 AND tg_id IN (${fresh.map(() => '?').join(',')})`).bind(...fresh).all()).results || [];
    const name = cleanName(owner.name);
    for (const row of listening) {
      const reply = await streaksMessage(env, row.tg_id, true);
      reply.text = `🔥 ${name} начал(а) с тобой огонёк!\n\n${reply.text}`;
      await tg(env, 'sendMessage', { chat_id: row.tg_id, ...reply });
    }
  }

  const restores = await env.DB.prepare('SELECT friend_id, day FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id).all();
  await env.DB.prepare('DELETE FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id).run();
  return json({ restores: (restores.results || []).map((r) => ({ friend: r.friend_id, day: r.day })) });
}

// The AstraGram badge. Telegram drops invisible characters from names, so the badge cannot ride in the name: an app
// with the badge on says so here, and every AstraGram with the badge on gets the whole list back (no contacts are
// sent). A badge nobody refreshed in BADGE_DAYS is dropped.
const BADGE_DAYS = 45;
const MAX_BADGES = 50000;

async function handleBadge(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ error: 'not linked' }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const t = now();
  if (!body.show) {
    await env.DB.prepare('DELETE FROM badges WHERE tg_id = ?').bind(owner.tg_id).run();
    return json({ users: [] });
  }
  // A badge-only owner never syncs streaks: this keeps it from being taken for stale.
  await env.DB.prepare('UPDATE owners SET last_sync = ? WHERE token_hash = ? AND last_sync < ?').bind(t, owner.token_hash, t - 86400).run();
  await env.DB.prepare('INSERT INTO badges (tg_id, updated_at) VALUES (?, ?) ON CONFLICT (tg_id) DO UPDATE SET updated_at = excluded.updated_at')
    .bind(owner.tg_id, t).run();
  const rows = (await env.DB.prepare('SELECT tg_id FROM badges WHERE updated_at >= ? LIMIT ?').bind(t - BADGE_DAYS * 86400, MAX_BADGES).all()).results || [];
  return json({ users: rows.map((r) => r.tg_id) });
}

// The app's launch gate. The app reads this at launch; when blocked it refuses to run and shows the message. The
// state is set only through /api/control, which needs the owner token (APP_CONTROL_TOKEN, a Worker secret). Without
// that secret the control endpoint does not exist and the app is never blocked.
async function handleStatus(env) {
  const row = await env.DB.prepare('SELECT blocked, message, message_en, url FROM app_state WHERE id = 1').first();
  if (!row || !row.blocked) {
    return json({ blocked: false });
  }
  return json({ blocked: true, message: row.message || '', messageEn: row.message_en || '', url: row.url || '' });
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

async function handleControl(request, env) {
  if (!env.APP_CONTROL_TOKEN) {
    return json({ error: 'not found' }, 404);
  }
  const auth = request.headers.get('authorization') || '';
  const match = auth.match(/^Bearer (.+)$/);
  if (!match || !timingSafeEqual(match[1], env.APP_CONTROL_TOKEN)) {
    return json({ error: 'forbidden' }, 403);
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const blocked = body.blocked ? 1 : 0;
  const message = String(body.message || '').slice(0, 2000);
  const messageEn = String(body.messageEn || '').slice(0, 2000);
  const url = String(body.url || '').slice(0, 500);
  await env.DB.prepare(
    `INSERT INTO app_state (id, blocked, message, message_en, url, updated_at) VALUES (1, ?, ?, ?, ?, ?)
     ON CONFLICT (id) DO UPDATE SET blocked = excluded.blocked, message = excluded.message,
       message_en = excluded.message_en, url = excluded.url, updated_at = excluded.updated_at`
  ).bind(blocked, message, messageEn, url, now()).run();
  return json({ ok: true, blocked: !!blocked });
}

async function handleUnlink(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ ok: true });
  await env.DB.batch([
    env.DB.prepare('DELETE FROM owners WHERE tg_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM pairs WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM badges WHERE tg_id = ?').bind(owner.tg_id),
  ]);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------------------------------------------
// The bot

async function streaksMessage(env, userId, ru) {
  const rows = (await env.DB.prepare(
    `SELECT p.*, o.name AS owner_name FROM pairs p JOIN owners o ON o.tg_id = p.owner_id
     WHERE p.friend_id = ? ORDER BY p.count DESC`
  ).bind(userId).all()).results || [];
  if (rows.length === 0) {
    return {
      text: ru
        ? 'Огоньков пока нет.\n\nОгонёк ведёт тот, у кого AstraGram: пусть откроет ваш профиль, нажмёт «Огонёк» и подключит бота. Как только его AstraGram пришлёт счёт, я сам напишу сюда.'
        : 'No streaks yet.\n\nA streak is kept by someone with AstraGram: they open your profile, tap Streak and connect the bot. As soon as their AstraGram sends the count, I will write here myself.',
    };
  }
  const t = now();
  const lines = [];
  const buttons = [];
  for (const row of rows) {
    row.owner_name = cleanName(row.owner_name);
    const shown = row.restorable_day !== null ? Math.max(row.count, row.lost_count) : row.count;
    lines.push(`🔥 ${plural(shown, ru)} — ${row.owner_name}`);
    lines.push(ru
      ? `   Сегодня: ты ${Math.min(row.theirs, row.need)}/${row.need}, ${row.owner_name} ${Math.min(row.mine, row.need)}/${row.need}${row.today_done ? ' ✅' : ''}`
      : `   Today: you ${Math.min(row.theirs, row.need)}/${row.need}, ${row.owner_name} ${Math.min(row.mine, row.need)}/${row.need}${row.today_done ? ' ✅' : ''}`);
    if (row.restorable_day !== null && row.restores_left > 0) {
      lines.push(ru
        ? `   Вчера пропущено — можно восстановить сегодня (осталось ${row.restores_left} на неделе)`
        : `   Yesterday was missed — it can be restored today (${row.restores_left} left this week)`);
      buttons.push([{ text: ru ? `🔥 Восстановить с ${row.owner_name}` : `🔥 Restore with ${row.owner_name}`, callback_data: `r:${row.owner_id}` }]);
    }
    lines.push(ru ? `   обновлено ${ago(t - row.updated_at, ru)}` : `   updated ${ago(t - row.updated_at, ru)}`);
  }
  lines.push('');
  lines.push(ru
    ? 'День засчитывается, когда каждый написал хотя бы 3 сообщения. Счёт ведёт AstraGram собеседника и обновляется, когда его приложение на связи.'
    : 'A day counts when each of you wrote at least 3 messages. The count is kept by the other person\'s AstraGram and updates when their app is online.');
  return { text: lines.join('\n'), reply_markup: buttons.length ? { inline_keyboard: buttons } : undefined };
}

async function handleMessage(env, message) {
  const from = message.from;
  if (!from || from.is_bot || message.chat.type !== 'private') return;
  const ru = isRussian(from);
  const text = (message.text || '').trim();
  const t = now();

  const link = text.match(/^\/start l([0-9a-f]{48})$/);
  if (link) {
    const hash = await sha256Hex(link[1]);
    // One linked device per account: a new link replaces the old one.
    await env.DB.batch([
      env.DB.prepare('DELETE FROM owners WHERE tg_id = ?').bind(from.id),
      env.DB.prepare('INSERT INTO owners (token_hash, tg_id, name, created_at) VALUES (?, ?, ?, ?)').bind(hash, from.id, cleanName(from.first_name), t),
    ]);
    await tg(env, 'sendMessage', {
      chat_id: from.id,
      text: ru
        ? '✅ AstraGram подключён к боту огоньков.\n\nТе, с кем у вас огонёк и у кого нет AstraGram, увидят здесь счёт, получат напоминание вечером и смогут восстановить пропущенный день. Пригласить человека можно с экрана огонька в AstraGram.\n\nБоту приходят только числа, тексты сообщений — никогда. Отключить: AstraGram → огонёк → «Отключить бота огоньков».'
        : '✅ AstraGram is connected to the streak bot.\n\nPeople you have a streak with who do not use AstraGram see the count here, get a reminder in the evening and can restore a missed day. Invite someone from the streak screen in AstraGram.\n\nThe bot gets only numbers, never message texts. To disconnect: AstraGram → streak → Disconnect Streak Bot.',
    });
    return;
  }

  // The admin's chat is the control panel and the support inbox.
  if (isAdmin(from.id)) {
    if (await handleAdminMessage(env, message)) return;
  }

  if (text === '/stop') {
    await env.DB.prepare('INSERT INTO friends (tg_id, started_at, stopped) VALUES (?, ?, 1) ON CONFLICT (tg_id) DO UPDATE SET stopped = 1').bind(from.id, t).run();
    await tg(env, 'sendMessage', { chat_id: from.id, text: ru ? 'Напоминания выключены. Включить снова: /start' : 'Reminders are off. Turn them on again: /start' });
    return;
  }

  if (text === '/help') {
    await tg(env, 'sendMessage', {
      chat_id: from.id,
      text: ru
        ? 'Огонёк растёт, когда вы с собеседником каждый день пишете друг другу хотя бы по 3 сообщения. Пропущенный день можно восстановить на следующий день — до 5 раз в неделю. Если огонёк погаснет, всё начнётся заново.\n\n/streaks — мои огоньки\n/stop — выключить напоминания\n\nНужна помощь? Просто напишите сюда — сообщение попадёт в поддержку AstraGram, и вам ответят здесь.'
        : 'A streak grows when you and the other person write at least 3 messages to each other every day. A missed day can be restored the next day — up to 5 times a week. If the streak goes out, it starts over.\n\n/streaks — my streaks\n/stop — turn reminders off\n\nNeed help? Just write here — your message reaches AstraGram support and they reply here.',
    });
    return;
  }

  // /start, /start f<id> and /streaks open the streak list; any other free-form message goes to support.
  const isStreakEntry = text === '/streaks' || text === '/start' || /^\/start f\d{1,20}$/.test(text);
  if (!isStreakEntry && !isAdmin(from.id)) {
    await handleSupport(env, message);
    return;
  }

  await env.DB.prepare('INSERT INTO friends (tg_id, started_at, stopped) VALUES (?, ?, 0) ON CONFLICT (tg_id) DO UPDATE SET stopped = 0').bind(from.id, t).run();
  const invite = text.match(/^\/start f(\d{1,20})$/);
  if (invite) {
    const ownerId = Number(invite[1]);
    const pair = await env.DB.prepare('SELECT 1 FROM pairs WHERE owner_id = ? AND friend_id = ?').bind(ownerId, from.id).first();
    if (!pair) {
      const owner = await env.DB.prepare('SELECT name FROM owners WHERE tg_id = ?').bind(ownerId).first();
      const who = owner ? cleanName(owner.name) : (ru ? 'собеседника' : 'the other person');
      await tg(env, 'sendMessage', {
        chat_id: from.id,
        text: ru
          ? `👋 Привет! Огонёк с ${who} появится здесь, как только AstraGram ${who} пришлёт счёт — обычно в течение пары минут, когда приложение открыто. Я сам напишу, ничего нажимать не нужно.\n\nОгонёк растёт, когда вы оба пишете друг другу хотя бы по 3 сообщения в день.`
          : `👋 Hi! The streak with ${who} shows up here as soon as ${who}'s AstraGram sends the count, usually within a couple of minutes while the app is open. I will write by myself, nothing to press.\n\nThe streak grows when both of you write at least 3 messages to each other a day.`,
      });
      return;
    }
  }
  const reply = await streaksMessage(env, from.id, ru);
  await tg(env, 'sendMessage', { chat_id: from.id, ...reply });
}

async function handleCallback(env, callback) {
  const from = callback.from;
  const ru = isRussian(from);
  if (isAdmin(from.id) && (callback.data || '').startsWith('bc:')) {
    if (await handleAdminCallback(env, callback)) return;
  }
  const match = (callback.data || '').match(/^r:(\d+)$/);
  let answer = ru ? 'Не получилось' : 'Could not do that';
  if (match) {
    const ownerId = Number(match[1]);
    const pair = await env.DB.prepare('SELECT p.*, o.name AS owner_name FROM pairs p JOIN owners o ON o.tg_id = p.owner_id WHERE p.owner_id = ? AND p.friend_id = ?').bind(ownerId, from.id).first();
    if (pair && pair.restorable_day !== null && pair.restores_left > 0) {
      await env.DB.prepare('INSERT OR IGNORE INTO restore_requests (owner_id, friend_id, day, created_at) VALUES (?, ?, ?, ?)').bind(ownerId, from.id, pair.restorable_day, now()).run();
      pair.owner_name = cleanName(pair.owner_name);
      answer = ru
        ? `Готово: вчерашний день засчитается, как только AstraGram у ${pair.owner_name} выйдет на связь`
        : `Done: yesterday counts as soon as ${pair.owner_name}'s AstraGram is online`;
    } else {
      answer = ru ? 'Восстановить уже нельзя' : 'It can no longer be restored';
    }
  }
  await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id, text: answer, show_alert: true });
}

// ---------------------------------------------------------------------------------------------------------------
// Tech support and broadcasts

// A user's message, forwarded to the admin once. Receipt is shown as a reaction on the user's message, not a reply,
// so the chat stays clean. The admin answers by replying to the forwarded message (see handleAdminMessage).
async function handleSupport(env, message) {
  const from = message.from;
  // Anyone who writes is reachable for broadcasts; never un-stop someone who used /stop.
  await env.DB.prepare('INSERT INTO friends (tg_id, started_at, stopped) VALUES (?, ?, 0) ON CONFLICT (tg_id) DO NOTHING').bind(from.id, now()).run();
  const fwd = await tg(env, 'forwardMessage', { chat_id: ADMIN_ID, from_chat_id: from.id, message_id: message.message_id });
  let adminMsgId = fwd.ok && fwd.result ? fwd.result.message_id : null;
  if (!adminMsgId) {
    // Forwarding can be refused (privacy); fall back to a header plus a copy of the content.
    const uname = from.username ? ` @${from.username}` : '';
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, text: `💬 ${cleanName(from.first_name)}${uname} (id ${from.id}):` });
    const copied = await tg(env, 'copyMessage', { chat_id: ADMIN_ID, from_chat_id: from.id, message_id: message.message_id });
    adminMsgId = copied.ok && copied.result ? copied.result.message_id : null;
  }
  if (!adminMsgId) {
    return;
  }
  await env.DB.prepare('INSERT OR REPLACE INTO support (admin_msg_id, user_id, created_at) VALUES (?, ?, ?)').bind(adminMsgId, from.id, now()).run();
  await tg(env, 'setMessageReaction', { chat_id: from.id, message_id: message.message_id, reaction: [{ type: 'emoji', emoji: '👀' }] });
}

// Everyone the bot can reach: people who started it and AstraGram users who linked it (the admin excluded).
async function broadcastRecipients(env) {
  const rows = (await env.DB.prepare('SELECT tg_id FROM friends WHERE stopped = 0 UNION SELECT tg_id FROM owners').all()).results || [];
  return rows.map((r) => r.tg_id).filter((id) => id !== ADMIN_ID);
}

async function enqueueBroadcast(env, fromChat, msgId) {
  const ids = await broadcastRecipients(env);
  const t = now();
  const statements = ids.map((id) => env.DB.prepare('INSERT INTO broadcast_queue (chat_id, from_chat, msg_id, created_at) VALUES (?, ?, ?, ?)').bind(id, fromChat, msgId, t));
  for (let i = 0; i < statements.length; i += 50) {
    await env.DB.batch(statements.slice(i, i + 50));
  }
  return ids.length;
}

async function drainBroadcast(env) {
  const rows = (await env.DB.prepare('SELECT * FROM broadcast_queue ORDER BY id LIMIT ?').bind(BROADCAST_BATCH).all()).results || [];
  for (const row of rows) {
    const res = await tg(env, 'copyMessage', { chat_id: row.chat_id, from_chat_id: row.from_chat, message_id: row.msg_id });
    if (!res.ok && res.error_code === 429) {
      // Rate limited: stop and leave the rest for the next drain (the cron runs every minute).
      break;
    }
    // Sent, or the user blocked the bot / chat is gone: either way the row is done.
    await env.DB.prepare('DELETE FROM broadcast_queue WHERE id = ?').bind(row.id).run();
  }
}

function adminPanel() {
  return {
    text: '🛠 <b>Панель администратора</b>\n\n• Ответьте <b>reply</b> на пересланное сообщение пользователя, чтобы написать ему.\n• «Новый пост» — рассылка всем.',
    parse_mode: 'HTML',
    reply_markup: { inline_keyboard: [
      [{ text: '📢 Новый пост', callback_data: 'bc:new' }],
      [{ text: '📊 Статистика', callback_data: 'bc:stats' }],
    ] },
  };
}

async function adminStats(env) {
  const reach = (await broadcastRecipients(env)).length;
  const owners = (await env.DB.prepare('SELECT COUNT(*) AS c FROM owners').first()).c;
  const pairs = (await env.DB.prepare('SELECT COUNT(*) AS c FROM pairs').first()).c;
  const queued = (await env.DB.prepare('SELECT COUNT(*) AS c FROM broadcast_queue').first()).c;
  let text = `📊 <b>Статистика</b>\n\n👥 Подписчиков бота: <b>${reach}</b>\n🔥 Пользователей AstraGram: <b>${owners}</b>\n💬 Активных огоньков: <b>${pairs}</b>`;
  if (queued) {
    text += `\n\n📤 В очереди рассылки: <b>${queued}</b>`;
  }
  return { text, parse_mode: 'HTML' };
}

async function promptForPost(env) {
  await kvSet(env, 'admin_state', 'await_post');
  await tg(env, 'sendMessage', { chat_id: ADMIN_ID, text: '📢 Пришлите пост одним сообщением — текст, фото, видео, что угодно. Покажу предпросмотр перед отправкой.\n\n/cancel — отмена.' });
}

async function confirmPost(env, message) {
  await kvSet(env, 'admin_state', '');
  await kvSet(env, 'pending_post', JSON.stringify({ from_chat: ADMIN_ID, msg_id: message.message_id }));
  const count = (await broadcastRecipients(env)).length;
  await tg(env, 'sendMessage', {
    chat_id: ADMIN_ID,
    text: `Отправить этот пост? Получателей: <b>${count}</b>.`,
    parse_mode: 'HTML',
    reply_markup: { inline_keyboard: [[
      { text: `✅ Разослать`, callback_data: 'bc:send' },
      { text: '✖️ Отмена', callback_data: 'bc:cancel' },
    ]] },
  });
}

// The admin's chat. Returns true when the message was handled (so no streak/support processing follows).
async function handleAdminMessage(env, message) {
  const text = (message.text || '').trim();

  // A reply to a forwarded support message → relay it to that user.
  if (message.reply_to_message) {
    const row = await env.DB.prepare('SELECT user_id FROM support WHERE admin_msg_id = ?').bind(message.reply_to_message.message_id).first();
    if (row) {
      const res = await tg(env, 'copyMessage', { chat_id: row.user_id, from_chat_id: ADMIN_ID, message_id: message.message_id });
      await tg(env, 'setMessageReaction', { chat_id: ADMIN_ID, message_id: message.message_id, reaction: res.ok ? [{ type: 'emoji', emoji: '👍' }] : [] });
      if (!res.ok) {
        await tg(env, 'sendMessage', { chat_id: ADMIN_ID, text: '⚠️ Не доставлено — пользователь мог остановить бота.' });
      }
      return true;
    }
  }

  if (text === '/start' || text === '/menu') {
    await tg(env, 'setMyCommands', { scope: { type: 'chat', chat_id: ADMIN_ID }, commands: [
      { command: 'post', description: '📢 Новый пост (рассылка)' },
      { command: 'stats', description: '📊 Статистика' },
      { command: 'menu', description: 'Панель администратора' },
    ] });
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, ...adminPanel() });
    return true;
  }
  if (text === '/cancel') {
    await kvSet(env, 'admin_state', '');
    await kvSet(env, 'pending_post', '');
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, text: 'Отменено.' });
    return true;
  }
  if (text === '/stats') {
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, ...(await adminStats(env)) });
    return true;
  }
  if (text === '/post') {
    await promptForPost(env);
    return true;
  }

  // Awaiting the post content.
  if ((await kvGet(env, 'admin_state')) === 'await_post' && !text.startsWith('/')) {
    await confirmPost(env, message);
    return true;
  }

  // Let the shared commands run as usual for the admin too.
  if (text === '/streaks' || text === '/help' || text === '/stop' || text.startsWith('/start ')) {
    return false;
  }

  await tg(env, 'sendMessage', { chat_id: ADMIN_ID, text: 'Ответьте (reply) на пересланное сообщение, чтобы написать пользователю.\n\n/post — рассылка\n/stats — статистика\n/menu — панель' });
  return true;
}

async function handleAdminCallback(env, callback) {
  const data = callback.data || '';
  if (data === 'bc:new') {
    await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id });
    await promptForPost(env);
    return true;
  }
  if (data === 'bc:stats') {
    await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id });
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, ...(await adminStats(env)) });
    return true;
  }
  if (data === 'bc:cancel') {
    await kvSet(env, 'pending_post', '');
    await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id, text: 'Отменено' });
    await tg(env, 'editMessageText', { chat_id: ADMIN_ID, message_id: callback.message.message_id, text: '✖️ Рассылка отменена.' });
    return true;
  }
  if (data === 'bc:send') {
    const pendingRaw = await kvGet(env, 'pending_post');
    if (!pendingRaw) {
      await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id, text: 'Пост не найден' });
      return true;
    }
    const pending = JSON.parse(pendingRaw);
    await kvSet(env, 'pending_post', '');
    const count = await enqueueBroadcast(env, pending.from_chat, pending.msg_id);
    await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id, text: `Рассылаю: ${count}` });
    await tg(env, 'editMessageText', { chat_id: ADMIN_ID, message_id: callback.message.message_id, text: `📢 Рассылка запущена. Получателей: ${count}.` });
    await drainBroadcast(env);
    return true;
  }
  return false;
}

async function handleTelegram(request, env) {
  if (request.headers.get('x-telegram-bot-api-secret-token') !== await webhookSecret(env)) {
    return new Response('forbidden', { status: 403 });
  }
  const update = await request.json().catch(() => null);
  if (update) {
    try {
      if (update.message) await handleMessage(env, update.message);
      else if (update.callback_query) await handleCallback(env, update.callback_query);
    } catch (error) {
      console.error('update failed', error && error.message);
    }
  }
  return new Response('ok');
}

// ---------------------------------------------------------------------------------------------------------------
// Reminders

async function remind(env) {
  const t = now();
  const rows = (await env.DB.prepare(
    `SELECT p.*, o.name AS owner_name, o.tz AS tz FROM pairs p
     JOIN owners o ON o.tg_id = p.owner_id
     JOIN friends f ON f.tg_id = p.friend_id AND f.stopped = 0
     WHERE p.updated_at > ? AND p.today_done = 0 AND p.theirs < p.need AND p.reminded_day < p.day AND (p.count > 0 OR p.lost_count > 0)`
  ).bind(t - 36 * 3600).all()).results || [];
  for (const row of rows) {
    const localHour = Math.floor(((t + row.tz) % 86400) / 3600);
    const localDay = Math.floor((t + row.tz) / 86400);
    if (localHour !== 19 || localDay !== row.day) continue;
    row.owner_name = cleanName(row.owner_name);
    const left = row.need - row.theirs;
    const shown = row.restorable_day !== null ? Math.max(row.count, row.lost_count) : row.count;
    await tg(env, 'sendMessage', {
      chat_id: row.friend_id,
      text: `🔥 ${plural(shown, true)} с ${row.owner_name}: напиши сегодня ещё ${left}, чтобы огонёк не погас.`,
    });
    await env.DB.prepare('UPDATE pairs SET reminded_day = ? WHERE owner_id = ? AND friend_id = ?').bind(row.day, row.owner_id, row.friend_id).run();
  }
  // Data nobody updated for a month goes away.
  const stale = t - STALE_DAYS * 86400;
  await env.DB.batch([
    env.DB.prepare('DELETE FROM pairs WHERE updated_at < ?').bind(stale),
    env.DB.prepare('DELETE FROM restore_requests WHERE created_at < ?').bind(t - 3 * 86400),
    env.DB.prepare('DELETE FROM owners WHERE last_sync < ? AND created_at < ?').bind(stale, stale),
    env.DB.prepare('DELETE FROM badges WHERE updated_at < ?').bind(t - BADGE_DAYS * 86400),
    env.DB.prepare('DELETE FROM support WHERE created_at < ?').bind(t - 30 * 86400),
    env.DB.prepare('DELETE FROM broadcast_queue WHERE created_at < ?').bind(t - 2 * 86400),
  ]);
}

// Points the bot's webhook at this worker and sets its commands. Safe to call by anyone: it can only point the bot at
// this same worker. Returns the bot's username (public) so the app can be told where the bot is.
async function handleSetup(url, env) {
  if (!env.BOT_TOKEN) return json({ ok: false, error: 'BOT_TOKEN is not set' }, 500);
  const me = await tg(env, 'getMe', {});
  if (!me.ok) return json({ ok: false, error: 'the bot token is not valid' }, 500);
  const hook = await tg(env, 'setWebhook', {
    url: `${url.origin}/tg`,
    secret_token: await webhookSecret(env),
    allowed_updates: ['message', 'callback_query'],
  });
  await tg(env, 'setMyCommands', { commands: [
    { command: 'streaks', description: 'Мои огоньки' },
    { command: 'help', description: 'Как работает огонёк' },
    { command: 'stop', description: 'Выключить напоминания' },
  ] });
  await tg(env, 'setMyDescription', { description: '🔥 Огоньки AstraGram для тех, у кого нет AstraGram: счёт, напоминание вечером и восстановление пропущенного дня. Боту приходят только числа, тексты сообщений — никогда.' });
  return json({ ok: hook.ok === true, username: me.result.username, server: url.origin });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/tg') return handleTelegram(request, env);
    if (request.method === 'GET' && url.pathname === '/api/status') return handleStatus(env);
    if (request.method === 'POST' && url.pathname === '/api/control') return handleControl(request, env);
    if (request.method === 'POST' && url.pathname === '/api/sync') return handleSync(request, env);
    if (request.method === 'POST' && url.pathname === '/api/badge') return handleBadge(request, env);
    if (request.method === 'POST' && url.pathname === '/api/unlink') return handleUnlink(request, env);
    if (url.pathname === '/setup') return handleSetup(url, env);
    if (url.pathname === '/') return new Response('AstraGram streak bot', { headers: { 'content-type': 'text/plain; charset=utf-8' } });
    return new Response('not found', { status: 404 });
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil((async () => {
      // Every minute: move the broadcast queue along. Reminders and cleanup stay hourly (at minute 5, as before).
      await drainBroadcast(env);
      if (new Date(event.scheduledTime).getUTCMinutes() === 5) {
        await remind(env);
      }
    })());
  },
};
