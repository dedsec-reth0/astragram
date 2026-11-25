-- AstraGram streak bot. Only numbers are kept: no message texts ever reach the bot.
CREATE TABLE IF NOT EXISTS owners (
  token_hash TEXT PRIMARY KEY,          -- SHA-256 of the token AstraGram keeps in the Keychain
  tg_id INTEGER NOT NULL,               -- the AstraGram user's Telegram ID (from pressing Start)
  name TEXT NOT NULL,                   -- their first name, shown to the other person
  created_at INTEGER NOT NULL,
  last_sync INTEGER NOT NULL DEFAULT 0,
  tz INTEGER NOT NULL DEFAULT 0         -- seconds from UTC, for the evening reminder
);
CREATE INDEX IF NOT EXISTS owners_tg ON owners(tg_id);

CREATE TABLE IF NOT EXISTS pairs (
  owner_id INTEGER NOT NULL,
  friend_id INTEGER NOT NULL,
  count INTEGER NOT NULL,
  mine INTEGER NOT NULL,                -- the AstraGram user's messages today
  theirs INTEGER NOT NULL,              -- the other person's messages today
  today_done INTEGER NOT NULL,
  restores_left INTEGER NOT NULL,
  restorable_day INTEGER,
  lost_count INTEGER NOT NULL,
  day INTEGER NOT NULL,
  need INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  reminded_day INTEGER NOT NULL DEFAULT -1,
  PRIMARY KEY (owner_id, friend_id)
);
CREATE INDEX IF NOT EXISTS pairs_friend ON pairs(friend_id);

-- The account's list of streaks, shared by all of its devices (apps from version 2): the day each streak started, or
-- stopped = 1 once a device turned it off (a mark kept for 30 days, so the other devices turn it off too).
CREATE TABLE IF NOT EXISTS streak_list (
  owner_id INTEGER NOT NULL,
  friend_id INTEGER NOT NULL,
  start_day INTEGER NOT NULL,
  stopped INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (owner_id, friend_id)
);

-- Days restored on one of the account's devices (a restore asked for in the bot reaches one device): every device of the
-- account counts them.
CREATE TABLE IF NOT EXISTS streak_restores (
  owner_id INTEGER NOT NULL,
  friend_id INTEGER NOT NULL,
  day INTEGER NOT NULL,
  PRIMARY KEY (owner_id, friend_id, day)
);

CREATE TABLE IF NOT EXISTS friends (
  tg_id INTEGER PRIMARY KEY,
  started_at INTEGER NOT NULL,
  stopped INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS restore_requests (
  owner_id INTEGER NOT NULL,
  friend_id INTEGER NOT NULL,
  day INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (owner_id, friend_id, day)
);

-- A single row the app reads at launch to decide whether it may run. Set only through POST /api/control (owner token).
CREATE TABLE IF NOT EXISTS app_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  blocked INTEGER NOT NULL DEFAULT 0,
  message TEXT NOT NULL DEFAULT '',
  message_en TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL DEFAULT 0
);

-- Small key/value store for the admin's state (awaiting a post, the pending post reference).
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL DEFAULT 0
);

-- Tech support. A user's message is forwarded to the admin; this maps the forwarded message to the user, so the
-- admin's reply to it is relayed back. One row per forwarded message.
CREATE TABLE IF NOT EXISTS support (
  admin_msg_id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

-- Broadcast queue: the admin's post is copied to each recipient. Drained in batches (webhook + the cron), so a large
-- broadcast never exceeds a single invocation's limits.
CREATE TABLE IF NOT EXISTS broadcast_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  broadcast_id INTEGER NOT NULL DEFAULT 0,
  chat_id INTEGER NOT NULL,
  from_chat INTEGER NOT NULL,
  msg_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

-- One row per broadcast, so the admin gets a delivered/failed report once it has drained.
CREATE TABLE IF NOT EXISTS broadcasts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  total INTEGER NOT NULL,
  delivered INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  done INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Visual gifts: the Telegram gift IDs an AstraGram user put on their profile in AstraGram's gift shop (not bought,
-- only shown in AstraGram), as a JSON array. Other AstraGram apps get them only for the people in their own chats.
CREATE TABLE IF NOT EXISTS visual_gifts (
  tg_id INTEGER PRIMARY KEY,
  gifts TEXT NOT NULL DEFAULT '[]',
  updated_at INTEGER NOT NULL,
  changed_at INTEGER NOT NULL DEFAULT 0
);

-- Visual gifts one AstraGram user gave another for free: shown on the recipient's profile in AstraGram, with the sender.
-- The recipient can take one off (deletes the row).
CREATE TABLE IF NOT EXISTS visual_gift_received (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  to_id INTEGER NOT NULL,
  from_id INTEGER NOT NULL,
  gift_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS visual_gift_received_to ON visual_gift_received(to_id);
CREATE INDEX IF NOT EXISTS visual_gift_received_from ON visual_gift_received(from_id, created_at);

-- AstraGram users who show the AstraGram badge: other AstraGram users draw it beside their names.
CREATE TABLE IF NOT EXISTS badges (
  tg_id INTEGER PRIMARY KEY,
  updated_at INTEGER NOT NULL
);

-- Bug reports and ideas sent from AstraGram's settings. Forwarded to the admin at once; kept here for the record.
CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,                     -- bug | idea
  text TEXT NOT NULL,
  tg_id INTEGER,                          -- set only when the sender let AstraGram name them
  verified INTEGER NOT NULL DEFAULT 0,    -- 1: the account was proven by its streak-bot token
  ip TEXT NOT NULL DEFAULT '',
  app TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS feedback_ip ON feedback(ip, created_at);

-- What a visual gift's owner set on it, beside the gift itself (apps from 1.0.30): `ref` is 'o<gift ID>' for a gift the
-- owner put on from the shop, 'r<row>' for a visual_gift_received row. pinned_at > 0 pins it to the top of the profile
-- (in that order); hidden keeps it for the owner only; unique is the look it was upgraded to ({n, m, p, b}: number,
-- model, pattern, backdrop, as Telegram names them); text and anonymous are what the giver wrote and whether the giver's
-- name is kept from everyone but the recipient.
CREATE TABLE IF NOT EXISTS visual_gift_meta (
  tg_id INTEGER NOT NULL,
  ref TEXT NOT NULL,
  pinned_at INTEGER NOT NULL DEFAULT 0,
  hidden INTEGER NOT NULL DEFAULT 0,
  unique_look TEXT NOT NULL DEFAULT '',
  text TEXT NOT NULL DEFAULT '',
  anonymous INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (tg_id, ref)
);

-- The next number of each gift upgraded in AstraGram (its own count, apart from Telegram's).
CREATE TABLE IF NOT EXISTS visual_gift_numbers (
  gift_id TEXT PRIMARY KEY,
  next INTEGER NOT NULL
);

-- The visual gift each AstraGram user wears as their status (AstraGram shows it beside their name; everyone else sees
-- the user's own Telegram status).
CREATE TABLE IF NOT EXISTS visual_gift_worn (
  tg_id INTEGER PRIMARY KEY,
  ref TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- The Premium look of an AstraGram user with Local Premium (emoji status, name and profile colours, as JSON): other
-- AstraGram apps show it on that user; everyone else sees the user as Telegram does.
CREATE TABLE IF NOT EXISTS premium_look (
  tg_id INTEGER PRIMARY KEY,
  look TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Every visual gift an account gave or passed on, for the daily limit (GIFTS_PER_DAY). Apart from
-- visual_gift_received, so a recipient hiding gifts (or a trim) does not give the sender new ones. Kept a day.
CREATE TABLE IF NOT EXISTS visual_gift_sends (
  from_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS visual_gift_sends_from ON visual_gift_sends(from_id, created_at);

-- How many IDs each account asked about this hour in the badge's and the visual gifts' `check` (CHECK_IDS_PER_HOUR),
-- so nobody can sweep ID ranges to collect every AstraGram user. period is the hour (unix time / 3600).
CREATE TABLE IF NOT EXISTS check_budget (
  tg_id INTEGER PRIMARY KEY,
  period INTEGER NOT NULL,
  used INTEGER NOT NULL DEFAULT 0
);

-- A friend who said a streak's owner is not someone they know (the "🔕" button under the bot's first message about
-- it): the bot never names that owner to them again, reminds them of nothing from them and lists none of their numbers.
CREATE TABLE IF NOT EXISTS muted (
  friend_id INTEGER NOT NULL,
  owner_id INTEGER NOT NULL,
  PRIMARY KEY (friend_id, owner_id)
);

-- When the bot told someone about a new streak, per owner (NOTIFY_PER_DAY a day).
CREATE TABLE IF NOT EXISTS notify_log (
  owner_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS notify_log_owner ON notify_log(owner_id, created_at);

-- Who an AstraGram account is, for the admin panel only: names as Telegram reports them when the user writes to the bot
-- or links the app. Shown to nobody else.
CREATE TABLE IF NOT EXISTS profiles (
  tg_id INTEGER PRIMARY KEY,
  first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '',
  username TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL
);
