CREATE TABLE IF NOT EXISTS local_profile (
    id TEXT PRIMARY KEY NOT NULL,
    email TEXT,
    name TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
