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

-- AstraGram users who show the AstraGram badge: other AstraGram users draw it beside their names.
CREATE TABLE IF NOT EXISTS badges (
  tg_id INTEGER PRIMARY KEY,
  updated_at INTEGER NOT NULL
);
