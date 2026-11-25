// Polyfills for the parts of the Workers runtime the bot uses, then the scenarios.
function call(req) {
  print('@@' + JSON.stringify(req));
  return JSON.parse(readline());
}
globalThis.TextEncoder = class {
  encode(s) {
    const bytes = [];
    for (const ch of unescape(encodeURIComponent(s))) bytes.push(ch.charCodeAt(0));
    return new Uint8Array(bytes);
  }
};
globalThis.crypto = { subtle: { digest: async (_alg, data) => {
  const hex = call({ op: 'sha256', bytes: Array.from(data) });
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out.buffer;
},
  importKey: async (_f, keyBytes) => Array.from(keyBytes),
  sign: async (_alg, key, data) => new Uint8Array(call({ op: 'hmac', key, bytes: Array.from(data) })).buffer,
} };
globalThis.URLSearchParams = class {
  constructor(s) {
    this.list = s.split('&').filter(Boolean).map((p) => {
      const i = p.indexOf('=');
      const dec = (x) => decodeURIComponent(x.replace(/\+/g, ' '));
      return i < 0 ? [dec(p), ''] : [dec(p.slice(0, i)), dec(p.slice(i + 1))];
    });
  }
  get(k) { const e = this.list.find((x) => x[0] === k); return e ? e[1] : null; }
  [Symbol.iterator]() { return this.list[Symbol.iterator](); }
};
globalThis.URL = class {
  constructor(u) {
    const m = u.match(/^(https?:\/\/[^/]+)(\/[^?]*)?/);
    this.origin = m[1];
    this.pathname = m[2] || '/';
  }
};
globalThis.Response = class {
  constructor(body, init = {}) {
    this.body = body;
    this.status = init.status || 200;
  }
};
const sent = [];
let nextMessageId = 1000;
// A chat whose copyMessage answers 429 (Telegram's rate limit), for the broadcast drain.
let rateLimitedChat = null;
globalThis.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  sent.push({ method: url.split('/').pop(), ...body });
  if (url.endsWith('/createInvoiceLink')) return { json: async () => ({ ok: true, result: 'https://t.me/$invoice' }) };
  if (url.endsWith('/createForumTopic')) return { json: async () => ({ ok: true, result: { message_thread_id: 500 + sent.length } }) };
  if (url.endsWith('/copyMessage') && body.chat_id === rateLimitedChat) return { json: async () => ({ ok: false, error_code: 429 }) };
  if (url.endsWith('/copyMessage')) return { json: async () => ({ ok: true, result: { message_id: nextMessageId++ } }) };
  if (url.endsWith('/sendMessage')) return { json: async () => ({ ok: true, result: { message_id: nextMessageId++ } }) };
  return { json: async () => ({ ok: true, result: {} }) };
};
function statement(sql, args) {
  return {
    sql, args,
    bind: (...a) => statement(sql, a),
    first: async () => call({ op: 'first', sql, args }),
    all: async () => call({ op: 'all', sql, args }),
    run: async () => call({ op: 'run', sql, args }),
  };
}
const env = { BOT_TOKEN: 'x', DB: {
  prepare: (sql) => statement(sql, []),
  batch: async (list) => call({ op: 'batch', statements: list.map((s) => ({ sql: s.sql, args: s.args })) }),
} };

import worker from './worker.mjs';

const TOKENS = { A: 'a'.repeat(48), B: 'b'.repeat(48), C: 'c'.repeat(48) };
async function sync(device, body) {
  call({ op: 'reset' });
  const request = {
    url: 'https://bot.example/api/sync', method: 'POST',
    headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS[device] : null) },
    json: async () => body,
  };
  const response = await worker.fetch(request, env);
  return { status: response.status, body: JSON.parse(response.body) };
}
const pair = (friend, startDay) => ({ friend, count: 1, mine: 3, theirs: 3, todayDone: true, restoresLeft: 5, lostCount: 0, day: 20420, ...(startDay === undefined ? {} : { startDay }) });
const q = (sql, args = []) => call({ op: 'query', sql, args });
let failures = 0;
function check(name, actual, expected) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) print('ok   ' + name);
  else { failures++; print('FAIL ' + name + '\n     got      ' + a + '\n     expected ' + e); }
}
const friends = (rows) => rows.map((r) => r.friend_id).sort((x, y) => x - y);
const streaks = (r) => (r.body.streaks || []).map((s) => s.friend + ':' + s.startDay).sort();

(async () => {
  // 1. An old (version 1) phone: its numbers go in, no shared list.
  let r = await sync('A', { pairs: [pair(1)] });
  check('v1 sync accepted', r.status, 200);
  check('v1 reply has no list', r.body.streaks, undefined);
  check('v1 pair stored', friends(q('SELECT friend_id FROM pairs')), [1]);

  // 2. The phone updates: its streaks become the account's list.
  r = await sync('A', { v: 2, pairs: [pair(1, 20400), pair(2, 20405)] });
  check('phone v2 list', streaks(r), ['1:20400', '2:20405']);

  // 3. The simulator starts a streak with 3: it gets the phone's streaks too; the phone's numbers stay.
  r = await sync('B', { v: 2, starts: [{ friend: 3, startDay: 20410 }], pairs: [pair(3, 20410)] });
  check('second device gets every streak', streaks(r), ['1:20400', '2:20405', '3:20410']);
  check('second device keeps the phone numbers', friends(q('SELECT friend_id FROM pairs')), [1, 2, 3]);

  // 4. The phone turns 2 off.
  r = await sync('A', { v: 2, stops: [2], pairs: [pair(1, 20400), pair(3, 20410)] });
  check('stop reported', r.body.stopped, [2]);
  check('stopped streak left the list', streaks(r), ['1:20400', '3:20410']);
  check('stopped numbers removed', friends(q('SELECT friend_id FROM pairs')), [1, 3]);

  // 5. The simulator has not heard: its stale copy of 2 does not bring it back.
  r = await sync('B', { v: 2, pairs: [pair(1, 20400), pair(2, 20405), pair(3, 20410)] });
  check('stale copy stays off', streaks(r), ['1:20400', '3:20410']);
  check('stale copy told to stop', r.body.stopped, [2]);
  check('stale numbers not stored', friends(q('SELECT friend_id FROM pairs')), [1, 3]);

  // 6. Starting 2 again (on any device) brings it back with its new start day.
  r = await sync('B', { v: 2, starts: [{ friend: 2, startDay: 20420 }], pairs: [pair(2, 20420)] });
  check('restart', streaks(r), ['1:20400', '2:20420', '3:20410']);
  check('restart clears the stop', r.body.stopped, []);

  // 7. A pair keeps the list's start day: the first device to report it decides.
  r = await sync('A', { v: 2, pairs: [pair(1, 20399)] });
  check('start day not overwritten by a pair', streaks(r).filter((s) => s.startsWith('1:')), ['1:20400']);

  // 7b. A device with less history counts a shorter streak the same day: the longer one stays; a new day takes the new.
  await sync('A', { v: 2, pairs: [{ ...pair(1, 20400), count: 12, mine: 1, theirs: 0, todayDone: false, day: 20421 }] });
  await sync('B', { v: 2, pairs: [{ ...pair(1, 20400), count: 2, mine: 0, theirs: 3, todayDone: false, day: 20421 }] });
  let row = q('SELECT count, mine, theirs, today_done FROM pairs WHERE owner_id = 100 AND friend_id = 1')[0];
  check('same day keeps longer streak and most messages', [row.count, row.mine, row.theirs, row.today_done], [12, 1, 3, 0]);
  await sync('B', { v: 2, pairs: [{ ...pair(1, 20400), count: 0, mine: 0, theirs: 0, todayDone: false, day: 20422 }] });
  row = q('SELECT count, mine, theirs, day FROM pairs WHERE owner_id = 100 AND friend_id = 1')[0];
  check('new day takes new numbers', [row.count, row.mine, row.theirs, row.day], [0, 0, 0, 20422]);

  // 8. Another account sees nothing of this one; own ID and junk are ignored.
  r = await sync('C', { v: 2, starts: [{ friend: 200, startDay: 1 }, { friend: 'x', startDay: 1 }], stops: [-5], pairs: [] });
  check('other account isolated', streaks(r), []);

  // 9. An old app syncing again only trims the numbers, never the list.
  q('UPDATE pairs SET updated_at = updated_at - 10');
  r = await sync('A', { pairs: [pair(1)] });
  check('v1 trims numbers', friends(q('SELECT friend_id FROM pairs WHERE owner_id = 100')), [1]);
  check('v1 leaves list', friends(q('SELECT friend_id FROM streak_list WHERE owner_id = 100 AND stopped = 0')), [1, 2, 3]);

  // 9b. Visual gifts: an account stores its list; another app gets it only for IDs it asks about.
  const gifts = async (device, body) => {
    const request = {
      url: 'https://bot.example/api/gifts', method: 'POST',
      headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS[device] : null) },
      json: async () => body,
    };
    const response = await worker.fetch(request, env);
    return { status: response.status, body: JSON.parse(response.body) };
  };
  r = await gifts('A', { gifts: ['5170145012310081615', '5170145012310081615', 'x', 6028601630662853006], check: [] });
  check('gifts stored, deduplicated, junk and rounded numbers dropped', r.body.mine, ['5170145012310081615']);
  r = await gifts('A', { gifts: ['5170145012310081615', '6028601630662853006'], check: [] });
  check('64-bit ids kept exactly as strings', r.body.mine, ['5170145012310081615', '6028601630662853006']);
  r = await gifts('C', { check: [100, 999] });
  check('other app sees the list of a checked id', r.body.users, { 100: ['5170145012310081615', '6028601630662853006'] });
  r = await gifts('C', { check: [999] });
  check('unchecked ids are not handed out', r.body.users, {});
  r = await gifts('C', { gifts: [] , check: [100] });
  check('empty list clears own gifts', r.body.mine, []);

  // 9c. Free gifts: A (100) gives C (200) a gift; C and anyone asking about 200 see it with the sender; C can take it off.
  r = await gifts('A', { send: { to: 200, gift: '5170145012310081615' }, check: [] });
  check('gift sent', typeof r.body.sent, 'number');
  const sentId = r.body.sent;
  r = await gifts('A', { send: { to: 100, gift: '5170145012310081615' } });
  check('no gift to oneself', r.status, 400);
  r = await gifts('A', { send: { to: 200, gift: 'x' } });
  check('no junk gift id', r.status, 400);
  r = await gifts('C', { check: [] });
  check('recipient sees own received gift', r.body.mineReceived.map((g) => [g.gift, g.from]), [['5170145012310081615', 100]]);
  r = await gifts('B', { check: [200] });
  check('others see received gifts of a checked id', r.body.received[200].map((g) => g.from), [100]);
  r = await gifts('A', { hide: [sentId], check: [200] });
  check('sender cannot take it off', r.body.received[200].length, 1);
  r = await gifts('C', { hide: [sentId], check: [] });
  check('recipient takes it off', r.body.mineReceived, []);
  // One sender keeps at most 10 gifts on one profile; the day's other 10 go to someone else.
  for (let i = 0; i < 10; i++) await gifts('A', { send: { to: 200, gift: '1' } });
  r = await gifts('A', { send: { to: 200, gift: '1' } });
  check('at most 10 from one sender on one profile', [r.status, r.body.error], [429, 'too many gifts there']);
  for (let i = 0; i < 9; i++) await gifts('A', { send: { to: 201, gift: '1' } });
  r = await gifts('A', { send: { to: 202, gift: '1' } });
  check('daily limit', [r.status, r.body.error], [429, 'too many gifts today']);
  // The recipient taking gifts off does not give the sender new ones.
  const given = q('SELECT id FROM visual_gift_received WHERE from_id = 100').map((x) => x.id);
  await gifts('C', { hide: given, check: [] });
  r = await gifts('A', { send: { to: 200, gift: '1' } });
  check('hiding does not reset the daily limit', r.status, 429);
  // Passing a gift on counts too, an own gift put on from the shop just before included.
  r = await gifts('A', { gifts: ['55'], transfer: { ref: 'o55', to: 200 }, check: [] });
  check('a transfer counts against the daily limit', r.status, 429);
  // A new day.
  q('DELETE FROM visual_gift_sends');

  // 9d. Feedback and donations (no streak-bot link needed).
  const post = async (path, body, headers = {}) => {
    const response = await worker.fetch({
      url: 'https://bot.example' + path, method: 'POST',
      headers: { get: (k) => headers[k] || null },
      json: async () => body,
    }, env);
    return { status: response.status, body: JSON.parse(response.body) };
  };
  sent.length = 0;
  r = await post('/api/feedback', { kind: 'bug', text: 'Crash when opening the gift shop', version: '1.0.27', os: 'iOS 26.3' }, { 'cf-connecting-ip': '1.2.3.4' });
  check('anonymous feedback accepted', r.body.ok, true);
  check('admin gets the report', sent.some((m) => m.method === 'sendMessage' && /Ошибка/.test(m.text) && /аноним/.test(m.text)), true);
  r = await post('/api/feedback', { kind: 'idea', text: 'Dark theme for the shop', userId: 200, name: 'C' }, { 'cf-connecting-ip': '1.2.3.4', authorization: 'Bearer ' + TOKENS.C });
  check('verified sender named', sent.some((m) => /Идея/.test(m.text) && /id 200\)/.test(m.text)), true);
  check('reply mapping kept', q('SELECT user_id FROM support ORDER BY admin_msg_id DESC LIMIT 1')[0].user_id, 200);
  r = await post('/api/feedback', { kind: 'bug', text: 'x' }, { 'cf-connecting-ip': '1.2.3.4' });
  check('too short refused', r.status, 400);
  for (let i = 0; i < 3; i++) await post('/api/feedback', { kind: 'bug', text: 'again ' + i }, { 'cf-connecting-ip': '1.2.3.4' });
  r = await post('/api/feedback', { kind: 'bug', text: 'one too many' }, { 'cf-connecting-ip': '1.2.3.4' });
  check('rate limited per address', r.status, 429);
  r = await post('/api/donate', { stars: 100 });
  check('donation link', r.body.link, 'https://t.me/$invoice');
  check('invoice in stars', sent.filter((m) => m.method === 'createInvoiceLink').map((m) => [m.currency, m.prices[0].amount, m.payload]), [['XTR', 100, 'donate:100']]);
  r = await post('/api/donate', { stars: 0 });
  check('bad amount refused', r.status, 400);

  // 9e. A day restored on one device (a request from the bot) reaches the account's other devices.
  q('DELETE FROM streak_list WHERE owner_id = 100 AND friend_id = 1');
  q('INSERT INTO streak_list (owner_id, friend_id, start_day, stopped, updated_at) VALUES (100, 1, 20400, 0, 1)');
  await sync('A', { v: 2, pairs: [{ ...pair(1, 20400), restored: [20419, 20420, 99999, 1, 'x'] }] });
  r = await sync('B', { v: 2, pairs: [pair(1, 20400)] });
  check('restored days shared', (r.body.restored || []).filter((x) => x.friend === 1).map((x) => x.day).sort(), [20419]);

  // 9f. Linking with Telegram's signed web-app data: no message to the bot.
  const D = 'd'.repeat(48);
  const login = (initData, token = D) => post('/api/login', { initData }, { authorization: 'Bearer ' + token });
  r = await login(call({ op: 'webappdata', id: 300 }));
  check('signed login links', [r.status, r.body.id], [200, 300]);
  check('owner row for the new token', q('SELECT tg_id FROM owners WHERE token_hash = ?', [call({ op: 'sha256', bytes: Array.from(new TextEncoder().encode(D)) })])[0].tg_id, 300);
  r = await login(call({ op: 'webappdata', id: 300, forge: 100 }), 'e'.repeat(48));
  check('changed user refused', r.status, 403);
  r = await login(call({ op: 'webappdata', id: 300, age: 3600 }), 'e'.repeat(48));
  check('old data refused', r.status, 403);
  r = await login('hash=00&user=1', 'e'.repeat(48));
  check('junk refused', r.status, 403);

  // 9g. The admin's group with topics becomes the inbox: reports go to their topics, a reply there reaches the author.
  const WEBHOOK = call({ op: 'sha256', bytes: Array.from(new TextEncoder().encode('x:webhook')) }).slice(0, 48);
  const update = async (message) => worker.fetch({ url: 'https://bot.example/tg', method: 'POST',
    headers: { get: (k) => (k === 'x-telegram-bot-api-secret-token' ? WEBHOOK : null) }, json: async () => ({ update_id: 1, message }) }, env);
  const GROUP = -1001234;
  const admin = { id: 800000000 + 80000000 + 7000000 + 825713, first_name: 'Admin', language_code: 'ru' };
  sent.length = 0;
  await update({ message_id: 1, from: { id: 5, first_name: 'X' }, chat: { id: GROUP, type: 'supergroup', is_forum: true }, text: '/inbox' });
  check('only the admin sets the inbox', sent.filter((m) => m.method === 'createForumTopic').length, 0);
  await update({ message_id: 2, from: admin, chat: { id: GROUP, type: 'supergroup', is_forum: false }, text: '/inbox' });
  check('topics needed', sent.some((m) => m.chat_id === GROUP && /Темы/.test(m.text || '')), true);
  sent.length = 0;
  await update({ message_id: 3, from: admin, chat: { id: GROUP, type: 'supergroup', is_forum: true }, text: '/inbox@infoastragram_bot' });
  check('four topics made', sent.filter((m) => m.method === 'createForumTopic').map((m) => m.name), ['🐞 Ошибки', '💡 Идеи', '💛 Донаты', '💬 Поддержка']);
  const box = JSON.parse(q("SELECT value FROM kv WHERE key = 'inbox'")[0].value);
  check('inbox stored', box.chat, GROUP);
  sent.length = 0;
  await update({ message_id: 4, from: admin, chat: { id: GROUP, type: 'supergroup', is_forum: true }, text: '/inbox' });
  check('again: no new topics', sent.filter((m) => m.method === 'createForumTopic').length, 0);
  sent.length = 0;
  r = await post('/api/feedback', { kind: 'idea', text: 'Topics are nice', userId: 200 }, { 'cf-connecting-ip': '9.9.9.9', authorization: 'Bearer ' + TOKENS.C });
  const notice = sent.find((m) => m.method === 'sendMessage');
  check('idea goes to its topic', [notice.chat_id, notice.message_thread_id], [GROUP, box.idea]);
  const noticeId = nextMessageId - 1;
  sent.length = 0;
  await update({ message_id: 77, message_thread_id: box.idea, from: admin, chat: { id: GROUP, type: 'supergroup', is_forum: true }, text: 'Thanks!', reply_to_message: { message_id: noticeId } });
  check('reply in the group reaches the author', sent.filter((m) => m.method === 'copyMessage').map((m) => [m.chat_id, m.from_chat_id, m.message_id]), [[200, GROUP, 77]]);
  sent.length = 0;
  await update({ message_id: 78, from: admin, chat: { id: GROUP, type: 'supergroup', is_forum: true }, text: 'chatter' });
  check('other group messages ignored', sent.length, 0);
  sent.length = 0;
  await update({ message_id: 9, from: { id: 200, first_name: 'C', language_code: 'ru' }, chat: { id: 200, type: 'private' }, successful_payment: { currency: 'XTR', total_amount: 50, invoice_payload: 'donate:50' } });
  const donation = sent.find((m) => /Донат/.test(m.text || ''));
  check('donation goes to its topic', [donation.chat_id, donation.message_thread_id], [GROUP, box.donate]);
  q("DELETE FROM kv WHERE key = 'inbox'");

  // 9h. Gifts like Telegram's: a caption and an anonymous giver, pinning, hiding, upgrades with numbers, passing on, wearing.
  r = await gifts('C', { send: { to: 100, gift: '777', text: 'С днём рождения!', anonymous: true }, check: [] });
  const anonId = r.body.sent;
  r = await gifts('A', { check: [] });
  const mineAnon = r.body.mineReceived.find((g) => g.id === anonId);
  check('recipient sees the caption and the giver', [mineAnon.text, mineAnon.from, mineAnon.anon], ['С днём рождения!', 200, true]);
  r = await gifts('C', { check: [100] });
  const seenAnon = r.body.received[100].find((g) => g.id === anonId);
  check('others see the caption, not the anonymous giver', [seenAnon.text, seenAnon.from], ['С днём рождения!', 0]);
  r = await gifts('A', { gifts: ['5170145012310081615', '6028601630662853006'], meta: [{ ref: 'o5170145012310081615', pinned: true }, { ref: 'o6028601630662853006', hidden: true }, { ref: 'o42', pinned: true }], check: [] });
  check('owner sees pin and hidden', [r.body.mineMeta['5170145012310081615'].pin > 0, r.body.mineMeta['6028601630662853006'].hidden], [true, true]);
  check('a gift not on the profile is not pinned', q("SELECT COUNT(*) AS c FROM visual_gift_meta WHERE ref = 'o42'")[0].c, 0);
  r = await gifts('C', { check: [100] });
  check('a hidden gift is not handed out', r.body.users[100], ['5170145012310081615']);
  check('others see the pin', r.body.usersMeta[100]['5170145012310081615'].pin > 0, true);
  r = await gifts('A', { upgrade: { ref: `r${anonId}`, model: 'Blue Star', pattern: 'Moon', backdrop: 'Midnight' }, check: [] });
  check('upgrade numbered from 1', r.body.upgraded.u, { n: 1, m: 'Blue Star', p: 'Moon', b: 'Midnight' });
  r = await gifts('A', { upgrade: { ref: `r${anonId}`, model: 'Other', pattern: 'x', backdrop: 'y' }, check: [] });
  check('a gift is upgraded once', r.body.upgraded.u.m, 'Blue Star');
  r = await gifts('C', { send: { to: 100, gift: '777' }, check: [] });
  r = await gifts('A', { upgrade: { ref: `r${r.body.sent}`, model: 'M', pattern: 'P', backdrop: 'B' }, check: [] });
  check('the next one of the same gift is #2', r.body.upgraded.u.n, 2);
  r = await gifts('C', { upgrade: { ref: `r${anonId}`, model: 'M', pattern: 'P', backdrop: 'B' }, check: [] });
  check('nobody upgrades a gift that is not theirs', r.status, 400);
  r = await gifts('A', { wear: { ref: `r${anonId}` }, check: [] });
  check('worn by its owner', r.body.worn[100].u.n, 1);
  r = await gifts('C', { check: [100] });
  check('others see what is worn', [r.body.worn[100].gift, r.body.worn[100].u.m], ['777', 'Blue Star']);
  r = await gifts('B', { transfer: { ref: `r${anonId}`, to: 200 }, check: [] });
  check('passed on', typeof r.body.transferred, 'number');
  check('taken off when passed on', r.body.worn[100], undefined);
  r = await gifts('C', { check: [] });
  const movedId = q('SELECT MAX(id) AS id FROM visual_gift_received WHERE to_id = 200')[0].id;
  const moved = r.body.mineReceived.find((g) => g.id === movedId);
  check('the new owner gets it with its upgrade, from the one who passed it', [moved.from, moved.u.n, moved.text, moved.anon], [100, 1, undefined, undefined]);
  r = await gifts('C', { gifts: ['9'], check: [] });
  r = await gifts('C', { transfer: { ref: 'o9', to: 100 }, check: [] });
  check('an own gift passed on leaves the list', r.body.mine, []);
  r = await gifts('A', { check: [] });
  check('and reaches the other profile', r.body.mineReceived.some((g) => g.id === r.body.mineReceived[0].id && g.gift === '9' && g.from === 200), true);
  r = await gifts('A', { wear: null, meta: [{ ref: 'o5170145012310081615', pinned: false }], check: [] });
  check('unpinned', r.body.mineMeta['5170145012310081615'], undefined);

  // 9h2. Only the admin may set the number (or change an upgraded gift); anyone else gets the next number.
  r = await gifts('A', { upgrade: { ref: 'o5170145012310081615', model: 'Gold', pattern: 'Star', backdrop: 'Black', number: 7 }, check: [] });
  check('a non-admin cannot choose the number', [r.body.upgraded.u.m, r.body.upgraded.u.n === 7], ['Gold', false]);
  r = await gifts('A', { upgrade: { ref: 'o5170145012310081615', model: 'Silver', pattern: 'Star', backdrop: 'Black' }, check: [] });
  check('a non-admin cannot change an upgraded gift', r.body.upgraded.u.m, 'Gold');

  // 9i. Local Premium looks: set, seen by others, junk dropped, turned off.
  r = await gifts('A', { premiumLook: { status: '5170145012310081615', nameColor: 3, profileColor: 7, bad: 'x', backgroundEmoji: 12.5 }, check: [] });
  check('own look comes back', r.body.premiumLooks[100], { status: '5170145012310081615', nameColor: 3, profileColor: 7 });
  r = await gifts('C', { check: [100] });
  check('others see the look', r.body.premiumLooks[100].profileColor, 7);
  r = await gifts('A', { premiumLook: null, check: [] });
  check('turned off', r.body.premiumLooks[100], undefined);

  // 9j. Gifts asked about with another linked account's token come back for that account too.
  r = await gifts('A', { check: [100] });
  check('the token owner is not dropped from check', Array.isArray(r.body.users[100]), true);

  // 9k. A received gift passed on gets a new row, and the old one goes.
  const oldRow = q("INSERT INTO visual_gift_received (to_id, from_id, gift_id, created_at) VALUES (100, 5, '31', 1) RETURNING id")[0].id;
  r = await gifts('A', { transfer: { ref: `r${oldRow}`, to: 200 }, check: [] });
  check('a passed-on gift reaches the new owner', q('SELECT gift_id FROM visual_gift_received WHERE id = ? AND to_id = 200', [r.body.transferred]).map((x) => x.gift_id), ['31']);
  check('the old row is gone', q('SELECT COUNT(*) AS c FROM visual_gift_received WHERE id = ?', [oldRow])[0].c, 0);
  q('DELETE FROM visual_gift_received WHERE to_id = 200');
  q('DELETE FROM visual_gift_sends');
  // 9k2. A full profile takes no more gifts, and nothing on it is pushed off (several accounts could otherwise wipe
  // out every gift a person was given).
  for (let i = 0; i < 100; i++) q("INSERT INTO visual_gift_received (to_id, from_id, gift_id, created_at) VALUES (200, ?, '32', 1)", [5000 + i]);
  const keepRow = q("INSERT INTO visual_gift_received (to_id, from_id, gift_id, created_at) VALUES (100, 5, '33', 1) RETURNING id")[0].id;
  r = await gifts('A', { send: { to: 200, gift: '1' } });
  check('a full profile refuses a new gift', r.status, 429);
  r = await gifts('A', { transfer: { ref: `r${keepRow}`, to: 200 } });
  check('and a gift passed on', r.status, 429);
  check('nothing pushed off the full profile', q('SELECT COUNT(*) AS c FROM visual_gift_received WHERE to_id = 200')[0].c, 100);
  check('the refused gift stays with its owner', q('SELECT COUNT(*) AS c FROM visual_gift_received WHERE id = ?', [keepRow])[0].c, 1);
  q('DELETE FROM visual_gift_received WHERE to_id IN (100, 200)');
  q('DELETE FROM visual_gift_sends');

  // 9l. A device a day behind does not put yesterday's numbers back over today's.
  await sync('A', { v: 2, pairs: [{ ...pair(1, 20400), count: 5, mine: 3, theirs: 3, day: 20430 }] });
  await sync('B', { v: 2, pairs: [{ ...pair(1, 20400), count: 9, mine: 0, theirs: 0, todayDone: false, day: 20429 }] });
  row = q('SELECT count, day FROM pairs WHERE owner_id = 100 AND friend_id = 1')[0];
  check('one day back is ignored', [row.count, row.day], [5, 20430]);

  // 9m. The bot offers a restore only from a row of the owner's current day; the request is kept until the app confirms it.
  const today = Math.floor(Date.now() / 1000 / 86400);
  const callback = async (from, data) => worker.fetch({ url: 'https://bot.example/tg', method: 'POST',
    headers: { get: (k) => (k === 'x-telegram-bot-api-secret-token' ? WEBHOOK : null) }, json: async () => ({ update_id: 2, callback_query: { id: 'q', from, data } }) }, env);
  const friend = { id: 600, first_name: 'F', language_code: 'ru' };
  const restorePair = { friend: 600, count: 4, mine: 0, theirs: 0, todayDone: false, restoresLeft: 5, lostCount: 0, startDay: today - 10 };
  // A second device of account 200: the streak must still be listed once.
  q('INSERT INTO owners (token_hash, tg_id, name, created_at) VALUES (?, 200, ?, 0)', ['f'.repeat(64), 'OwnerC2']);
  await sync('C', { v: 2, pairs: [{ ...restorePair, restorableDay: today - 2, day: today - 1 }] });
  sent.length = 0;
  await update({ message_id: 20, from: friend, chat: { id: 600, type: 'private' }, text: '/streaks' });
  let list = sent.find((m) => m.method === 'sendMessage');
  check('a stale row offers no restore', list.reply_markup, undefined);
  check('a streak is listed once with two devices', (list.text.match(/🔥 /g) || []).length, 1);
  sent.length = 0;
  await callback(friend, 'r:200');
  check('a stale restore is refused', [sent.find((m) => m.method === 'answerCallbackQuery').text, q('SELECT COUNT(*) AS c FROM restore_requests')[0].c], ['Восстановить уже нельзя', 0]);
  await sync('C', { v: 2, pairs: [{ ...restorePair, restorableDay: today - 1, day: today }] });
  sent.length = 0;
  await update({ message_id: 21, from: friend, chat: { id: 600, type: 'private' }, text: '/streaks' });
  list = sent.find((m) => m.method === 'sendMessage');
  check('a current row offers the restore', list.reply_markup.inline_keyboard.map((b) => b[0].callback_data), ['r:200']);
  await callback(friend, 'r:200');
  check('the restore is asked for', q('SELECT day FROM restore_requests WHERE owner_id = 200').map((x) => x.day), [today - 1]);
  r = await sync('C', { v: 2, pairs: [{ ...restorePair, restorableDay: today - 1, day: today }] });
  check('the request is handed over', r.body.restores, [{ friend: 600, day: today - 1 }]);
  check('and kept until confirmed', q('SELECT COUNT(*) AS c FROM restore_requests WHERE owner_id = 200')[0].c, 1);
  r = await sync('C', { v: 2, pairs: [{ ...restorePair, restorableDay: null, day: today, restored: [today - 1] }] });
  check('a confirmed request goes', q('SELECT COUNT(*) AS c FROM restore_requests WHERE owner_id = 200')[0].c, 0);
  q('INSERT INTO restore_requests (owner_id, friend_id, day, created_at) VALUES (200, 601, 5, 0)');
  r = await sync('C', { pairs: [] });
  check('an old app gets the request once', [r.body.restores, q('SELECT COUNT(*) AS c FROM restore_requests WHERE owner_id = 200')[0].c], [[{ friend: 601, day: 5 }], 0]);
  q("DELETE FROM owners WHERE name = 'OwnerC2'");

  // 9n. "/start l<token>" links only after the button is pressed, and never moves a token to another account.
  const linkToken = '1'.repeat(48);
  const linkHash = call({ op: 'sha256', bytes: Array.from(new TextEncoder().encode(linkToken)) });
  sent.length = 0;
  await update({ message_id: 30, from: { id: 700, first_name: 'L', language_code: 'ru' }, chat: { id: 700, type: 'private' }, text: '/start l' + linkToken });
  check('the link asks first', [q('SELECT COUNT(*) AS c FROM owners WHERE token_hash = ?', [linkHash])[0].c, sent[0].reply_markup.inline_keyboard[0][0].callback_data], [0, 'l:' + linkToken]);
  await callback({ id: 700, first_name: 'L', language_code: 'ru' }, 'l:' + linkToken);
  check('the button links', q('SELECT tg_id FROM owners WHERE token_hash = ?', [linkHash]).map((x) => x.tg_id), [700]);
  await callback({ id: 701, first_name: 'M', language_code: 'ru' }, 'l:' + linkToken);
  check('a linked token stays with its account', q('SELECT tg_id FROM owners WHERE token_hash = ?', [linkHash]).map((x) => x.tg_id), [700]);
  r = await login(call({ op: 'webappdata', id: 701 }), linkToken);
  check('nor through the signed login', [r.status, q('SELECT tg_id FROM owners WHERE token_hash = ?', [linkHash])[0].tg_id], [409, 700]);

  // 9o. An unproven sender's report gets no reply mapping: the admin's answer would go to whoever they named.
  const supportRows = q('SELECT COUNT(*) AS c FROM support')[0].c;
  sent.length = 0;
  r = await post('/api/feedback', { kind: 'bug', text: 'Claimed to be 200', userId: 200 }, { 'cf-connecting-ip': '7.7.7.7' });
  check('no reply mapping for an unproven sender', q('SELECT COUNT(*) AS c FROM support')[0].c, supportRows);
  check('the admin is told', sent.some((m) => /не подтверждён — ответ/.test(m.text || '')), true);

  // 9p. The admin's own donation is thanked and logged.
  sent.length = 0;
  await update({ message_id: 40, from: admin, chat: { id: admin.id, type: 'private' }, successful_payment: { currency: 'XTR', total_amount: 5, invoice_payload: 'donate:5' } });
  check('admin donation thanked and logged', [sent.some((m) => /Спасибо/.test(m.text || '')), sent.some((m) => /Донат 5/.test(m.text || ''))], [true, true]);

  // 9q. A broadcast drain claims its rows; a 429 puts the rest back in order, the counts are written per broadcast.
  const bc = q('INSERT INTO broadcasts (total, created_at) VALUES (3, 0) RETURNING id')[0].id;
  for (const chat of [801, 802, 803]) q('INSERT INTO broadcast_queue (broadcast_id, chat_id, from_chat, msg_id, created_at) VALUES (?, ?, 1, 1, ?)', [bc, chat, Math.floor(Date.now() / 1000)]);
  rateLimitedChat = 802;
  const cron = async () => {
    let pending;
    await worker.scheduled({ scheduledTime: Date.UTC(2026, 0, 1, 0, 1) }, env, { waitUntil: (p) => { pending = p; } });
    await pending;
  };
  sent.length = 0;
  await cron();
  check('rate limited: the rest stays queued', q('SELECT chat_id FROM broadcast_queue WHERE broadcast_id = ? ORDER BY id', [bc]).map((x) => x.chat_id), [802, 803]);
  rateLimitedChat = null;
  await cron();
  check('drained once each, reported', [q('SELECT delivered, done FROM broadcasts WHERE id = ?', [bc]).map((x) => [x.delivered, x.done])[0],
    sent.filter((m) => m.method === 'copyMessage' && m.chat_id >= 801 && m.chat_id <= 803).map((m) => m.chat_id),
    sent.filter((m) => /Рассылка завершена/.test(m.text || '')).length], [[3, 1], [801, 802, 802, 803], 1]);
  // A row another drain has claimed and is still sending is out of the queue: the broadcast is not reported yet.
  const bc2 = q('INSERT INTO broadcasts (total, created_at) VALUES (2, 0) RETURNING id')[0].id;
  q('INSERT INTO broadcast_queue (broadcast_id, chat_id, from_chat, msg_id, created_at) VALUES (?, 804, 1, 1, ?)', [bc2, Math.floor(Date.now() / 1000)]);
  await cron();
  check('a row in flight elsewhere: not reported yet', q('SELECT delivered, done FROM broadcasts WHERE id = ?', [bc2]).map((x) => [x.delivered, x.done])[0], [1, 0]);

  // 9r. Checking IDs has an hourly budget per account.
  q('INSERT OR REPLACE INTO check_budget (tg_id, period, used) VALUES (100, ?, 40000)', [Math.floor(Date.now() / 1000 / 3600)]);
  const badge = async (device, body) => {
    const response = await worker.fetch({ url: 'https://bot.example/api/badge', method: 'POST',
      headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS[device] : null) }, json: async () => body }, env);
    return response.status;
  };
  check('over the budget: badge refused', await badge('B', { show: true, check: [1] }), 429);
  check('over the budget: gifts refused', (await gifts('A', { check: [1] })).status, 429);
  check('no check, no budget needed', (await gifts('A', { check: [] })).status, 200);
  q('DELETE FROM check_budget');
  check('within the budget', await badge('B', { show: true, check: [1] }), 200);

  // 9s. Security fixes (2026-11-25).
  const tgUpdate = async (update, secret) => {
    const response = await worker.fetch({ url: 'https://bot.example/tg', method: 'POST',
      headers: { get: (k) => (k === 'x-telegram-bot-api-secret-token' ? secret : null) }, json: async () => update }, env);
    return response.status;
  };
  const secret = (await call({ op: 'sha256', bytes: Array.from(new TextEncoder().encode('x:webhook')) })).slice(0, 48);
  // Without BOT_TOKEN the webhook refuses everything, even the secret made from an empty token.
  const noToken = { ...env, BOT_TOKEN: '' };
  const emptySecret = (await call({ op: 'sha256', bytes: Array.from(new TextEncoder().encode(':webhook')) })).slice(0, 48);
  const noTokenStatus = (await worker.fetch({ url: 'https://bot.example/tg', method: 'POST',
    headers: { get: (k) => (k === 'x-telegram-bot-api-secret-token' ? emptySecret : null) }, json: async () => ({}) }, noToken)).status;
  check('webhook without a token is closed', noTokenStatus, 503);
  check('wrong webhook secret refused', await tgUpdate({}, 'nope'), 403);
  const loginNoToken = await worker.fetch({ url: "https://bot.example/api/login", method: "POST",
    headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + 'e'.repeat(48) : null) },
    json: async () => ({ initData: call({ op: 'webappdata', id: 900 }) }) }, noToken);
  check("login without a token is refused", loginNoToken.status, 403);

  // "/start f<id>" names the owner only to someone in their list of streaks.
  const startF = async (fromId, ownerId) => {
    sent.length = 0;
    await tgUpdate({ message: { chat: { type: 'private', id: fromId }, from: { id: fromId, first_name: 'F', language_code: 'ru' }, text: `/start f${ownerId}` } }, secret);
    return (sent.find((m) => m.method === 'sendMessage') || {}).text || '';
  };
  q('DELETE FROM pairs WHERE owner_id = 200 AND friend_id = 910');
  check('a stranger asking about an ID learns no name', /OwnerC/.test(await startF(910, 200)), false);
  check('and gets the same reply as for an unknown ID', (await startF(910, 200)).replace(/собеседника/g, ''), (await startF(910, 123456)).replace(/собеседника/g, ''));
  q('INSERT OR REPLACE INTO streak_list (owner_id, friend_id, start_day, stopped, updated_at) VALUES (200, 910, 1, 0, 0)');
  check('someone in the owner\'s list is told who', /OwnerC/.test(await startF(910, 200)), true);
  q('DELETE FROM streak_list WHERE owner_id = 200 AND friend_id = 910');

  // Parallel syncs with one token: one passes the throttle.
  call({ op: 'reset' });
  const syncNoReset = async () => {
    const response = await worker.fetch({ url: 'https://bot.example/api/sync', method: 'POST',
      headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS.C : null) }, json: async () => ({ v: 2, pairs: [] }) }, env);
    return response.status;
  };
  const statuses = await Promise.all([syncNoReset(), syncNoReset(), syncNoReset()]);
  check('parallel syncs: one passes', statuses.filter((x) => x === 200).length, 1);
  // At most MAX_PAIRS (300) pairs per account, however many syncs bring new IDs.
  q('DELETE FROM pairs WHERE owner_id = 200');
  const many = (from) => Array.from({ length: 300 }, (_, i) => ({ ...pair(100000 + from + i), day: 20420 }));
  await sync('C', { v: 2, pairs: many(0) });
  await sync('C', { v: 2, pairs: many(300) });
  check('pairs capped per account', q('SELECT COUNT(*) AS c FROM pairs WHERE owner_id = 200')[0].c, 300);
  check('the list capped per account', q('SELECT COUNT(*) AS c FROM streak_list WHERE owner_id = 200')[0].c <= 600, true);
  // Restored days: only the recent ones, at most 10 a pair.
  q('DELETE FROM streak_restores WHERE owner_id = 200');
  const old = Array.from({ length: 60 }, (_, i) => 20360 + i);
  await sync('C', { v: 2, pairs: [{ ...pair(100000), restored: old }] });
  const days = q('SELECT day FROM streak_restores WHERE owner_id = 200 AND friend_id = 100000').map((x) => x.day);
  check('restored days: the newest 10, within 30 days', [days.length, Math.min(...days) >= 20390], [10, true]);
  q('DELETE FROM pairs WHERE owner_id = 200');
  q('DELETE FROM streak_list WHERE owner_id = 200');
  q('DELETE FROM streak_restores WHERE owner_id = 200');

  // New-streak notices: at most 20 a day per owner, with a button to say "I do not know them", which silences them.
  q('DELETE FROM notified');
  q('DELETE FROM notify_log');
  for (let i = 0; i < 25; i++) q('INSERT OR REPLACE INTO friends (tg_id, started_at, stopped) VALUES (?, 0, 0)', [300000 + i]);
  sent.length = 0;
  await sync('C', { v: 2, pairs: Array.from({ length: 25 }, (_, i) => pair(300000 + i)) });
  const notices = sent.filter((m) => m.method === 'sendMessage' && /начал\(а\) с тобой огонёк/.test(m.text || ''));
  check('notices capped per day', notices.length, 20);
  const muteButton = notices[0].reply_markup.inline_keyboard.flat().find((b) => /^m:/.test(b.callback_data));
  check('a notice can be silenced', muteButton.callback_data, 'm:200');
  sent.length = 0;
  await tgUpdate({ callback_query: { id: 'cb', from: { id: notices[0].chat_id, first_name: 'F', language_code: 'ru' }, data: muteButton.callback_data } }, secret);
  check('silenced', q('SELECT COUNT(*) AS c FROM muted WHERE friend_id = ? AND owner_id = 200', [notices[0].chat_id])[0].c, 1);
  sent.length = 0;
  await tgUpdate({ message: { chat: { type: 'private', id: notices[0].chat_id }, from: { id: notices[0].chat_id, first_name: 'F', language_code: 'ru' }, text: '/streaks' } }, secret);
  check('a silenced owner is not listed', /OwnerC/.test((sent.find((m) => m.method === 'sendMessage') || {}).text || ''), false);
  q('DELETE FROM pairs WHERE owner_id = 200');
  q('DELETE FROM streak_list WHERE owner_id = 200');
  q('DELETE FROM friends WHERE tg_id >= 300000');

  // A name made to look like a link loses the link shape in the bot's texts.
  q("UPDATE owners SET name = 'https://t.me/evil' WHERE tg_id = 200");
  q('INSERT OR REPLACE INTO friends (tg_id, started_at, stopped) VALUES (310000, 0, 0)');
  q('DELETE FROM notify_log');
  sent.length = 0;
  await sync('C', { v: 2, pairs: [pair(310000)] });
  const lure = (sent.find((m) => m.method === 'sendMessage') || {}).text || '';
  check('no link in a quoted name', [/t\.me/.test(lure), /https:\/\//.test(lure)], [false, false]);
  q("UPDATE owners SET name = 'OwnerC' WHERE tg_id = 200");
  q('DELETE FROM pairs WHERE owner_id = 200');
  q('DELETE FROM streak_list WHERE owner_id = 200');

  // Feedback: an IPv6 /64 is one sender; unverified feedback has a global hourly cap.
  q('DELETE FROM feedback');
  for (let i = 0; i < 5; i++) await post('/api/feedback', { kind: 'bug', text: 'v6 ' + i }, { 'cf-connecting-ip': `2001:db8:1:2::${i + 1}` });
  r = await post('/api/feedback', { kind: 'bug', text: 'v6 again' }, { 'cf-connecting-ip': '2001:0db8:0001:0002:ffff::9' });
  check('an IPv6 /64 is one sender', r.status, 429);
  const hour = Math.floor(Date.now() / 1000);
  for (let i = 0; i < 60; i++) q("INSERT INTO feedback (kind, text, tg_id, verified, ip, app, created_at) VALUES ('bug', 'x', NULL, 0, ?, '', ?)", ['10.0.' + i + '.1', hour]);
  r = await post('/api/feedback', { kind: 'bug', text: 'yet another' }, { 'cf-connecting-ip': '8.8.4.4' });
  check('unverified feedback capped per hour', r.status, 429);
  r = await post('/api/feedback', { kind: 'bug', text: 'from a linked app' }, { 'cf-connecting-ip': '8.8.4.4', authorization: 'Bearer ' + TOKENS.C });
  check('a linked sender still gets through', r.status, 200);
  q('DELETE FROM feedback');

  // Reminders: at most 40 a run, marked before sending, so the next run sends the rest and nothing twice.
  const nowS = Math.floor(Date.now() / 1000);
  const tz19 = (19 * 3600) - (nowS % 86400);   // a time zone where it is 19:xx now
  const dayAt = Math.floor((nowS + tz19) / 86400);
  q('UPDATE owners SET tz = ?, last_sync = ? WHERE tg_id = 200', [tz19, nowS]);
  for (let i = 0; i < 45; i++) {
    q('INSERT OR REPLACE INTO friends (tg_id, started_at, stopped) VALUES (?, 0, 0)', [320000 + i]);
    q('INSERT INTO pairs (owner_id, friend_id, count, mine, theirs, today_done, restores_left, restorable_day, lost_count, day, need, updated_at, reminded_day) VALUES (200, ?, 5, 3, 0, 0, 5, NULL, 0, ?, 3, ?, 0)', [320000 + i, dayAt, nowS]);
  }
  const reminderRun = async () => {
    sent.length = 0;
    let pendingRun;
    await worker.scheduled({ scheduledTime: Date.UTC(2026, 0, 1, 0, 15) }, env, { waitUntil: (p) => { pendingRun = p; } });
    await pendingRun;
    return sent.filter((m) => m.method === 'sendMessage' && /огонёк не погас/.test(m.text || '')).length;
  };
  check('reminders: 40 in a run', await reminderRun(), 40);
  check('reminders: the rest in the next', await reminderRun(), 5);
  check('reminders: nothing twice', await reminderRun(), 0);
  q('DELETE FROM pairs WHERE owner_id = 200');
  q('DELETE FROM friends WHERE tg_id >= 320000');

  // 10. Unlink forgets the list.
  call({ op: 'reset' });
  await worker.fetch({ url: 'https://bot.example/api/unlink', method: 'POST', headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS.A : null) }, json: async () => ({}) }, env);
  check('unlink clears list', q('SELECT COUNT(*) AS c FROM streak_list WHERE owner_id = 100')[0].c, 0);
  check('unlink clears visual gifts', q('SELECT COUNT(*) AS c FROM visual_gifts WHERE tg_id = 100')[0].c, 0);
  check('unlink clears given gifts', q('SELECT COUNT(*) AS c FROM visual_gift_received WHERE from_id = 100')[0].c, 0);

  print(failures ? `${failures} FAILED` : 'all passed');
})().catch((e) => print('Exception ' + e + '\n' + e.stack));
