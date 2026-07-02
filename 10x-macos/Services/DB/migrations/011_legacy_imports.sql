CREATE TABLE IF NOT EXISTS legacy_imports (
    id TEXT PRIMARY KEY NOT NULL,
    source_path TEXT NOT NULL,
    legacy_project_id TEXT,
    manifest_id TEXT,
    content_fingerprint TEXT NOT NULL,
    project_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'in_progress',
    error_message TEXT,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    imported_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_legacy_imports_source_path ON legacy_imports(source_path);
CREATE INDEX IF NOT EXISTS idx_legacy_imports_legacy_project_id ON legacy_imports(legacy_project_id);
CREATE INDEX IF NOT EXISTS idx_legacy_imports_status ON legacy_imports(status);
