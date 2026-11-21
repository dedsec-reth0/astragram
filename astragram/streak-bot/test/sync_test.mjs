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
} } };
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

  // 10. Unlink forgets the list.
  call({ op: 'reset' });
  await worker.fetch({ url: 'https://bot.example/api/unlink', method: 'POST', headers: { get: (k) => (k === 'authorization' ? 'Bearer ' + TOKENS.A : null) }, json: async () => ({}) }, env);
  check('unlink clears list', q('SELECT COUNT(*) AS c FROM streak_list WHERE owner_id = 100')[0].c, 0);
  check('unlink clears visual gifts', q('SELECT COUNT(*) AS c FROM visual_gifts WHERE tg_id = 100')[0].c, 0);
  check('unlink clears given gifts', q('SELECT COUNT(*) AS c FROM visual_gift_received WHERE from_id = 100')[0].c, 0);

  print(failures ? `${failures} FAILED` : 'all passed');
})().catch((e) => print('Exception ' + e + '\n' + e.stack));
