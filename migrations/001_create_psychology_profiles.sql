CREATE TABLE IF NOT EXISTS psychology_profiles (
  username TEXT PRIMARY KEY CHECK (username ~ '^[a-z0-9_]{2,32}$'),
  state JSONB NOT NULL DEFAULT '{}'::jsonb,
  revision INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)