// AstraGram streak bot (Cloudflare Worker + D1).
//
// AstraGram counts a streak (огонёк) on the phone from the chat's messages. When its user connects this bot, the app
// sends here only numbers: the other person's Telegram ID, the streak, how many messages each wrote today and whether
// yesterday can be restored. The bot shows them to the other person (who may not have AstraGram), reminds them in the
// evening and takes their restore requests, which the app picks up on its next sync. Message texts never come here.
//
// Secrets: BOT_TOKEN (Worker secret). The webhook is checked with a secret derived from the token.

const MAX_PAIRS = 300;
// One sync per token in this many seconds.
const SYNC_INTERVAL = 20;
const MAX_LIST = 2 * MAX_PAIRS;
// Restored days taken from one pair in one sync, and how far back.
const RESTORED_PER_SYNC = 10;
const RESTORED_DAYS = 30;
// New friends the bot tells about a streak, per owner per day (made-up IDs must not turn the bot into a spam sender).
const NOTIFY_PER_DAY = 20;
const STALE_DAYS = 30;

// The bot's admin: their private chat is the control panel and the support inbox. The id is assembled from parts so
// it is not a plain number in the source (a code search will not find it; it is still computable from here).
const ADMIN_ID = 800000000 + 80000000 + 7000000 + 825713;
// How many messages one invocation sends, kept well under the Workers subrequest limit and the free plan's 50 D1
// queries per invocation (a drain makes a few queries per batch, not per message).
const BROADCAST_BATCH = 20;

// An account keeps one owners row per linked device (up to 5): joining owners directly returns every pair once per
// device. This is one row per account, its most recently synced device, whose time zone is the current one.
const LATEST_OWNER = `(SELECT tg_id, name, tz FROM owners o1 WHERE token_hash = (SELECT token_hash FROM owners o2
  WHERE o2.tg_id = o1.tg_id ORDER BY last_sync DESC, created_at DESC LIMIT 1))`;

// The owner's current local day, as the app counts it (see remind()).
function ownerDay(t, tz) {
  return Math.floor((t + (tz || 0)) / 86400);
}

// A restore the friend may still ask for: the pair's numbers are of the owner's current day and yesterday is
// restorable. An older row (the owner's app offline since) would be refused by the app, which restores only
// yesterday, after the bot had told the friend it would count.
function canRestore(pair, t) {
  const day = ownerDay(t, pair.owner_tz);
  return pair.restorable_day !== null && pair.restores_left > 0 && pair.day === day && pair.restorable_day === day - 1;
}

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

// The admin's inbox: a private group with topics, set up by the admin's /inbox in it (kv 'inbox': {chat, bug, idea,
// donate, support} with the topics' thread IDs). Without one, everything goes to the admin's chat with the bot.
const INBOX_TOPICS = [
  { key: 'bug', name: '🐞 Ошибки', color: 16478047 },
  { key: 'idea', name: '💡 Идеи', color: 16766590 },
  { key: 'donate', name: '💛 Донаты', color: 9367192 },
  { key: 'support', name: '💬 Поддержка', color: 7322096 },
];
// Message IDs in the group and in the admin's chat are separate counters: the group's are kept shifted in `support`.
const INBOX_KEY = 1e12;

async function inbox(env) {
  try {
    const value = JSON.parse((await kvGet(env, 'inbox')) || 'null');
    return value && Number.isSafeInteger(value.chat) ? value : null;
  } catch {
    return null;
  }
}

// Where a notice of this kind goes: {chat_id, message_thread_id?} plus the `support` key of the sent message's ID.
async function inboxTarget(env, kind) {
  const box = await inbox(env);
  if (box && box[kind]) return { to: { chat_id: box.chat, message_thread_id: box[kind] }, key: (id) => INBOX_KEY + id };
  return { to: { chat_id: ADMIN_ID }, key: (id) => id };
}

// Sends to the inbox; should the group be gone (the bot removed, the topic deleted), to the admin's chat instead.
async function sendInbox(env, kind, body) {
  const target = await inboxTarget(env, kind);
  let sent = await tg(env, 'sendMessage', { ...target.to, ...body });
  if (sent.ok || target.to.chat_id === ADMIN_ID) return { sent, key: sent.ok && sent.result ? target.key(sent.result.message_id) : null };
  sent = await tg(env, 'sendMessage', { chat_id: ADMIN_ID, ...body });
  return { sent, key: sent.ok && sent.result ? sent.result.message_id : null };
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
  let cleaned = String(name || '').replace(/[\u200B-\u200F\u2060-\u2064\uFEFF]/g, '').trim();
  // The bot quotes names to other people, and Telegram turns a link or @username in the text into a tappable one: a
  // name made to look like a link (a phishing lure from "the official bot") keeps its letters but loses the shape.
  if (/(:\/\/|www\.|t\.me|@|[A-Za-z0-9-]\.[A-Za-z]{2,})/i.test(cleaned)) {
    cleaned = cleaned.replace(/\./g, '\u2024').replace(/@/g, '\uFF20').replace(/:\/\//g, ' ');
  }
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

const PAIR_UPSERT =
  `INSERT INTO pairs (owner_id, friend_id, count, mine, theirs, today_done, restores_left, restorable_day, lost_count, day, need, updated_at)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
   ON CONFLICT (owner_id, friend_id) DO UPDATE SET count = excluded.count, mine = excluded.mine, theirs = excluded.theirs,
     today_done = excluded.today_done, restores_left = excluded.restores_left, restorable_day = excluded.restorable_day,
     lost_count = excluded.lost_count, day = excluded.day, need = excluded.need, updated_at = excluded.updated_at`;

// With several devices, one of them may not have the chat's older messages loaded yet and count a shorter streak. On the
// same day every device counts the same messages, so the larger numbers are the complete ones: the streak (with its
// restore state) of the device that counted more is kept, and today's messages are the most either device saw. A new
// day takes the new numbers as they are.
const SAME_DAY_KEEPS_OLD = 'pairs.day = excluded.day AND (pairs.count > excluded.count OR (pairs.count = excluded.count AND pairs.lost_count > excluded.lost_count))';
const PAIR_UPSERT_SHARED =
  `INSERT INTO pairs (owner_id, friend_id, count, mine, theirs, today_done, restores_left, restorable_day, lost_count, day, need, updated_at)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
   ON CONFLICT (owner_id, friend_id) DO UPDATE SET
     count = CASE WHEN ${SAME_DAY_KEEPS_OLD} THEN pairs.count ELSE excluded.count END,
     restores_left = CASE WHEN ${SAME_DAY_KEEPS_OLD} THEN pairs.restores_left ELSE excluded.restores_left END,
     restorable_day = CASE WHEN ${SAME_DAY_KEEPS_OLD} THEN pairs.restorable_day ELSE excluded.restorable_day END,
     lost_count = CASE WHEN ${SAME_DAY_KEEPS_OLD} THEN pairs.lost_count ELSE excluded.lost_count END,
     mine = CASE WHEN pairs.day = excluded.day THEN MAX(pairs.mine, excluded.mine) ELSE excluded.mine END,
     theirs = CASE WHEN pairs.day = excluded.day THEN MAX(pairs.theirs, excluded.theirs) ELSE excluded.theirs END,
     today_done = CASE WHEN pairs.day = excluded.day THEN MAX(pairs.today_done, excluded.today_done) ELSE excluded.today_done END,
     day = excluded.day, need = excluded.need, updated_at = excluded.updated_at
   WHERE excluded.day >= pairs.day OR excluded.day < pairs.day - 1`;
// The WHERE above: a device whose numbers are of the day before the stored row (counted before midnight, or in a time
// zone behind) must not put yesterday's numbers back as today's. Only exactly one day back is refused, so a row once
// written with a wrong future clock does not stay frozen until that day comes.

async function handleSync(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ error: 'not linked' }, 401);
  // Taken in one statement: requests sent at once with the same token cannot all pass a check read before the write.
  const slot = await env.DB.prepare('UPDATE owners SET last_sync = ? WHERE token_hash = ? AND last_sync <= ?').bind(now(), owner.token_hash, now() - SYNC_INTERVAL).run();
  if (!(slot.meta && slot.meta.changes)) return json({ error: 'too often' }, 429);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const pairs = Array.isArray(body.pairs) ? body.pairs.slice(0, MAX_PAIRS) : [];
  const need = int(body.need, 1, 100, 3);
  const tz = int(body.tz, -14 * 3600, 14 * 3600, 0);
  // Version 2 apps keep the account's list of streaks here, shared by all of its devices (see syncList).
  const shared = int(body.v, 1, 100, 1) >= 2;
  const t = now();
  const statements = [env.DB.prepare('UPDATE owners SET tz = ? WHERE token_hash = ?').bind(tz, owner.token_hash)];
  const known = new Set(((await env.DB.prepare('SELECT friend_id FROM pairs WHERE owner_id = ?').bind(owner.tg_id).all()).results || []).map((r) => r.friend_id));
  const list = shared ? await syncList(env, owner, body, pairs, t) : null;
  const friendIds = [];
  // An account keeps at most MAX_PAIRS streaks' numbers: a new friend past that is not stored (made-up IDs would
  // otherwise grow the table without end, and the free plan's daily writes run out for everyone).
  let room = MAX_PAIRS - known.size;
  for (const pair of pairs) {
    const friend = int(pair.friend, 1, Number.MAX_SAFE_INTEGER, 0);
    if (!friend || friend === owner.tg_id) continue;
    if (!known.has(friend)) {
      if (room <= 0) continue;
      room--;
    }
    // A streak another device turned off: this device has not heard yet, its numbers are stale.
    if (list && list.stopped.has(friend)) continue;
    friendIds.push(friend);
    const restorable = pair.restorableDay === undefined || pair.restorableDay === null ? null : int(pair.restorableDay, 0, 1e6, 0);
    // The days this device restored (a restore asked for in the bot reaches one device only): kept for the account,
    // so its other devices count them too. Only days of the last year, at most 60 a sync.
    if (list && Array.isArray(pair.restored)) {
      // A restore is of yesterday, and a device syncs every day it is used: only the recent days are new here (older
      // ones were stored when they were recent). The app sends the newest last.
      const day = int(pair.day, 0, 1e6, 0);
      for (const value of pair.restored.slice(-RESTORED_PER_SYNC)) {
        const restoredDay = int(value, 0, 1e6, 0);
        if (restoredDay > 0 && restoredDay < day && restoredDay >= day - RESTORED_DAYS) {
          statements.push(env.DB.prepare('INSERT OR IGNORE INTO streak_restores (owner_id, friend_id, day) VALUES (?, ?, ?)').bind(owner.tg_id, friend, restoredDay));
        }
      }
    }
    statements.push(env.DB.prepare(list ? PAIR_UPSERT_SHARED : PAIR_UPSERT).bind(owner.tg_id, friend, int(pair.count, 0, 1e5), int(pair.mine, 0, 1e6), int(pair.theirs, 0, 1e6), pair.todayDone ? 1 : 0,
      int(pair.restoresLeft, 0, 7), restorable, int(pair.lostCount, 0, 1e5), int(pair.day, 0, 1e6), need, t));
  }
  if (list) {
    // Another device may have streaks this one has not: only what was turned off goes (syncList), and the numbers of a
    // streak nobody counts any more age out with STALE_DAYS.
    for (const friend of list.stopped) {
      statements.push(env.DB.prepare('DELETE FROM pairs WHERE owner_id = ? AND friend_id = ?').bind(owner.tg_id, friend));
    }
  } else {
    // An app before version 2 knows only its own streaks: every pair this sync did not touch is gone (D1 takes at most
    // 100 bound parameters, so no NOT IN over the whole list).
    statements.push(env.DB.prepare('DELETE FROM pairs WHERE owner_id = ? AND updated_at < ?').bind(owner.tg_id, t));
  }
  await env.DB.batch(statements);

  // Whoever started the bot before this streak reached it hears about it now, without pressing anything. Once per
  // pair ever: turning a streak off and on (or a client sending made-up IDs) must not make the bot message anyone again.
  const fresh = friendIds.filter((id) => !known.has(id));
  if (fresh.length > 0) {
    await env.DB.prepare('CREATE TABLE IF NOT EXISTS notified (owner_id INTEGER NOT NULL, friend_id INTEGER NOT NULL, PRIMARY KEY (owner_id, friend_id))').run();
    const name = cleanName(owner.name);
    // The friend IDs come from the owner's app, so the bot tells at most NOTIFY_PER_DAY new people a day about one
    // owner; the rest hear about it on a later day (they are not marked notified until told).
    let budget = NOTIFY_PER_DAY - (await env.DB.prepare('SELECT COUNT(*) AS c FROM notify_log WHERE owner_id = ? AND created_at > ?').bind(owner.tg_id, t - 86400).first()).c;
    for (let i = 0; i < fresh.length && budget > 0; i += D1_CHUNK) {
      const chunk = fresh.slice(i, i + D1_CHUNK);
      const listening = (await env.DB.prepare(
        `SELECT tg_id FROM friends WHERE stopped = 0 AND tg_id IN (${chunk.map(() => '?').join(',')})
           AND tg_id NOT IN (SELECT friend_id FROM notified WHERE owner_id = ?)
           AND tg_id NOT IN (SELECT friend_id FROM muted WHERE owner_id = ?)`
      ).bind(...chunk, owner.tg_id, owner.tg_id).all()).results || [];
      for (const row of listening) {
        if (budget <= 0) break;
        budget--;
        await env.DB.batch([
          env.DB.prepare('INSERT OR IGNORE INTO notified (owner_id, friend_id) VALUES (?, ?)').bind(owner.tg_id, row.tg_id),
          env.DB.prepare('INSERT INTO notify_log (owner_id, created_at) VALUES (?, ?)').bind(owner.tg_id, t),
        ]);
        const reply = await streaksMessage(env, row.tg_id, true);
        reply.text = `🔥 ${name} начал(а) с тобой огонёк!\n\n${reply.text}`;
        // Whoever does not know this person can say so: the bot then never names them here again.
        const mute = [{ text: `🔕 Я не знаю ${name}`, callback_data: `m:${owner.tg_id}` }];
        reply.reply_markup = { inline_keyboard: [...((reply.reply_markup && reply.reply_markup.inline_keyboard) || []), mute] };
        await tg(env, 'sendMessage', { chat_id: row.tg_id, ...reply });
      }
    }
  }

  let restores;
  if (list) {
    // A version 2 app confirms the restores it applied in pair.restored (stored in streak_restores by the batch above):
    // only those go. The others are sent again until confirmed, or until the 3-day cleanup in remind(), so a lost
    // reply (a timeout, the app killed mid-request) does not lose a restore the bot already promised the friend. The
    // app ignores one sent again (it restores only yesterday, and a restored day is a set).
    await env.DB.prepare(
      `DELETE FROM restore_requests WHERE owner_id = ? AND EXISTS (SELECT 1 FROM streak_restores s
         WHERE s.owner_id = restore_requests.owner_id AND s.friend_id = restore_requests.friend_id AND s.day = restore_requests.day)`
    ).bind(owner.tg_id).run();
    restores = await env.DB.prepare('SELECT friend_id, day FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id).all();
  } else {
    // An app before version 2 confirms nothing: the requests are handed over once, read and deleted in one statement,
    // so a request the friend makes meanwhile is not deleted unread.
    restores = await env.DB.prepare('DELETE FROM restore_requests WHERE owner_id = ? RETURNING friend_id, day').bind(owner.tg_id).all();
  }
  const reply = { restores: (restores.results || []).map((r) => ({ friend: r.friend_id, day: r.day })) };
  if (list) {
    reply.streaks = list.active.map((r) => ({ friend: r.friend_id, startDay: r.start_day }));
    reply.stopped = [...list.stopped];
    const restored = (await env.DB.prepare('SELECT friend_id, day FROM streak_restores WHERE owner_id = ?').bind(owner.tg_id).all()).results || [];
    const active = new Set(list.active.map((r) => r.friend_id));
    reply.restored = restored.filter((r) => active.has(r.friend_id)).map((r) => ({ friend: r.friend_id, day: r.day }));
  }
  return json(reply);
}

// The account's list of streaks, shared by its devices: each friend with the day the streak started, or a mark that it
// was turned off (kept STALE_DAYS, so a device that was away for weeks still hears of it). A device sends what the user did on it
// since its last sync, `starts` ({friend, startDay}) and `stops` (friends), at most one of them per friend, and its
// current streaks in `pairs` (with startDay). Its starts and stops are applied first; a pair the list does not know is
// added (that is how the streaks of a device that synced before version 2 get in), and a pair the list has turned off is
// left out: it is the stale copy of a device that has not heard yet. Returns the active rows and the turned-off friends.
async function syncList(env, owner, body, pairs, t) {
  const friendOf = (value) => {
    const friend = int(value, 1, Number.MAX_SAFE_INTEGER, 0);
    return friend && friend !== owner.tg_id ? friend : 0;
  };
  const statements = [];
  // At most MAX_LIST rows per account (streaks and turned-off marks): new friends past it are not stored.
  const listed = new Set(((await env.DB.prepare('SELECT friend_id FROM streak_list WHERE owner_id = ?').bind(owner.tg_id).all()).results || []).map((r) => r.friend_id));
  let room = MAX_LIST - listed.size;
  const fits = (friend) => {
    if (listed.has(friend)) return true;
    if (room <= 0) return false;
    room--;
    listed.add(friend);
    return true;
  };
  const stops = Array.isArray(body.stops) ? body.stops.slice(0, MAX_PAIRS) : [];
  for (const value of stops) {
    const friend = friendOf(value);
    if (!friend || !fits(friend)) continue;
    statements.push(env.DB.prepare(
      `INSERT INTO streak_list (owner_id, friend_id, start_day, stopped, updated_at) VALUES (?, ?, 0, 1, ?)
       ON CONFLICT (owner_id, friend_id) DO UPDATE SET stopped = 1, updated_at = excluded.updated_at`
    ).bind(owner.tg_id, friend, t));
  }
  const starts = Array.isArray(body.starts) ? body.starts.slice(0, MAX_PAIRS) : [];
  for (const start of starts) {
    const friend = friendOf(start && start.friend);
    if (!friend || !fits(friend)) continue;
    statements.push(env.DB.prepare(
      `INSERT INTO streak_list (owner_id, friend_id, start_day, stopped, updated_at) VALUES (?, ?, ?, 0, ?)
       ON CONFLICT (owner_id, friend_id) DO UPDATE SET start_day = excluded.start_day, stopped = 0, updated_at = excluded.updated_at`
    ).bind(owner.tg_id, friend, int(start.startDay, 0, 1e6, 0), t));
  }
  for (const pair of pairs) {
    const friend = friendOf(pair && pair.friend);
    if (!friend || pair.startDay === undefined || pair.startDay === null || !fits(friend)) continue;
    statements.push(env.DB.prepare(
      'INSERT OR IGNORE INTO streak_list (owner_id, friend_id, start_day, stopped, updated_at) VALUES (?, ?, ?, 0, ?)'
    ).bind(owner.tg_id, friend, int(pair.startDay, 0, 1e6, 0), t));
  }
  // The list of an account that syncs stays; its turned-off marks age out.
  statements.push(env.DB.prepare('UPDATE streak_list SET updated_at = ? WHERE owner_id = ? AND stopped = 0').bind(t, owner.tg_id));
  statements.push(env.DB.prepare('DELETE FROM streak_list WHERE owner_id = ? AND stopped = 1 AND updated_at < ?').bind(owner.tg_id, t - STALE_DAYS * 86400));
  await env.DB.batch(statements);
  const rows = (await env.DB.prepare('SELECT friend_id, start_day, stopped FROM streak_list WHERE owner_id = ?').bind(owner.tg_id).all()).results || [];
  return {
    active: rows.filter((r) => !r.stopped),
    stopped: new Set(rows.filter((r) => r.stopped).map((r) => r.friend_id)),
  };
}

// The AstraGram badge. Telegram drops invisible characters from names, so the badge cannot ride in the name: an app
// with the badge on says so here and sends the IDs of the people in its chats and contacts ("check"); it gets back
// which of them show the badge. The whole list is never handed out: any Telegram account can link to the bot, so
// returning it would give anyone the IDs of every AstraGram user. A badge nobody refreshed in BADGE_DAYS is dropped.
const BADGE_DAYS = 45;
const MAX_BADGE_CHECK = 1000;
// /api/gifts makes five chunked lookups per `check` (meta, lists, received, worn, looks): 300 IDs are 4 chunks each,
// which with its fixed queries stays under the free plan's 50 D1 queries per invocation.
const MAX_GIFT_CHECK = 300;
const D1_CHUNK = 90;
// Without a limit, any account (anyone can link one) could sweep ID ranges through `check` and collect every AstraGram
// user. Each account may check this many IDs an hour, over /api/badge and /api/gifts together and all of its devices:
// a real app re-checks its chats every 30 minutes and after a gift action, far below it.
const CHECK_IDS_PER_HOUR = 40000;

// Counts `n` checked IDs against the account's hourly budget; false when it is spent.
async function takeCheckBudget(env, tgId, n, t) {
  if (n === 0) return true;
  const period = Math.floor(t / 3600);
  const row = await env.DB.prepare(
    `INSERT INTO check_budget (tg_id, period, used) VALUES (?, ?, ?)
     ON CONFLICT (tg_id) DO UPDATE SET used = CASE WHEN check_budget.period = excluded.period THEN check_budget.used + excluded.used ELSE excluded.used END,
       period = excluded.period
     RETURNING used`
  ).bind(tgId, period, n).first();
  return !row || row.used <= CHECK_IDS_PER_HOUR;
}

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
  const check = Array.isArray(body.check)
    ? [...new Set(body.check.slice(0, MAX_BADGE_CHECK).map((id) => int(id, 1, Number.MAX_SAFE_INTEGER, 0)).filter((id) => id > 0))]
    : [];
  // The app takes a refusal for a failed refresh and keeps what it had.
  if (!(await takeCheckBudget(env, owner.tg_id, check.length, t))) return json({ error: 'too often' }, 429);
  // A badge-only owner never syncs streaks: this keeps it from being taken for stale.
  await env.DB.prepare('UPDATE owners SET last_sync = ? WHERE token_hash = ? AND last_sync < ?').bind(t, owner.token_hash, t - 86400).run();
  await env.DB.prepare('INSERT INTO badges (tg_id, updated_at) VALUES (?, ?) ON CONFLICT (tg_id) DO UPDATE SET updated_at = excluded.updated_at')
    .bind(owner.tg_id, t).run();
  const users = [];
  for (let i = 0; i < check.length; i += D1_CHUNK) {
    const chunk = check.slice(i, i + D1_CHUNK);
    const rows = (await env.DB.prepare(`SELECT tg_id FROM badges WHERE updated_at >= ? AND tg_id IN (${chunk.map(() => '?').join(',')})`)
      .bind(t - BADGE_DAYS * 86400, ...chunk).all()).results || [];
    for (const r of rows) users.push(r.tg_id);
  }
  return json({ users });
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

// Visual gifts: the gift shop in AstraGram puts Telegram gifts on a profile without buying them; only AstraGram shows
// them. `gifts` (when present) replaces this account's list (at most MAX_VISUAL_GIFTS gift IDs); `check` asks for the
// lists of the people in the app's chats and contacts, the same way the badge does: the whole table is never handed out.
// A list nobody refreshed in VISUAL_GIFT_DAYS is dropped.
const MAX_VISUAL_GIFTS = 100;
const VISUAL_GIFT_DAYS = 90;
// Gifts one AstraGram user gives another for free (only AstraGram shows them). The sender is the token's owner, so it
// cannot be forged; a sender gives at most GIFTS_PER_DAY a day and keeps at most GIFTS_PER_SENDER on one profile, a
// profile holds at most MAX_RECEIVED (a full one takes no more; nothing is pushed off), and the recipient can take any
// of them off (`hide`).
const GIFTS_PER_DAY = 20;
const MAX_RECEIVED = 100;
const GIFTS_PER_SENDER = 10;
const giftId = (id) => ((typeof id === 'string' || Number.isSafeInteger(id)) && /^[0-9]{1,20}$/.test(String(id)) ? String(id) : null);

const MAX_PINNED_GIFTS = 6;
const GIFT_TEXT_MAX = 255;
const giftRef = (ref) => (typeof ref === 'string' && /^[or][0-9]{1,20}$/.test(ref) ? ref : null);

// The look an upgrade gave a gift, as sent to the apps: {n, m, p, b} or null.
function uniqueLook(value) {
  if (!value) return null;
  try {
    const u = JSON.parse(value);
    return u && Number.isSafeInteger(u.n) ? { n: u.n, m: String(u.m || ''), p: String(u.p || ''), b: String(u.b || '') } : null;
  } catch {
    return null;
  }
}

async function ownGiftList(env, tgId) {
  const row = await env.DB.prepare('SELECT gifts FROM visual_gifts WHERE tg_id = ?').bind(tgId).first();
  try {
    return row ? JSON.parse(row.gifts) : [];
  } catch {
    return [];
  }
}

async function saveOwnGiftList(env, tgId, gifts, t) {
  if (gifts.length === 0) {
    await env.DB.prepare('DELETE FROM visual_gifts WHERE tg_id = ?').bind(tgId).run();
    return;
  }
  await env.DB.prepare(`INSERT INTO visual_gifts (tg_id, gifts, updated_at, changed_at) VALUES (?, ?, ?, ?) ON CONFLICT (tg_id) DO UPDATE SET
    changed_at = CASE WHEN visual_gifts.gifts = excluded.gifts THEN visual_gifts.changed_at ELSE excluded.changed_at END,
    gifts = excluded.gifts, updated_at = excluded.updated_at`)
    .bind(tgId, JSON.stringify(gifts), t, t).run();
}

// The gift ID behind one of the owner's refs, or null when the gift is not theirs.
async function ownedGift(env, tgId, ref) {
  if (ref[0] === 'o') {
    const id = ref.slice(1);
    return (await ownGiftList(env, tgId)).includes(id) ? id : null;
  }
  const row = await env.DB.prepare('SELECT gift_id FROM visual_gift_received WHERE id = ? AND to_id = ?').bind(int(ref.slice(1), 1, Number.MAX_SAFE_INTEGER, 0), tgId).first();
  return row ? String(row.gift_id) : null;
}

async function setGiftMeta(env, tgId, ref, fields) {
  const keys = Object.keys(fields);
  await env.DB.prepare(`INSERT INTO visual_gift_meta (tg_id, ref, ${keys.join(', ')}) VALUES (?, ?, ${keys.map(() => '?').join(', ')})
    ON CONFLICT (tg_id, ref) DO UPDATE SET ${keys.map((k) => `${k} = excluded.${k}`).join(', ')}`)
    .bind(tgId, ref, ...keys.map((k) => fields[k])).run();
}

// A Local Premium look as stored and sent: only known fields, IDs as decimal strings (64-bit), colours as small ints.
function premiumLook(value) {
  if (!value || typeof value !== 'object') return null;
  const id = (v) => (typeof v === 'string' && /^-?[0-9]{1,20}$/.test(v)) ? v : (Number.isSafeInteger(v) ? String(v) : undefined);
  const color = (v) => (Number.isInteger(v) && v >= 0 && v < 1000) ? v : undefined;
  const look = {
    status: id(value.status),
    statusUntil: Number.isSafeInteger(value.statusUntil) && value.statusUntil > 0 ? value.statusUntil : undefined,
    nameColor: color(value.nameColor),
    backgroundEmoji: id(value.backgroundEmoji),
    profileColor: color(value.profileColor),
    profileBackgroundEmoji: id(value.profileBackgroundEmoji),
  };
  for (const k of Object.keys(look)) if (look[k] === undefined) delete look[k];
  return look;
}

async function handleGifts(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ error: 'not linked' }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const t = now();
  // The account itself stays in `check`: an app may ask with another linked account's token (the lookup tokens), and
  // that account's gifts must then come back as anyone's would. The app leaves its own ID out when it asks with its own.
  const check = Array.isArray(body.check)
    ? [...new Set(body.check.slice(0, MAX_GIFT_CHECK).map((id) => int(id, 1, Number.MAX_SAFE_INTEGER, 0)).filter((id) => id > 0))]
    : [];
  // Refused before anything changes, so a refused request did nothing (the app takes it for a failure).
  if (!(await takeCheckBudget(env, owner.tg_id, check.length, t))) return json({ error: 'too often' }, 429);
  if (Array.isArray(body.gifts)) {
    // Gift IDs are 64-bit; they travel as decimal strings. A number past 2^53 has already been rounded by JSON.parse, so it
    // is dropped rather than stored as some other gift.
    const gifts = [...new Set(body.gifts.slice(0, MAX_VISUAL_GIFTS).filter((id) => typeof id === 'string' || Number.isSafeInteger(id)).map((id) => String(id)).filter((id) => /^[0-9]{1,20}$/.test(id)))];
    await saveOwnGiftList(env, owner.tg_id, gifts, t);
    // A gift taken off loses what was set on it (put on again, it starts afresh).
    const metaRows = (await env.DB.prepare("SELECT ref FROM visual_gift_meta WHERE tg_id = ? AND ref LIKE 'o%'").bind(owner.tg_id).all()).results || [];
    for (const r of metaRows) {
      if (!gifts.includes(r.ref.slice(1))) await env.DB.prepare('DELETE FROM visual_gift_meta WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, r.ref).run();
    }
  } else {
    await env.DB.prepare('UPDATE visual_gifts SET updated_at = ? WHERE tg_id = ?').bind(t, owner.tg_id).run();
  }
  // Takes one of the GIFTS_PER_DAY a gift given or passed on uses; false when they are used up. The count is kept in
  // its own log, which hiding, trimming and passing gifts on never touch (counting visual_gift_received let a sender
  // whose recipient hides the gifts give without end), and the check and the take are one statement, so two requests
  // at once cannot both take the last one.
  const takeGiftQuota = async () => {
    const taken = await env.DB.prepare(
      'INSERT INTO visual_gift_sends (from_id, created_at) SELECT ?, ? WHERE (SELECT COUNT(*) FROM visual_gift_sends WHERE from_id = ? AND created_at > ?) < ?'
    ).bind(owner.tg_id, t, owner.tg_id, t - 86400, GIFTS_PER_DAY).run();
    return !!(taken.meta && taken.meta.changes);
  };
  // Room on the recipient's profile: gifts are never pushed off it by new ones (someone with a few accounts could
  // otherwise wipe out every gift a person was given). One sender keeps at most GIFTS_PER_SENDER there, and a full
  // profile takes no more until its owner takes some off.
  const hasRoom = async (to) => {
    const row = await env.DB.prepare('SELECT COUNT(*) AS total, SUM(CASE WHEN from_id = ? THEN 1 ELSE 0 END) AS mine FROM visual_gift_received WHERE to_id = ?').bind(owner.tg_id, to).first();
    return !row || (row.total < MAX_RECEIVED && (row.mine || 0) < GIFTS_PER_SENDER);
  };
  let sent = null;
  if (body.send && typeof body.send === 'object') {
    const to = int(body.send.to, 1, Number.MAX_SAFE_INTEGER, 0);
    const gift = giftId(body.send.gift);
    if (!to || to === owner.tg_id || !gift) return json({ error: 'bad gift' }, 400);
    if (!(await hasRoom(to))) return json({ error: 'too many gifts there' }, 429);
    if (!(await takeGiftQuota())) return json({ error: 'too many gifts today' }, 429);
    const inserted = await env.DB.prepare('INSERT INTO visual_gift_received (to_id, from_id, gift_id, created_at) VALUES (?, ?, ?, ?)').bind(to, owner.tg_id, gift, t).run();
    sent = inserted.meta ? inserted.meta.last_row_id : null;
    const text = clip(body.send.text, GIFT_TEXT_MAX);
    if (sent && (text || body.send.anonymous)) {
      await setGiftMeta(env, to, `r${sent}`, { text, anonymous: body.send.anonymous ? 1 : 0 });
    }
  }
  if (Array.isArray(body.hide)) {
    for (const id of body.hide.slice(0, MAX_RECEIVED)) {
      const row = int(id, 1, Number.MAX_SAFE_INTEGER, 0);
      if (!row) continue;
      await env.DB.prepare('DELETE FROM visual_gift_received WHERE id = ? AND to_id = ?').bind(row, owner.tg_id).run();
      await env.DB.prepare('DELETE FROM visual_gift_meta WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, `r${row}`).run();
      await env.DB.prepare('DELETE FROM visual_gift_worn WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, `r${row}`).run();
    }
  }
  // Pinning and hiding, as on Telegram's own gifts: [{ref, pinned?, hidden?}].
  if (Array.isArray(body.meta)) {
    for (const item of body.meta.slice(0, MAX_RECEIVED)) {
      const ref = giftRef(item && item.ref);
      if (!ref || !(await ownedGift(env, owner.tg_id, ref))) continue;
      const fields = {};
      if (typeof item.pinned === 'boolean') {
        if (item.pinned) {
          const pinned = (await env.DB.prepare('SELECT COUNT(*) AS c FROM visual_gift_meta WHERE tg_id = ? AND pinned_at > 0 AND ref != ?').bind(owner.tg_id, ref).first()).c;
          if (pinned >= MAX_PINNED_GIFTS) return json({ error: 'too many pinned' }, 409);
          const current = await env.DB.prepare('SELECT pinned_at FROM visual_gift_meta WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, ref).first();
          fields.pinned_at = current && current.pinned_at > 0 ? current.pinned_at : t;
        } else {
          fields.pinned_at = 0;
        }
      }
      if (typeof item.hidden === 'boolean') {
        fields.hidden = item.hidden ? 1 : 0;
        if (item.hidden) fields.pinned_at = 0;
      }
      if (Object.keys(fields).length) await setGiftMeta(env, owner.tg_id, ref, fields);
    }
  }
  // An upgrade to a unique gift: the app picks the model, pattern and backdrop from Telegram's list for the gift; the
  // server gives it the next number. A gift is upgraded once.
  let upgraded = null;
  if (body.upgrade && typeof body.upgrade === 'object') {
    const ref = giftRef(body.upgrade.ref);
    const gift = ref ? await ownedGift(env, owner.tg_id, ref) : null;
    const m = clip(body.upgrade.model, 64), p = clip(body.upgrade.pattern, 64), b = clip(body.upgrade.backdrop, 64);
    if (!gift || !m || !p || !b) return json({ error: 'bad upgrade' }, 400);
    const current = await env.DB.prepare('SELECT unique_look FROM visual_gift_meta WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, ref).first();
    let look = current ? uniqueLook(current.unique_look) : null;
    // The admin picks every part, the number too, and may change an upgraded gift again.
    if (isAdmin(owner.tg_id)) {
      const number = int(body.upgrade.number, 1, 1000000, 0);
      look = { n: number || (look ? look.n : 0), m, p, b };
      if (!look.n) {
        const counter = await env.DB.prepare('INSERT INTO visual_gift_numbers (gift_id, next) VALUES (?, 2) ON CONFLICT (gift_id) DO UPDATE SET next = next + 1 RETURNING next').bind(gift).first();
        look.n = counter.next - 1;
      }
      await setGiftMeta(env, owner.tg_id, ref, { unique_look: JSON.stringify(look) });
    } else if (!look) {
      const counter = await env.DB.prepare('INSERT INTO visual_gift_numbers (gift_id, next) VALUES (?, 2) ON CONFLICT (gift_id) DO UPDATE SET next = next + 1 RETURNING next').bind(gift).first();
      look = { n: counter.next - 1, m, p, b };
      await setGiftMeta(env, owner.tg_id, ref, { unique_look: JSON.stringify(look) });
    }
    upgraded = { ref, u: look };
  }
  // Passing a gift on to someone else: it leaves this profile (with its upgrade) and shows on theirs, from this account.
  let transferred = null;
  if (body.transfer && typeof body.transfer === 'object') {
    const ref = giftRef(body.transfer.ref);
    const to = int(body.transfer.to, 1, Number.MAX_SAFE_INTEGER, 0);
    const gift = ref ? await ownedGift(env, owner.tg_id, ref) : null;
    if (!gift || !to || to === owner.tg_id) return json({ error: 'bad transfer' }, 400);
    if (!(await hasRoom(to))) return json({ error: 'too many gifts there' }, 429);
    // A gift passed on reaches the other profile as one given does (an own gift can be put on from the shop at will):
    // it counts against the same daily limit.
    if (!(await takeGiftQuota())) return json({ error: 'too many gifts today' }, 429);
    const meta = await env.DB.prepare('SELECT unique_look FROM visual_gift_meta WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, ref).first();
    if (ref[0] === 'o') {
      await saveOwnGiftList(env, owner.tg_id, (await ownGiftList(env, owner.tg_id)).filter((id) => id !== gift), t);
    }
    // A new row, also for a received gift passed on: it is the new owner's gift from this account, dated now.
    const inserted = await env.DB.prepare('INSERT INTO visual_gift_received (to_id, from_id, gift_id, created_at) VALUES (?, ?, ?, ?)').bind(to, owner.tg_id, gift, t).run();
    const row = inserted.meta.last_row_id;
    if (ref[0] === 'r') {
      await env.DB.prepare('DELETE FROM visual_gift_received WHERE id = ? AND to_id = ?').bind(int(ref.slice(1), 1, Number.MAX_SAFE_INTEGER, 0), owner.tg_id).run();
    }
    await env.DB.prepare('DELETE FROM visual_gift_meta WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, ref).run();
    await env.DB.prepare('DELETE FROM visual_gift_worn WHERE tg_id = ? AND ref = ?').bind(owner.tg_id, ref).run();
    const text = clip(body.transfer.text, GIFT_TEXT_MAX);
    const fields = { text, anonymous: body.transfer.anonymous ? 1 : 0 };
    if (meta && meta.unique_look) fields.unique_look = meta.unique_look;
    await setGiftMeta(env, to, `r${row}`, fields);
    transferred = row;
  }
  // Wearing a gift as the status AstraGram shows beside the name: {ref} or null to take it off.
  if (body.wear !== undefined) {
    const ref = body.wear === null ? null : giftRef(body.wear && body.wear.ref);
    if (ref === null) {
      await env.DB.prepare('DELETE FROM visual_gift_worn WHERE tg_id = ?').bind(owner.tg_id).run();
    } else if (await ownedGift(env, owner.tg_id, ref)) {
      await env.DB.prepare('INSERT INTO visual_gift_worn (tg_id, ref, updated_at) VALUES (?, ?, ?) ON CONFLICT (tg_id) DO UPDATE SET ref = excluded.ref, updated_at = excluded.updated_at').bind(owner.tg_id, ref, t).run();
    } else {
      return json({ error: 'bad wear' }, 400);
    }
  }
  // The account's Local Premium look, shown by other AstraGram apps: {...} or null when it is off.
  if (body.premiumLook !== undefined) {
    const look = premiumLook(body.premiumLook);
    if (look === null) {
      await env.DB.prepare('DELETE FROM premium_look WHERE tg_id = ?').bind(owner.tg_id).run();
    } else {
      await env.DB.prepare('INSERT INTO premium_look (tg_id, look, updated_at) VALUES (?, ?, ?) ON CONFLICT (tg_id) DO UPDATE SET look = excluded.look, updated_at = excluded.updated_at').bind(owner.tg_id, JSON.stringify(look), t).run();
    }
  }
  await env.DB.prepare('UPDATE owners SET last_sync = ? WHERE token_hash = ? AND last_sync < ?').bind(t, owner.token_hash, t - 86400).run();
  const inList = (chunk) => chunk.map(() => '?').join(',');
  // The account and the checked people, once each.
  const wornIds = [...new Set([owner.tg_id, ...check])];
  // What the owners set on their gifts, by owner and ref (with their hidden gifts, which only the owner gets).
  const metaOf = {};
  const metaRows = async (ids) => {
    for (let i = 0; i < ids.length; i += D1_CHUNK) {
      const chunk = ids.slice(i, i + D1_CHUNK);
      const rows = (await env.DB.prepare(`SELECT * FROM visual_gift_meta WHERE tg_id IN (${inList(chunk)})`).bind(...chunk).all()).results || [];
      for (const r of rows) (metaOf[r.tg_id] = metaOf[r.tg_id] || {})[r.ref] = r;
    }
  };
  await metaRows(wornIds);
  const metaFor = (tgId, ref) => (metaOf[tgId] || {})[ref];
  const isHidden = (tgId, ref) => !!(metaFor(tgId, ref) && metaFor(tgId, ref).hidden);
  // The settings an app shows on a gift; only the owner learns which are hidden.
  const shownMeta = (tgId, ref, forOwner) => {
    const m = metaFor(tgId, ref);
    if (!m) return null;
    const out = {};
    if (m.pinned_at > 0) out.pin = m.pinned_at;
    const u = uniqueLook(m.unique_look);
    if (u) out.u = u;
    if (forOwner && m.hidden) out.hidden = true;
    return Object.keys(out).length ? out : null;
  };

  const users = {};
  // When each list last changed: shown as the date of the gifts in it.
  const usersDate = {};
  const usersMeta = {};
  for (let i = 0; i < check.length; i += D1_CHUNK) {
    const chunk = check.slice(i, i + D1_CHUNK);
    const rows = (await env.DB.prepare(`SELECT tg_id, gifts, changed_at FROM visual_gifts WHERE updated_at >= ? AND tg_id IN (${inList(chunk)})`)
      .bind(t - VISUAL_GIFT_DAYS * 86400, ...chunk).all()).results || [];
    for (const r of rows) {
      try {
        const list = JSON.parse(r.gifts).filter((id) => !isHidden(r.tg_id, `o${id}`));
        users[r.tg_id] = list;
        usersDate[r.tg_id] = r.changed_at || 0;
        for (const id of list) {
          const m = shownMeta(r.tg_id, `o${id}`, false);
          if (m) (usersMeta[r.tg_id] = usersMeta[r.tg_id] || {})[id] = m;
        }
      } catch {
        // A broken row is skipped.
      }
    }
  }
  // A received gift as an app gets it; an anonymous giver is named only to the recipient.
  const receivedRow = (r, forOwner) => {
    const m = metaFor(r.to_id, `r${r.id}`);
    const anonymous = !!(m && m.anonymous);
    const out = { id: r.id, gift: r.gift_id, from: anonymous && !forOwner ? 0 : r.from_id, date: r.created_at };
    if (m && m.text) out.text = m.text;
    if (anonymous) out.anon = true;
    const shown = shownMeta(r.to_id, `r${r.id}`, forOwner);
    if (shown) Object.assign(out, shown);
    return out;
  };
  const received = {};
  for (let i = 0; i < check.length; i += D1_CHUNK) {
    const chunk = check.slice(i, i + D1_CHUNK);
    const rows = (await env.DB.prepare(`SELECT id, to_id, from_id, gift_id, created_at FROM visual_gift_received WHERE to_id IN (${inList(chunk)}) ORDER BY id DESC`)
      .bind(...chunk).all()).results || [];
    for (const r of rows) {
      if (!isHidden(r.to_id, `r${r.id}`)) (received[r.to_id] = received[r.to_id] || []).push(receivedRow(r, false));
    }
  }
  const mineReceived = ((await env.DB.prepare('SELECT id, to_id, from_id, gift_id, created_at FROM visual_gift_received WHERE to_id = ? ORDER BY id DESC').bind(owner.tg_id).all()).results || []).map((r) => receivedRow(r, true));
  const mine = await ownGiftList(env, owner.tg_id);
  const mineMeta = {};
  for (const id of mine) {
    const m = shownMeta(owner.tg_id, `o${id}`, true);
    if (m) mineMeta[id] = m;
  }
  // The gifts worn as a status: the account's own and the checked people's (a hidden gift is not shown worn).
  // Whether a worn ref is still its wearer's gift, from the lists loaded above rather than a query per wearer (which
  // would take a full `check` past the free plan's D1 query limit). A hidden gift is left out of the others' lists,
  // and is not shown worn for them anyway.
  const ownedRef = (tgId, ref) => {
    if (ref[0] === 'o') {
      const list = tgId === owner.tg_id ? mine : users[tgId];
      return list && list.map(String).includes(ref.slice(1)) ? ref.slice(1) : null;
    }
    const id = int(ref.slice(1), 1, Number.MAX_SAFE_INTEGER, 0);
    const list = tgId === owner.tg_id ? mineReceived : received[tgId];
    const r = list && list.find((x) => x.id === id);
    return r ? String(r.gift) : null;
  };
  const worn = {};
  for (let i = 0; i < wornIds.length; i += D1_CHUNK) {
    const chunk = wornIds.slice(i, i + D1_CHUNK);
    const rows = (await env.DB.prepare(`SELECT tg_id, ref FROM visual_gift_worn WHERE tg_id IN (${inList(chunk)})`).bind(...chunk).all()).results || [];
    for (const r of rows) {
      if (r.tg_id !== owner.tg_id && isHidden(r.tg_id, r.ref)) continue;
      const gift = ownedRef(r.tg_id, r.ref);
      if (!gift) continue;
      const m = metaFor(r.tg_id, r.ref);
      worn[r.tg_id] = { ref: r.ref, gift, u: m ? uniqueLook(m.unique_look) : null };
    }
  }
  // The Local Premium looks of the account and of the checked people.
  const premiumLooks = {};
  for (let i = 0; i < wornIds.length; i += D1_CHUNK) {
    const chunk = wornIds.slice(i, i + D1_CHUNK);
    const rows = (await env.DB.prepare(`SELECT tg_id, look FROM premium_look WHERE tg_id IN (${inList(chunk)})`).bind(...chunk).all()).results || [];
    for (const r of rows) {
      try {
        const look = premiumLook(JSON.parse(r.look));
        if (look) premiumLooks[r.tg_id] = look;
      } catch {}
    }
  }
  const reply = { users, usersDate, usersMeta, received, mine, mineMeta, mineReceived, worn, premiumLooks };
  if (sent !== null) reply.sent = sent;
  if (upgraded) reply.upgraded = upgraded;
  if (transferred !== null) reply.transferred = transferred;
  return json(reply);
}

// ---------------------------------------------------------------------------------------------------------------
// Feedback (bug reports, ideas) and donations, both from AstraGram's settings.

const FEEDBACK_PER_HOUR = 5;
// Feedback from senders without a streak-bot link, from all addresses together, an hour: an attacker with a whole IPv6
// range must not bury the admin's inbox.
const UNVERIFIED_FEEDBACK_PER_HOUR = 60;
const FEEDBACK_KEEP_DAYS = 180;

// The address a sender is limited by: an IPv4 address, or an IPv6 address's /64 (one home or one server gets a whole
// /64, and could otherwise change address with every request).
function feedbackSource(ip) {
  if (!ip.includes(':')) return ip;
  const [head, tail = ''] = ip.split('::');
  const left = head ? head.split(':') : [];
  const right = ip.includes('::') && tail ? tail.split(':') : [];
  const groups = ip.includes('::') ? [...left, ...Array(Math.max(0, 8 - left.length - right.length)).fill('0'), ...right] : left;
  return groups.slice(0, 4).map((g) => (g || '0').toLowerCase().replace(/^0+(?=.)/, '')).join(':') + '::/64';
}
const FEEDBACK_MAX_LENGTH = 4000;
const DONATION_MIN = 1;
const DONATION_MAX = 10000;

function clip(value, max) {
  return String(value || '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').slice(0, max).trim();
}

// No streak-bot link is needed to send feedback; at most FEEDBACK_PER_HOUR an hour from one address. The sender's account
// is named only when they let the app do so, and marked unproven unless their streak-bot token came with it.
async function handleFeedback(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const text = clip(body.text, FEEDBACK_MAX_LENGTH);
  if (text.length < 3) return json({ error: 'empty' }, 400);
  const kind = body.kind === 'idea' ? 'idea' : 'bug';
  const t = now();
  const ip = feedbackSource(request.headers.get('cf-connecting-ip') || '');
  const recent = (await env.DB.prepare('SELECT COUNT(*) AS c FROM feedback WHERE ip = ? AND created_at > ?').bind(ip, t - 3600).first()).c;
  if (recent >= FEEDBACK_PER_HOUR) return json({ error: 'too often' }, 429);

  const owner = request.headers.get('authorization') ? await ownerFromRequest(request, env) : null;
  if (!owner) {
    const unverified = (await env.DB.prepare('SELECT COUNT(*) AS c FROM feedback WHERE verified = 0 AND created_at > ?').bind(t - 3600).first()).c;
    if (unverified >= UNVERIFIED_FEEDBACK_PER_HOUR) return json({ error: 'too often' }, 429);
  }
  const claimedId = int(body.userId, 1, Number.MAX_SAFE_INTEGER, 0);
  const tgId = owner ? owner.tg_id : (claimedId || null);
  const verified = owner ? 1 : 0;
  const app = clip([body.version, body.build && `(${body.build})`, body.os, body.device].filter(Boolean).join(' · '), 200);
  const inserted = await env.DB.prepare('INSERT INTO feedback (kind, text, tg_id, verified, ip, app, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(kind, text, tgId, verified, ip, app, t).run();
  const id = inserted.meta ? inserted.meta.last_row_id : 0;

  const name = clip(body.name, 64);
  const username = clip(body.username, 64).replace(/[^A-Za-z0-9_]/g, '');
  let who = 'аноним';
  if (tgId) {
    who = `${name || 'пользователь'}${username ? ' @' + username : ''} (id ${tgId}${verified ? '' : ', не подтверждён'})`;
  }
  const header = kind === 'idea' ? '💡 Идея' : '🐞 Ошибка';
  // A reply reaches the author only when their account is proven: a claimed userId is whatever the sender typed, and
  // the admin's answer would go to that person's chat.
  const reply = verified
    ? '\n\nОтветьте на это сообщение — ответ уйдёт автору в чат с ботом (если он его запускал).'
    : (tgId ? '\n\nОтправитель не подтверждён — ответ через бота не доставляется.' : '');
  const { key } = await sendInbox(env, kind, { text: `${header} #${id}\nОт: ${who}\n${app}\n\n${text}${reply}` });
  if (verified && tgId && key) {
    await env.DB.prepare('INSERT OR REPLACE INTO support (admin_msg_id, user_id, created_at) VALUES (?, ?, ?)').bind(key, tgId, t).run();
  }
  return json({ ok: true, id });
}

// A Stars invoice link for a donation: the app opens it and Telegram shows its own payment sheet, with no chat.
async function handleDonate(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const stars = Number(body.stars);
  if (!Number.isInteger(stars) || stars < DONATION_MIN || stars > DONATION_MAX) return json({ error: 'bad amount' }, 400);
  const ru = body.lang !== 'en';
  const reply = await tg(env, 'createInvoiceLink', {
    title: ru ? 'Поддержать AstraGram' : 'Support AstraGram',
    description: ru ? 'Спасибо, что помогаете AstraGram развиваться!' : 'Thank you for helping AstraGram grow!',
    payload: `donate:${stars}`,
    currency: 'XTR',
    prices: [{ label: ru ? 'Поддержка AstraGram' : 'AstraGram support', amount: stars }],
  });
  if (!reply.ok || typeof reply.result !== 'string') return json({ error: 'telegram' }, 502);
  return json({ link: reply.result });
}

async function handlePreCheckout(env, query) {
  const match = String(query.invoice_payload || '').match(/^donate:(\d+)$/);
  const ok = Boolean(match && query.currency === 'XTR' && Number(match[1]) === query.total_amount);
  await tg(env, 'answerPreCheckoutQuery', ok
    ? { pre_checkout_query_id: query.id, ok: true }
    : { pre_checkout_query_id: query.id, ok: false, error_message: 'Счёт устарел, попробуйте ещё раз' });
}

async function handleSuccessfulPayment(env, message) {
  const payment = message.successful_payment;
  const match = String(payment.invoice_payload || '').match(/^donate:(\d+)$/);
  if (!match || payment.currency !== 'XTR') return;
  const from = message.from;
  const ru = isRussian(from);
  await tg(env, 'sendMessage', {
    chat_id: from.id,
    text: ru ? `💛 Спасибо за поддержку AstraGram — ${payment.total_amount} ⭐!` : `💛 Thank you for supporting AstraGram — ${payment.total_amount} ⭐!`,
  });
  const uname = from.username ? ` @${from.username}` : '';
  await sendInbox(env, 'donate', { text: `💛 Донат ${payment.total_amount} ⭐ от ${cleanName(from.first_name)}${uname} (id ${from.id})` });
}

async function handleUnlink(request, env) {
  const owner = await ownerFromRequest(request, env);
  if (!owner) return json({ ok: true });
  await env.DB.batch([
    env.DB.prepare('DELETE FROM owners WHERE tg_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM pairs WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM streak_list WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM restore_requests WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM streak_restores WHERE owner_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM badges WHERE tg_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM visual_gifts WHERE tg_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM premium_look WHERE tg_id = ?').bind(owner.tg_id),
    env.DB.prepare('DELETE FROM visual_gift_received WHERE to_id = ? OR from_id = ?').bind(owner.tg_id, owner.tg_id),
  ]);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------------------------------------------
// Linking without the bot's chat: the app asks Telegram for the bot's web-app data (messages.requestSimpleWebView),
// which Telegram signs with a key made from the bot token and which names the account. Nothing is sent to the bot's
// chat. The app's new token (in Authorization) is tied to the Telegram ID the signed data names.
const LOGIN_MAX_AGE = 600;

async function hmac(keyBytes, text) {
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(text)));
}

// The user ({id, first_name, ...}) the web-app data names, or null when the signature or its age does not hold.
async function verifiedWebAppUser(env, initData, t) {
  if (!env.BOT_TOKEN || typeof initData !== 'string' || initData.length > 4096) return null;
  const params = new URLSearchParams(initData);
  const hash = params.get('hash');
  if (!hash || !/^[0-9a-f]{64}$/.test(hash)) return null;
  const lines = [];
  for (const [key, value] of params) {
    if (key !== 'hash') lines.push(`${key}=${value}`);
  }
  lines.sort();
  const secret = await hmac(new TextEncoder().encode('WebAppData'), env.BOT_TOKEN);
  const signed = [...await hmac(secret, lines.join('\n'))].map((b) => b.toString(16).padStart(2, '0')).join('');
  if (!timingSafeEqual(signed, hash)) return null;
  const authDate = Number(params.get('auth_date'));
  if (!Number.isFinite(authDate) || Math.abs(t - authDate) > LOGIN_MAX_AGE) return null;
  try {
    const user = JSON.parse(params.get('user') || '');
    return user && Number.isSafeInteger(user.id) && user.id > 0 ? user : null;
  } catch {
    return null;
  }
}

async function handleLogin(request, env) {
  const auth = request.headers.get('authorization') || '';
  const match = auth.match(/^Bearer ([0-9a-f]{48})$/);
  if (!match) return json({ ok: false, error: 'token' }, 400);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, error: 'body' }, 400);
  }
  const t = now();
  const user = await verifiedWebAppUser(env, body && body.initData, t);
  if (!user) return json({ ok: false, error: 'signature' }, 403);
  if (!(await linkOwner(env, await sha256Hex(match[1]), user.id, user.first_name, t))) return json({ ok: false, error: 'token' }, 409);
  await rememberProfile(env, user);
  return json({ ok: true, id: user.id });
}

// Up to 5 linked devices per account (a phone and an iPad must not keep unlinking each other): the oldest go. A token
// already tied to another account is never handed over (whoever knows it would act as the new account); returns
// whether the token is now linked.
async function linkOwner(env, hash, tgId, firstName, t) {
  const existing = await env.DB.prepare('SELECT tg_id FROM owners WHERE token_hash = ?').bind(hash).first();
  if (existing && existing.tg_id !== tgId) return false;
  await env.DB.batch([
    env.DB.prepare('DELETE FROM owners WHERE tg_id = ? AND token_hash NOT IN (SELECT token_hash FROM owners WHERE tg_id = ? ORDER BY created_at DESC LIMIT 4)').bind(tgId, tgId),
    env.DB.prepare('INSERT OR REPLACE INTO owners (token_hash, tg_id, name, created_at) VALUES (?, ?, ?, ?)').bind(hash, tgId, cleanName(firstName), t),
  ]);
  return true;
}

// ---------------------------------------------------------------------------------------------------------------
// The bot

async function streaksMessage(env, userId, ru) {
  const rows = (await env.DB.prepare(
    `SELECT p.*, o.name AS owner_name, o.tz AS owner_tz FROM pairs p JOIN ${LATEST_OWNER} o ON o.tg_id = p.owner_id
     WHERE p.friend_id = ? AND p.owner_id NOT IN (SELECT owner_id FROM muted WHERE friend_id = ?) ORDER BY p.count DESC`
  ).bind(userId, userId).all()).results || [];
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
    if (canRestore(row, t)) {
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
  if (!from || from.is_bot) return;
  if (message.chat.type === 'supergroup' && isAdmin(from.id)) {
    await handleInboxMessage(env, message);
    return;
  }
  if (message.chat.type !== 'private') return;
  const ru = isRussian(from);
  const text = (message.text || '').trim();
  const t = now();

  // Linking by "/start l<token>" asks first: anyone can make a token and send someone the link, and pressing Start
  // alone would tie that token to the presser's account, letting the link's author act as them. The token is linked
  // when the button is pressed (handleCallback). The app's usual way to link is /api/login, with Telegram's signature.
  const link = text.match(/^\/start l([0-9a-f]{48})$/);
  if (link) {
    await tg(env, 'sendMessage', {
      chat_id: from.id,
      text: ru
        ? 'Подключить AstraGram к вашему аккаунту? Нажимайте, только если вы сами только что подключали бота огоньков в своём AstraGram. Если ссылку прислал кто-то другой — не нажимайте: он получит доступ к вашим огонькам и подаркам.'
        : 'Connect AstraGram to your account? Press only if you just connected the streak bot in your own AstraGram. If someone else sent you this link, do not press: they would get access to your streaks and gifts.',
      // "l:" and 48 hex digits are 50 bytes, under Telegram's 64-byte limit for callback data.
      reply_markup: { inline_keyboard: [[{ text: ru ? '✅ Подключить' : '✅ Connect', callback_data: `l:${link[1]}` }]] },
    });
    return;
  }

  // A payment's service message has no text: it must not fall into the admin's panel below.
  if (message.successful_payment) {
    await handleSuccessfulPayment(env, message);
    return;
  }

  // The admin's chat is the control panel and the support inbox.
  if (isAdmin(from.id)) {
    if (await handleAdminMessage(env, message)) return;
  }

  if (text === '/paysupport') {
    await tg(env, 'sendMessage', {
      chat_id: from.id,
      text: ru
        ? 'Вопрос по оплате? Напишите его сюда одним сообщением (сумму и когда платили) — оно попадёт в поддержку AstraGram, и вам ответят здесь.'
        : 'A question about a payment? Write it here in one message (the amount and when you paid): it reaches AstraGram support and they reply here.',
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
      // The owner is named only to someone in their list of streaks: the same reply for any other ID, so "/start f<id>"
      // cannot tell anyone which IDs use AstraGram, nor their names.
      const listed = await env.DB.prepare('SELECT 1 FROM streak_list WHERE owner_id = ? AND friend_id = ? AND stopped = 0').bind(ownerId, from.id).first();
      const owner = listed ? await env.DB.prepare('SELECT name FROM owners WHERE tg_id = ?').bind(ownerId).first() : null;
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
  // The confirmation of "/start l<token>" (see handleMessage): the token is tied to whoever pressed it.
  const linkMatch = (callback.data || '').match(/^l:([0-9a-f]{48})$/);
  if (linkMatch) {
    const ok = await linkOwner(env, await sha256Hex(linkMatch[1]), from.id, from.first_name, now());
    await tg(env, 'answerCallbackQuery', { callback_query_id: callback.id });
    await tg(env, 'sendMessage', {
      chat_id: from.id,
      text: !ok
        ? (ru ? 'Эта ссылка уже использована другим аккаунтом.' : 'This link was already used by another account.')
        : ru
          ? '✅ AstraGram подключён к боту огоньков.\n\nТе, с кем у вас огонёк и у кого нет AstraGram, увидят здесь счёт, получат напоминание вечером и смогут восстановить пропущенный день. Пригласить человека можно с экрана огонька в AstraGram.\n\nБоту приходят только числа, тексты сообщений — никогда. Отключить: AstraGram → огонёк → «Отключить бота огоньков».'
          : '✅ AstraGram is connected to the streak bot.\n\nPeople you have a streak with who do not use AstraGram see the count here, get a reminder in the evening and can restore a missed day. Invite someone from the streak screen in AstraGram.\n\nThe bot gets only numbers, never message texts. To disconnect: AstraGram → streak → Disconnect Streak Bot.',
    });
    return;
  }
  const muteMatch = (callback.data || '').match(/^m:(\d{1,20})$/);
  if (muteMatch) {
    await env.DB.prepare('INSERT OR IGNORE INTO muted (friend_id, owner_id) VALUES (?, ?)').bind(from.id, Number(muteMatch[1])).run();
    await tg(env, 'answerCallbackQuery', {
      callback_query_id: callback.id,
      text: ru ? 'Готово: этот человек больше не появится здесь, напоминаний от него не будет.' : 'Done: this person no longer shows up here, and you get no reminders about them.',
      show_alert: true,
    });
    return;
  }
  const match = (callback.data || '').match(/^r:(\d+)$/);
  let answer = ru ? 'Не получилось' : 'Could not do that';
  if (match) {
    const ownerId = Number(match[1]);
    const t = now();
    const pair = await env.DB.prepare(`SELECT p.*, o.name AS owner_name, o.tz AS owner_tz FROM pairs p JOIN ${LATEST_OWNER} o ON o.tg_id = p.owner_id WHERE p.owner_id = ? AND p.friend_id = ?`).bind(ownerId, from.id).first();
    if (pair && canRestore(pair, t)) {
      await env.DB.prepare('INSERT OR IGNORE INTO restore_requests (owner_id, friend_id, day, created_at) VALUES (?, ?, ?, ?)').bind(ownerId, from.id, pair.restorable_day, t).run();
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
  let target = await inboxTarget(env, 'support');
  let fwd = await tg(env, 'forwardMessage', { ...target.to, from_chat_id: from.id, message_id: message.message_id });
  if (!fwd.ok && target.to.chat_id !== ADMIN_ID && !/forward/i.test(fwd.description || '')) {
    // The group is gone: the admin's chat.
    target = { to: { chat_id: ADMIN_ID }, key: (id) => id };
    fwd = await tg(env, 'forwardMessage', { ...target.to, from_chat_id: from.id, message_id: message.message_id });
  }
  let adminMsgId = fwd.ok && fwd.result ? target.key(fwd.result.message_id) : null;
  if (!adminMsgId) {
    // Forwarding can be refused (privacy); fall back to a header plus a copy of the content.
    const uname = from.username ? ` @${from.username}` : '';
    await tg(env, 'sendMessage', { ...target.to, text: `💬 ${cleanName(from.first_name)}${uname} (id ${from.id}):` });
    const copied = await tg(env, 'copyMessage', { ...target.to, from_chat_id: from.id, message_id: message.message_id });
    adminMsgId = copied.ok && copied.result ? target.key(copied.result.message_id) : null;
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
  const inserted = await env.DB.prepare('INSERT INTO broadcasts (total, created_at) VALUES (?, ?)').bind(ids.length, t).run();
  const broadcastId = inserted.meta ? inserted.meta.last_row_id : (await env.DB.prepare('SELECT MAX(id) AS id FROM broadcasts').first()).id;
  const statements = ids.map((id) => env.DB.prepare('INSERT INTO broadcast_queue (broadcast_id, chat_id, from_chat, msg_id, created_at) VALUES (?, ?, ?, ?, ?)').bind(broadcastId, id, fromChat, msgId, t));
  for (let i = 0; i < statements.length; i += 50) {
    await env.DB.batch(statements.slice(i, i + 50));
  }
  return ids.length;
}

async function drainBroadcast(env) {
  // The rows are claimed (taken out of the queue) before sending, in one statement: a drain from the webhook and one
  // from the cron at the same time never get the same rows, so nobody gets the post twice.
  const rows = ((await env.DB.prepare('DELETE FROM broadcast_queue WHERE id IN (SELECT id FROM broadcast_queue ORDER BY id LIMIT ?) RETURNING *').bind(BROADCAST_BATCH).all()).results || [])
    .sort((a, b) => a.id - b.id);
  const touched = new Set();
  // The counts are written once per broadcast at the end, not per message: with a query or two per message a batch
  // went past the free plan's 50 D1 queries, and the query that failed came after its message had been sent.
  const counts = new Map();
  const stopped = [];
  let unsent = [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const res = await tg(env, 'copyMessage', { chat_id: row.chat_id, from_chat_id: row.from_chat, message_id: row.msg_id });
    if (!res.ok && res.error_code === 429) {
      // Rate limited: stop and put the rest back for the next drain (the cron runs every minute).
      unsent = rows.slice(i);
      break;
    }
    const c = counts.get(row.broadcast_id) || { delivered: 0, failed: 0 };
    if (res.ok) {
      c.delivered++;
    } else {
      c.failed++;
      // Blocked the bot: no more broadcasts or reminders to them.
      if (res.error_code === 403) stopped.push(row.chat_id);
    }
    counts.set(row.broadcast_id, c);
    touched.add(row.broadcast_id);
  }
  const statements = [];
  for (const [id, c] of counts) {
    statements.push(env.DB.prepare('UPDATE broadcasts SET delivered = delivered + ?, failed = failed + ? WHERE id = ?').bind(c.delivered, c.failed, id));
  }
  for (const chatId of stopped) {
    statements.push(env.DB.prepare('UPDATE friends SET stopped = 1 WHERE tg_id = ?').bind(chatId));
  }
  // Put back with their own ids, so the queue keeps its order.
  for (const r of unsent) {
    statements.push(env.DB.prepare('INSERT INTO broadcast_queue (id, broadcast_id, chat_id, from_chat, msg_id, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(r.id, r.broadcast_id, r.chat_id, r.from_chat, r.msg_id, r.created_at));
  }
  if (statements.length) await env.DB.batch(statements);
  // Report each broadcast that has now fully drained, once: marking it done is one statement, so two drains at once
  // do not both report it. A row another drain has claimed is no longer in the queue while it is being sent, so an
  // empty queue alone is not enough: every recipient must also be counted.
  for (const id of touched) {
    const remaining = (await env.DB.prepare('SELECT COUNT(*) AS c FROM broadcast_queue WHERE broadcast_id = ?').bind(id).first()).c;
    if (remaining > 0) {
      continue;
    }
    const b = await env.DB.prepare('UPDATE broadcasts SET done = 1 WHERE id = ? AND done = 0 AND delivered + failed >= total RETURNING *').bind(id).first();
    if (!b) {
      continue;
    }
    let text = `✅ <b>Рассылка завершена</b>\n\nДоставлено: <b>${b.delivered}</b> из <b>${b.total}</b>`;
    if (b.failed > 0) {
      text += `\nНе доставлено: ${b.failed} (остановили бота)`;
    }
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, text, parse_mode: 'HTML' });
  }
}

function adminPanel() {
  return {
    text: '🛠 <b>Панель администратора</b>\n\n• Ответьте <b>reply</b> на пересланное сообщение пользователя, чтобы написать ему.\n• «Новый пост» — рассылка всем.',
    parse_mode: 'HTML',
    reply_markup: { inline_keyboard: [
      [{ text: '📢 Новый пост', callback_data: 'bc:new' }],
      [{ text: '📊 Статистика', callback_data: 'bc:stats' }],
      ...(workerOrigin ? [[{ text: '🛡 Админ-панель', web_app: { url: `${workerOrigin}/admin` } }]] : []),
    ] },
  };
}

async function adminStats(env) {
  const reach = (await broadcastRecipients(env)).length;
  // One row per linked device: the accounts are counted once.
  const owners = (await env.DB.prepare('SELECT COUNT(DISTINCT tg_id) AS c FROM owners').first()).c;
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
// The admin in a group: /inbox makes it the inbox (its topics created once); a reply there to a user's message is
// relayed to that user, as in the admin's chat.
async function handleInboxMessage(env, message) {
  const chat = message.chat.id;
  const text = (message.text || '').trim();
  if (/^\/inbox(@\w+)?$/.test(text)) {
    if (!message.chat.is_forum) {
      await tg(env, 'sendMessage', { chat_id: chat, text: 'Включите в группе «Темы», затем снова /inbox.' });
      return;
    }
    const old = await inbox(env);
    const box = { chat };
    for (const topic of INBOX_TOPICS) {
      if (old && old.chat === chat && old[topic.key]) {
        box[topic.key] = old[topic.key];
        continue;
      }
      const made = await tg(env, 'createForumTopic', { chat_id: chat, name: topic.name, icon_color: topic.color });
      if (!made.ok) {
        await tg(env, 'sendMessage', { chat_id: chat, text: '⚠️ Не удалось создать темы: сделайте бота администратором с правом «Управление темами».' });
        return;
      }
      box[topic.key] = made.result.message_thread_id;
    }
    await kvSet(env, 'inbox', JSON.stringify(box));
    for (const topic of INBOX_TOPICS) {
      if (old && old.chat === chat && old[topic.key]) continue;
      await tg(env, 'sendMessage', { chat_id: chat, message_thread_id: box[topic.key], text: {
        bug: 'Сюда приходят ошибки из AstraGram → «Ошибки и идеи». Ответьте на сообщение — ответ уйдёт автору.',
        idea: 'Сюда приходят идеи из AstraGram → «Ошибки и идеи». Ответьте на сообщение — ответ уйдёт автору.',
        donate: 'Сюда приходят донаты из AstraGram → «Поддержать AstraGram».',
        support: 'Сюда приходят сообщения, написанные боту. Ответьте на сообщение — ответ уйдёт человеку.',
      }[topic.key] });
    }
    await tg(env, 'setMessageReaction', { chat_id: chat, message_id: message.message_id, reaction: [{ type: 'emoji', emoji: '👍' }] });
    return;
  }
  const box = await inbox(env);
  if (!box || box.chat !== chat || !message.reply_to_message) return;
  const row = await env.DB.prepare('SELECT user_id FROM support WHERE admin_msg_id = ?').bind(INBOX_KEY + message.reply_to_message.message_id).first();
  if (!row) return;
  const res = await tg(env, 'copyMessage', { chat_id: row.user_id, from_chat_id: chat, message_id: message.message_id });
  await tg(env, 'setMessageReaction', { chat_id: chat, message_id: message.message_id, reaction: [{ type: 'emoji', emoji: res.ok ? '👍' : '👎' }] });
  if (!res.ok) {
    await tg(env, 'sendMessage', { chat_id: chat, message_thread_id: message.message_thread_id, reply_parameters: { message_id: message.message_id }, text: '⚠️ Не доставлено — человек не запускал бота или остановил его.' });
  }
}

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
      { command: 'admin', description: '🛡 Админ-панель (мини-приложение)' },
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
  if (text === '/admin') {
    await tg(env, 'sendMessage', { chat_id: ADMIN_ID, ...adminAppButton() });
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
  // Without the token the secret would be a hash of a known string: anyone could forge updates (link any token to any
  // account) in the minutes before the first deploy sets it.
  if (!env.BOT_TOKEN) return new Response('not configured', { status: 503 });
  if (!timingSafeEqual(request.headers.get('x-telegram-bot-api-secret-token') || '', await webhookSecret(env))) {
    return new Response('forbidden', { status: 403 });
  }
  workerOrigin = new URL(request.url).origin;
  const update = await request.json().catch(() => null);
  if (update) {
    try {
      const who = (update.message && update.message.from) || (update.callback_query && update.callback_query.from);
      if (who && !who.is_bot) await rememberProfile(env, who);
      if (update.message) await handleMessage(env, update.message);
      else if (update.callback_query) await handleCallback(env, update.callback_query);
      else if (update.pre_checkout_query) await handlePreCheckout(env, update.pre_checkout_query);
    } catch (error) {
      console.error('update failed', error && error.message);
    }
  }
  return new Response('ok');
}

// ---------------------------------------------------------------------------------------------------------------
// Reminders

// Messages one reminder run sends at most (each is one Telegram call): the rest are sent by the next run, ten minutes
// later in the same evening hour. Planted pairs that all fall due at once cannot take a run past its limits.
const REMIND_BATCH = 40;

async function remind(env) {
  const t = now();
  const rows = (await env.DB.prepare(
    `SELECT p.*, o.name AS owner_name, o.tz AS tz FROM pairs p
     JOIN ${LATEST_OWNER} o ON o.tg_id = p.owner_id
     JOIN friends f ON f.tg_id = p.friend_id AND f.stopped = 0
     WHERE p.updated_at > ? AND p.today_done = 0 AND p.theirs < p.need AND p.reminded_day < p.day AND (p.count > 0 OR p.lost_count > 0)
       AND NOT EXISTS (SELECT 1 FROM muted m WHERE m.friend_id = p.friend_id AND m.owner_id = p.owner_id)`
  ).bind(t - 36 * 3600).all()).results || [];
  const due = rows.filter((row) => {
    const localHour = Math.floor(((t + row.tz) % 86400) / 3600);
    const localDay = Math.floor((t + row.tz) / 86400);
    return localHour === 19 && localDay === row.day;
  }).slice(0, REMIND_BATCH);
  if (due.length === 0) return;
  // Marked first, in one batch: a run cut short sends nothing twice.
  await env.DB.batch(due.map((row) => env.DB.prepare('UPDATE pairs SET reminded_day = ? WHERE owner_id = ? AND friend_id = ?').bind(row.day, row.owner_id, row.friend_id)));
  for (const row of due) {
    row.owner_name = cleanName(row.owner_name);
    const left = row.need - row.theirs;
    const shown = row.restorable_day !== null ? Math.max(row.count, row.lost_count) : row.count;
    await tg(env, 'sendMessage', {
      chat_id: row.friend_id,
      text: `🔥 ${plural(shown, true)} с ${row.owner_name}: напиши сегодня ещё ${left}, чтобы огонёк не погас.`,
    });
  }
}

// Removal of stale data, hourly, on its own (a failed reminder run must not keep it from running).
async function cleanup(env) {
  const t = now();
  // Data nobody updated for a month goes away.
  const stale = t - STALE_DAYS * 86400;
  await env.DB.batch([
    env.DB.prepare('DELETE FROM pairs WHERE updated_at < ?').bind(stale),
    // Every sync touches the account's list, so a list untouched for a month belongs to nobody any more.
    env.DB.prepare('DELETE FROM streak_list WHERE updated_at < ?').bind(stale),
    env.DB.prepare('DELETE FROM restore_requests WHERE created_at < ?').bind(t - 3 * 86400),
    env.DB.prepare('DELETE FROM owners WHERE last_sync < ? AND created_at < ?').bind(stale, stale),
    env.DB.prepare('DELETE FROM badges WHERE updated_at < ?').bind(t - BADGE_DAYS * 86400),
    env.DB.prepare('DELETE FROM visual_gifts WHERE updated_at < ?').bind(t - VISUAL_GIFT_DAYS * 86400),
    env.DB.prepare('DELETE FROM support WHERE created_at < ?').bind(t - 30 * 86400),
    env.DB.prepare('DELETE FROM broadcast_queue WHERE created_at < ?').bind(t - 2 * 86400),
    env.DB.prepare('DELETE FROM broadcasts WHERE done = 1 AND created_at < ?').bind(t - 2 * 86400),
    // The daily gift limit looks back one day; the hourly check budget one hour.
    env.DB.prepare('DELETE FROM visual_gift_sends WHERE created_at < ?').bind(t - 86400),
    env.DB.prepare('DELETE FROM check_budget WHERE period < ?').bind(Math.floor(t / 3600) - 1),
    // Restored days are needed only while the app's count can reach them (it looks back a year).
    env.DB.prepare('DELETE FROM streak_restores WHERE day < ?').bind(Math.floor(t / 86400) - 400),
    env.DB.prepare('DELETE FROM notify_log WHERE created_at < ?').bind(t - 86400),
    env.DB.prepare('DELETE FROM feedback WHERE created_at < ?').bind(t - FEEDBACK_KEEP_DAYS * 86400),
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
    allowed_updates: ['message', 'callback_query', 'pre_checkout_query'],
  });
  await tg(env, 'setMyCommands', { commands: [
    { command: 'streaks', description: 'Мои огоньки' },
    { command: 'help', description: 'Как работает огонёк' },
    { command: 'stop', description: 'Выключить напоминания' },
    { command: 'paysupport', description: 'Помощь с оплатой' },
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
    if (request.method === 'POST' && url.pathname === '/api/gifts') return handleGifts(request, env);
    if (request.method === 'POST' && url.pathname === '/api/feedback') return handleFeedback(request, env);
    if (request.method === 'POST' && url.pathname === '/api/donate') return handleDonate(request, env);
    if (request.method === 'POST' && url.pathname === '/api/unlink') return handleUnlink(request, env);
    if (request.method === 'POST' && url.pathname === '/api/login') return handleLogin(request, env);
    if (request.method === 'POST' && url.pathname === '/api/admin') return handleAdminApi(request, env);
    if (request.method === 'GET' && url.pathname === '/admin') return new Response(ADMIN_PAGE, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY', 'content-security-policy': "default-src 'none'; script-src 'unsafe-inline' https://telegram.org; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; frame-ancestors 'none'" } });
    // The page the signed web-app data is requested for: the app reads the data from the address and never opens it.
    if (url.pathname === '/webapp') return new Response('<!doctype html><title>AstraGram</title>', { headers: { 'content-type': 'text/html; charset=utf-8' } });
    if (url.pathname === '/setup') return handleSetup(url, env);
    if (url.pathname === '/') return new Response('AstraGram streak bot', { headers: { 'content-type': 'text/plain; charset=utf-8' } });
    return new Response('not found', { status: 404 });
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil((async () => {
      // Every minute: move the broadcast queue along. Cleanup hourly at minute 5; reminders every ten minutes from
      // minute 5 (each run sends at most REMIND_BATCH, the evening hour's later runs send the rest).
      const minute = new Date(event.scheduledTime).getUTCMinutes();
      try {
        await drainBroadcast(env);
      } catch (error) {
        console.error('broadcast failed', error && error.message);
      }
      if (minute === 5) {
        try {
          await cleanup(env);
        } catch (error) {
          console.error('cleanup failed', error && error.message);
        }
      }
      if (minute % 10 === 5) {
        try {
          await remind(env);
        } catch (error) {
          console.error('reminders failed', error && error.message);
        }
      }
    })());
  },
};


// ---------------------------------------------------------------------------------------------------------------
// Admin panel: a mini app (GET /admin) that only the admin can use. The page itself holds no data; it sends Telegram's
// signed web-app data to /api/admin, which answers only when the signature names the admin's account.

// The worker's own address, taken from Telegram's webhook calls, for the panel's web-app button.
let workerOrigin = '';

function adminAppButton() {
  if (!workerOrigin) return { text: 'Адрес бота ещё не известен: пришлите любое сообщение и повторите /admin.' };
  return {
    text: '🛡 <b>Админ-панель</b>\n\nСтатистика AstraGram: выпуски, скачивания, пользователи. Открывается только у вас.',
    parse_mode: 'HTML',
    reply_markup: { inline_keyboard: [[{ text: '🛡 Открыть админ-панель', web_app: { url: `${workerOrigin}/admin` } }]] },
  };
}

async function rememberProfile(env, user) {
  if (!user || !Number.isSafeInteger(user.id) || user.id <= 0) return;
  await env.DB.prepare(`INSERT INTO profiles (tg_id, first_name, last_name, username, updated_at) VALUES (?, ?, ?, ?, ?)
    ON CONFLICT (tg_id) DO UPDATE SET first_name = excluded.first_name, last_name = excluded.last_name, username = excluded.username, updated_at = excluded.updated_at`)
    .bind(user.id, clip(user.first_name, 64), clip(user.last_name, 64), clip(user.username, 32), now()).run();
}

const GITHUB_REPO = 'dedsec-reth0/astragram';

// Releases and downloads from GitHub, kept for ten minutes (every call is a subrequest on the free plan).
async function releaseStats(env, t) {
  const cached = await kvGet(env, 'admin_releases');
  if (cached) {
    try {
      const value = JSON.parse(cached);
      if (t - value.at < 600) return value;
    } catch {}
  }
  const weekAgo = (t - 7 * 86400) * 1000;
  const value = { at: t, total: 0, week: 0, downloads: 0, downloadsWeek: 0, latest: null, list: [] };
  for (let page = 1; page <= 3; page++) {
    const res = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=100&page=${page}`, { headers: { 'user-agent': 'astragram-streak-bot', accept: 'application/vnd.github+json' } }).catch(() => null);
    if (!res || !res.ok) break;
    const releases = await res.json().catch(() => []);
    for (const release of releases) {
      if (release.draft || !/^v\d/.test(release.tag_name || '')) continue;
      const published = Date.parse(release.published_at || '') || 0;
      const downloads = (release.assets || []).filter((a) => /\.ipa$/.test(a.name)).reduce((sum, a) => sum + (a.download_count || 0), 0);
      value.total += 1;
      value.downloads += downloads;
      if (published >= weekAgo) {
        value.week += 1;
        value.downloadsWeek += downloads;
      }
      if (value.list.length < 10) value.list.push({ name: clip(release.name, 80), published: Math.floor(published / 1000), downloads });
      if (!value.latest) value.latest = clip(release.name, 80);
    }
    if (releases.length < 100) break;
  }
  await kvSet(env, 'admin_releases', JSON.stringify(value));
  return value;
}

async function handleAdminApi(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, error: 'body' }, 400);
  }
  const t = now();
  const user = await verifiedWebAppUser(env, body && body.initData, t);
  if (!user) return json({ ok: false, error: 'signature' }, 403);
  if (!isAdmin(user.id)) return json({ ok: false, error: 'forbidden' }, 403);

  const count = async (sql, ...args) => ((await env.DB.prepare(sql).bind(...args).first()) || {}).c || 0;
  const day = 86400;
  // AstraGram accounts the server knows: those linked to the streak bot and those with the badge on.
  const known = `(SELECT tg_id FROM owners UNION SELECT tg_id FROM badges)`;
  const users = {
    total: await count(`SELECT COUNT(*) AS c FROM ${known}`),
    linked: await count('SELECT COUNT(DISTINCT tg_id) AS c FROM owners'),
    active1: await count('SELECT COUNT(DISTINCT tg_id) AS c FROM owners WHERE last_sync >= ?', t - day),
    active7: await count('SELECT COUNT(DISTINCT tg_id) AS c FROM owners WHERE last_sync >= ?', t - 7 * day),
    new7: await count('SELECT COUNT(*) AS c FROM (SELECT tg_id FROM owners GROUP BY tg_id HAVING MIN(created_at) >= ?)', t - 7 * day),
    badges: await count('SELECT COUNT(*) AS c FROM badges'),
    botSubscribers: await count('SELECT COUNT(*) AS c FROM friends WHERE stopped = 0'),
  };
  const activity = {
    streaks: await count('SELECT COUNT(*) AS c FROM pairs'),
    gifts: await count('SELECT COUNT(*) AS c FROM visual_gift_received'),
    gifts7: await count('SELECT COUNT(*) AS c FROM visual_gift_received WHERE created_at >= ?', t - 7 * day),
    feedback: await count('SELECT COUNT(*) AS c FROM feedback'),
  };
  const rows = (await env.DB.prepare(`SELECT k.tg_id AS id, p.first_name, p.last_name, p.username,
      (SELECT MAX(last_sync) FROM owners o WHERE o.tg_id = k.tg_id) AS last_seen,
      (SELECT MIN(created_at) FROM owners o WHERE o.tg_id = k.tg_id) AS joined,
      (SELECT name FROM owners o WHERE o.tg_id = k.tg_id ORDER BY created_at DESC LIMIT 1) AS owner_name,
      EXISTS (SELECT 1 FROM badges b WHERE b.tg_id = k.tg_id) AS badge
    FROM ${known} k LEFT JOIN profiles p ON p.tg_id = k.tg_id ORDER BY last_seen DESC LIMIT 1000`).all()).results || [];

  // Fill in a few unknown names from Telegram (the bot sees users who wrote to it); the rest come later.
  let lookups = 0;
  for (const row of rows) {
    if (lookups >= 15 || row.first_name || row.username) continue;
    lookups += 1;
    const chat = await tg(env, 'getChat', { chat_id: row.id }).catch(() => null);
    if (chat && chat.ok && chat.result) {
      row.first_name = clip(chat.result.first_name, 64);
      row.last_name = clip(chat.result.last_name, 64);
      row.username = clip(chat.result.username, 32);
      await rememberProfile(env, { id: row.id, first_name: row.first_name, last_name: row.last_name, username: row.username });
    }
  }

  return json({
    ok: true,
    at: t,
    releases: await releaseStats(env, t),
    users,
    activity,
    list: rows.map((r) => ({
      id: r.id,
      name: [r.first_name || r.owner_name || '', r.last_name || ''].join(' ').trim(),
      username: r.username || '',
      lastSeen: r.last_seen || 0,
      joined: r.joined || 0,
      badge: !!r.badge,
    })),
  });
}

const ADMIN_PAGE = String.raw`<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="dark">
<meta name="robots" content="noindex">
<title>AstraGram · Админ</title>
<script src="https://telegram.org/js/telegram-web-app.js"></script>
<style>
:root{--bg:#000;--text:#f5f5f7;--muted:rgba(245,245,247,.62);--faint:rgba(245,245,247,.36);--glass:rgba(255,255,255,.06);--glass-2:rgba(255,255,255,.1);--edge:rgba(255,255,255,.12);--edge-top:rgba(255,255,255,.28);--violet:#8b5cf6;--blue:#38bdf8;--green:#34d399;--red:#f87171;
--display:"SF Pro Display",-apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif;--body:"SF Pro Text",-apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif;--mono:ui-monospace,SFMono-Regular,Menlo,monospace;--ease:cubic-bezier(.16,1,.3,1)}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}
body{min-height:100vh;padding:calc(env(safe-area-inset-top) + 18px) 16px calc(env(safe-area-inset-bottom) + 28px);overflow-x:hidden}
.bgfx{position:fixed;inset:0;z-index:0;pointer-events:none;background:radial-gradient(40vmax 40vmax at 75% 10%,rgba(139,92,246,.28),transparent 70%),radial-gradient(35vmax 35vmax at 10% 60%,rgba(56,189,248,.16),transparent 70%)}
.vignette{position:fixed;inset:0;z-index:1;pointer-events:none;background:radial-gradient(ellipse at 50% 40%,transparent 45%,rgba(0,0,0,.7) 100%)}
main{position:relative;z-index:2;max-width:760px;margin:0 auto}
.glass{position:relative;background:var(--glass);-webkit-backdrop-filter:blur(24px) saturate(160%);backdrop-filter:blur(24px) saturate(160%);box-shadow:inset 0 1px 0 var(--edge-top),inset 0 0 0 1px var(--edge);border-radius:24px}
.glass::before{content:"";position:absolute;inset:0;border-radius:inherit;pointer-events:none;background:linear-gradient(160deg,rgba(255,255,255,.12),rgba(255,255,255,.015) 40%,transparent 62%)}
.eyebrow{font:600 12px/1 var(--body);letter-spacing:.16em;text-transform:uppercase;color:var(--faint)}
h1{margin:10px 0 4px;font:800 40px/1 var(--display);letter-spacing:-.045em}
.grad{background:linear-gradient(100deg,#fff 0%,#d9d2ff 40%,#a5e4ff 75%,#fff 100%);-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{color:var(--muted);font-size:14px;margin-bottom:22px}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-bottom:10px}
@media(min-width:620px){.grid{grid-template-columns:repeat(4,minmax(0,1fr))}}
.stat{padding:16px 16px 14px;opacity:0;transform:translateY(10px);animation:in .7s var(--ease) forwards}
.stat b{display:block;font:750 30px/1 var(--display);letter-spacing:-.03em;font-variant-numeric:tabular-nums}
.stat span{display:block;margin-top:8px;font-size:12.5px;color:var(--muted)}
@keyframes in{to{opacity:1;transform:none}}
h2{font:700 20px var(--display);letter-spacing:-.02em;margin:26px 4px 10px;display:flex;justify-content:space-between;align-items:baseline}
h2 small{font:500 13px var(--body);color:var(--faint)}
.card{padding:6px 0}
.row{display:flex;align-items:center;gap:12px;padding:11px 16px;border-top:1px solid rgba(255,255,255,.06)}
.row:first-child{border-top:0}
.av{flex:none;width:38px;height:38px;border-radius:50%;display:grid;place-items:center;font:700 15px var(--display);color:#fff;background:linear-gradient(135deg,var(--violet),var(--blue))}
.who{flex:1;min-width:0}
.who .n{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.who .m{font-size:12.5px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-family:var(--mono)}
.when{flex:none;text-align:right;font-size:12px;color:var(--faint)}
.dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:5px;background:var(--faint)}
.dot.on{background:var(--green);box-shadow:0 0 8px var(--green)}
input{width:100%;height:44px;border-radius:14px;border:0;padding:0 14px;margin:0 0 10px;background:var(--glass-2);color:var(--text);font:500 15px var(--body);outline:none;box-shadow:inset 0 0 0 1px var(--edge)}
.rel .row{justify-content:space-between}
.rel .v{font-weight:600}.rel .d{font-size:12.5px;color:var(--muted)}
.state{margin-top:40vh;text-align:center;color:var(--muted)}
.state b{display:block;font:800 26px var(--display);color:var(--text);margin-bottom:8px}
.badge{font:600 10px var(--body);letter-spacing:.06em;text-transform:uppercase;color:#d9d2ff;background:rgba(139,92,246,.25);padding:2px 6px;border-radius:6px;margin-left:6px}
</style>
</head>
<body>
<div class="bgfx"></div><div class="vignette"></div>
<main id="app"><div class="state"><b>Загрузка…</b>Проверяем доступ</div></main>
<script>
const tgApp = window.Telegram && Telegram.WebApp;
if (tgApp) { tgApp.ready(); tgApp.expand(); try { tgApp.setHeaderColor('#000000'); tgApp.setBackgroundColor('#000000'); } catch (e) {} }
const app = document.getElementById('app');
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num = (n) => Number(n || 0).toLocaleString('ru-RU');
function ago(t, now) {
  if (!t) return 'не был(а)';
  const d = now - t;
  if (d < 120) return 'сейчас';
  if (d < 3600) return Math.floor(d / 60) + ' мин назад';
  if (d < 86400) return Math.floor(d / 3600) + ' ч назад';
  if (d < 30 * 86400) return Math.floor(d / 86400) + ' дн назад';
  return new Date(t * 1000).toLocaleDateString('ru-RU');
}
function stat(value, label, i) { return '<div class="stat glass" style="animation-delay:' + (i * 50) + 'ms"><b>' + value + '</b><span>' + label + '</span></div>'; }
function deny(title, text) { app.innerHTML = '<div class="state"><b>' + title + '</b>' + text + '</div>'; }
async function load() {
  const initData = tgApp ? tgApp.initData : '';
  if (!initData) return deny('Только в Telegram', 'Откройте панель кнопкой в боте.');
  let data;
  try {
    const res = await fetch('/api/admin', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ initData }) });
    data = await res.json();
  } catch (e) { return deny('Нет связи', 'Попробуйте ещё раз.'); }
  if (!data || !data.ok) return deny('Доступ запрещён', 'Эта страница только для администратора AstraGram.');
  const r = data.releases, u = data.users, a = data.activity, now = data.at;
  let html = '<div class="eyebrow">AstraGram · Админ-панель</div><h1 class="grad">Статистика</h1><div class="sub">Последняя версия: ' + esc(r.latest || '—') + '</div>';
  html += '<div class="grid">' + [
    [num(r.week), 'выпусков за неделю'], [num(r.total), 'выпусков всего'],
    [num(r.downloadsWeek), 'скачиваний за неделю'], [num(r.downloads), 'скачиваний всего'],
    [num(u.total), 'пользователей AstraGram'], [num(u.active1), 'активны за сутки'],
    [num(u.active7), 'активны за неделю'], [num(u.new7), 'новых за неделю'],
    [num(u.linked), 'подключили бота'], [num(u.badges), 'со значком'],
    [num(a.streaks), 'огоньков'], [num(a.gifts7) + ' / ' + num(a.gifts), 'подарков нед / всего'],
  ].map((s, i) => stat(s[0], s[1], i)).join('') + '</div>';
  html += '<h2>Выпуски <small>последние ' + r.list.length + '</small></h2><div class="card glass rel">' + r.list.map((x) => '<div class="row"><div><div class="v">' + esc(x.name) + '</div><div class="d">' + new Date(x.published * 1000).toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) + '</div></div><div class="d">⬇ ' + num(x.downloads) + '</div></div>').join('') + '</div>';
  html += '<h2>Пользователи <small>' + num(data.list.length) + '</small></h2><input id="q" placeholder="Поиск: имя, @юзернейм или ID" autocomplete="off"><div class="card glass" id="users"></div>';
  app.innerHTML = html;
  const box = document.getElementById('users');
  const render = (q) => {
    q = (q || '').trim().toLowerCase().replace(/^@/, '');
    const list = data.list.filter((x) => !q || (x.name || '').toLowerCase().includes(q) || (x.username || '').toLowerCase().includes(q) || String(x.id).includes(q));
    box.innerHTML = list.map((x) => {
      const online = x.lastSeen && now - x.lastSeen < 86400;
      return '<div class="row"><div class="av">' + esc((x.name || '?').trim().charAt(0).toUpperCase() || '?') + '</div><div class="who"><div class="n">' + esc(x.name || 'Без имени') + (x.badge ? '<span class="badge" title="значок AstraGram">★</span>' : '') + '</div><div class="m">' + (x.username ? '@' + esc(x.username) + ' · ' : '') + 'ID ' + x.id + '</div></div><div class="when"><span class="dot' + (online ? ' on' : '') + '"></span>' + ago(x.lastSeen, now) + '</div></div>';
    }).join('') || '<div class="row"><div class="who"><div class="m">Никого не найдено</div></div></div>';
  };
  render('');
  document.getElementById('q').addEventListener('input', (e) => render(e.target.value));
}
load();
</script>
</body>
</html>`;
