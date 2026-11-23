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
globalThis.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  sent.push({ method: url.split('/').pop(), ...body });
  if (url.endsWith('/createInvoiceLink')) return { json: async () => ({ ok: true, result: 'https://t.me/$invoice' }) };
  if (url.endsWith('/createForumTopic')) return { json: async () => ({ ok: true, result: { message_thread_id: 500 + sent.length } }) };
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
  for (let i = 0; i < 20; i++) await gifts('A', { send: { to: 200, gift: '1' } });
  r = await gifts('A', { send: { to: 200, gift: '1' } });
  check('daily limit', r.status, 429);

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
  const admin = { id: 887825713, first_name: 'Admin', language_code: 'ru' };
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
  const moved = r.body.mineReceived.find((g) => g.id === anonId);
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

  // 10. Unlink forgets the list.
  call({ op: 'reset' });
  await worker.fetch({ url: 'https://bot.example/api/unlink', method: 'POST', headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS.A : null) }, json: async () => ({}) }, env);
  check('unlink clears list', q('SELECT COUNT(*) AS c FROM streak_list WHERE owner_id = 100')[0].c, 0);
  check('unlink clears visual gifts', q('SELECT COUNT(*) AS c FROM visual_gifts WHERE tg_id = 100')[0].c, 0);
  check('unlink clears given gifts', q('SELECT COUNT(*) AS c FROM visual_gift_received WHERE from_id = 100')[0].c, 0);

  print(failures ? `${failures} FAILED` : 'all passed');
})().catch((e) => print('Exception ' + e + '\n' + e.stack));
