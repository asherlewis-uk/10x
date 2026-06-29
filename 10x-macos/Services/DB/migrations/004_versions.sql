CREATE TABLE IF NOT EXISTS versions (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL,
    version_number INTEGER NOT NULL,
    file_tree_json TEXT NOT NULL,
    prompt TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ready',
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_versions_project_id ON versions(project_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_versions_project_number ON versions(project_id, version_number);
