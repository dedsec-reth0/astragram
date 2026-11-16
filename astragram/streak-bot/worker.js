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

  const restores = await env.DB.prepare('SELECT friend_id, day FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id).all();
  await env.DB.prepare('DELETE FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id).run();
  return json({ restores: (restores.results || []).map((r) => ({ friend: r.friend_id, day: r.day })) });
}

async function handleUnlink(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ ok: true });
  await env.DB.batch([
    env.DB.prepare('DELETE FROM owners WHERE tg_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM pairs WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id),
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
        ? 'Огоньков пока нет.\n\nОгонёк ведёт тот, у кого AstraGram: пусть откроет ваш профиль, нажмёт «Огонёк» и подключит бота. Тогда здесь появится счёт, а вечером — напоминание.'
        : 'No streaks yet.\n\nA streak is kept by someone with AstraGram: they open your profile, tap Streak and connect the bot. Then the count shows here, with a reminder in the evening.',
    };
  }
  const t = now();
  const lines = [];
  const buttons = [];
  for (const row of rows) {
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
      env.DB.prepare('INSERT INTO owners (token_hash, tg_id, name, created_at) VALUES (?, ?, ?, ?)').bind(hash, from.id, (from.first_name || 'AstraGram').slice(0, 64), t),
    ]);
    await tg(env, 'sendMessage', {
      chat_id: from.id,
      text: ru
        ? '✅ AstraGram подключён к боту огоньков.\n\nТе, с кем у вас огонёк и у кого нет AstraGram, увидят здесь счёт, получат напоминание вечером и смогут восстановить пропущенный день. Пригласить человека можно с экрана огонька в AstraGram.\n\nБоту приходят только числа, тексты сообщений — никогда. Отключить: AstraGram → огонёк → «Отключить бота огоньков».'
        : '✅ AstraGram is connected to the streak bot.\n\nPeople you have a streak with who do not use AstraGram see the count here, get a reminder in the evening and can restore a missed day. Invite someone from the streak screen in AstraGram.\n\nThe bot gets only numbers, never message texts. To disconnect: AstraGram → streak → Disconnect Streak Bot.',
    });
    return;
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
        ? 'Огонёк растёт, когда вы с собеседником каждый день пишете друг другу хотя бы по 3 сообщения. Пропущенный день можно восстановить на следующий день — до 5 раз в неделю. Если огонёк погаснет, всё начнётся заново.\n\n/streaks — мои огоньки\n/stop — выключить напоминания'
        : 'A streak grows when you and the other person write at least 3 messages to each other every day. A missed day can be restored the next day — up to 5 times a week. If the streak goes out, it starts over.\n\n/streaks — my streaks\n/stop — turn reminders off',
    });
    return;
  }

  // /start, /streaks or anything else: the list.
  await env.DB.prepare('INSERT INTO friends (tg_id, started_at, stopped) VALUES (?, ?, 0) ON CONFLICT (tg_id) DO UPDATE SET stopped = 0').bind(from.id, t).run();
  const reply = await streaksMessage(env, from.id, ru);
  await tg(env, 'sendMessage', { chat_id: from.id, ...reply });
}

async function handleCallback(env, callback) {
  const from = callback.from;
  const ru = isRussian(from);
  const match = (callback.data || '').match(/^r:(\d+)$/);
  let answer = ru ? 'Не получилось' : 'Could not do that';
  if (match) {
    const ownerId = Number(match[1]);
    const pair = await env.DB.prepare('SELECT p.*, o.name AS owner_name FROM pairs p JOIN owners o ON o.tg_id = p.owner_id WHERE p.owner_id = ? AND p.friend_id = ?').bind(ownerId, from.id).first();
    if (pair && pair.restorable_day !== null && pair.restores_left > 0) {
      await env.DB.prepare('INSERT OR IGNORE INTO restore_requests (owner_id, friend_id, day, created_at) VALUES (?, ?, ?, ?)').bind(ownerId, from.id, pair.restorable_day, now()).run();
      answer = ru
        ? `Готово: вчерашний день засчитается, как только AstraGram у ${pair.owner_name} выйдет на связь`
        : `Done: yesterday counts as soon as ${pair.owner_name}'s AstraGram is online`;
    } else {
      answer = ru ? 'Восстановить уже нельзя' : 'It can no longer be restored';
    }
  }
  await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id, text: answer, show_alert: true });
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
  ]);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/tg') return handleTelegram(request, env);
    if (request.method === 'POST' && url.pathname === '/api/sync') return handleSync(request, env);
    if (request.method === 'POST' && url.pathname === '/api/unlink') return handleUnlink(request, env);
    if (url.pathname === '/') return new Response('AstraGram streak bot', { headers: { 'content-type': 'text/plain; charset=utf-8' } });
    return new Response('not found', { status: 404 });
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(remind(env));
  },
};
