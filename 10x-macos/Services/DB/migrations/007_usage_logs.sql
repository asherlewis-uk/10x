CREATE TABLE IF NOT EXISTS usage_logs (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT,
    kind TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_usage_logs_project_id ON usage_logs(project_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_created_at ON usage_logs(created_at);
