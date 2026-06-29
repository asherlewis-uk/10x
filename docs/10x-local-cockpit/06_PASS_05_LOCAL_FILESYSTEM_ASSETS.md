# Pass 05 — Local Filesystem Asset Storage

## Goal

Replace hosted/cloud storage assumptions with local portable asset storage.

## Storage Root

Use the isolated app support directory:

```text
~/Library/Application Support/11x/assets/
```

or equivalent per-platform app support path.

## Directory Shape

Recommended:

```text
assets/
  projects/
    <project_id>/
      uploads/
      generated/
      previews/
      exports/
      logs/
```

## SQL Metadata

Store:

```text
asset_id
project_id
kind
relative_path
mime_type
size_bytes
checksum
created_at
updated_at
deleted_at
```

## Rules

- Never store absolute paths in exportable project metadata unless required.
- Prefer relative paths under app support.
- Prevent path traversal.
- Validate file extension and MIME when applicable.
- Keep project export portable.
- Do not use Supabase buckets.
- Do not call hosted storage APIs.

## Tests

Add tests proving:

- Asset write creates file on disk.
- Asset metadata persists in SQL.
- Asset read resolves only inside storage root.
- Path traversal is rejected.
- Project export includes required assets.
- Deleting a project handles asset cleanup or tombstoning predictably.
- App boots offline with existing assets.

## Acceptance Criteria

- All generated/uploaded assets are local.
- SQL contains metadata, not blobs by default.
- Exports are portable.
- No cloud bucket dependency remains.
