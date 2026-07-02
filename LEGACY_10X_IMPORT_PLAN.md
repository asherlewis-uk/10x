# Legacy 10x Local Project Import Plan (11x)

## Goal
Add first-class, local-only import of legacy projects created by the original 10x app so they can be opened, previewed, built, and exported in 11x without remote login, Supabase, Superwall, billing, hosted deploy, or vendor services.

## Scope Locks (from AGENTS.md)
- The original 10x project folder under `~/Library/Developer/TenXApp/` must stay untouched.
- Import must copy, never move.
- No Supabase/Superwall/billing/credits/paywalls/hosted deploy/vendor auth/vendor backend/App Store submission automation may be reintroduced.
- Provider logic, signing/release lanes, and push behavior are not changed.
- No push is performed.

## Discovered Legacy Folder Layout

Observed sample root:
`/Users/asherlewis/Library/Developer/TenXApp/promptyou-are-building-the-native-ios-client-for-d2b7f292`

Top-level structure:
```
.git/                                     # git history (skipped by default)
.gitignore
.tenx/
  project.json                            # {projectId, name, slug, bundleId, targetName, platform, ownerId, lastUpdated}
  manifest.json                           # {name, projectType, workspaceRoot, xcodeProject, xcodeGenSpec, scheme, bundleIdentifier, createdWith, icon}
  messages.json                           # [{id, role, content, conversation_id, mode, attachments, created_at}, ...]
  chats.json                              # {activeChatId, chats:[{id,name,messageCount,lastMessagePreview,isAutoNamed,createdAt,updatedAt}]}
  chats/<chatId>/state.json               # optional per-chat state
  file_tree.json                          # {"Relative/Path.swift":"file contents", ...}
  plan.md                                 # generated plan
  tasks.md                                # generated task list
  project-status.json                     # build/publish status metadata
  build-suggestions.json                  # build hints
  publishing-state.json                   # legacy publishing metadata
  commit-messages.json                    # generated commit messages
conversation.md                           # human-readable conversation log
README.md
PRODUCTION.md
idea/
  README.md, brief.md, milestones.md
release/
  CHANGELOG.md, README.md
growth/
  README.md
  app-store/                              # inert marketing docs only
    app-store-description.txt
    app-privacy-guidance.md
    privacy-policy.md
    keywords.txt
    review-notes.md
    README.md
    support.md
    terms-of-service.md
    submission.json
    promotional-text.txt
ios/
  .tenx-source-manifest.json              # {targetName, files:[...]}
  project.yml                             # XcodeGen spec
  <TargetName>.xcodeproj/                 # generated Xcode project bundle
  <TargetName>/                           # generated Swift sources
    App.swift
    TenXPreviewSupport.swift
    Components/
    Models/
    ViewModels/
    Views/
    Assets.xcassets/
```

## Candidate Detection Rules
1. A directory is a legacy 10x candidate if it directly contains **either**:
   - `.tenx/project.json`, or
   - `ios/project.yml`.
2. For scan mode, enumerate immediate children of `~/Library/Developer/TenXApp/` and apply rule 1.
3. For manual mode, apply rule 1 to the user-selected directory.
4. A candidate is considered "importable" if it also has a non-empty `ios/` tree or a `file_tree.json`. Partial metadata is accepted and reported as unavailable where missing.

## Metadata Files Found and Their Use

| Legacy File | Imported As | Notes |
|---|---|---|
| `.tenx/project.json` | Project name, legacy ID, target/scheme hints | Primary source of project identity. `projectId` used as stable legacy ID for duplicate detection. |
| `.tenx/manifest.json` | Workspace/container/scheme/bundle identifier fallback | Used when `project.json` is absent. |
| `ios/.tenx-source-manifest.json` | Source manifest asset + file list for verification | Stored as asset; `files` used to cross-check copied source tree. |
| `ios/project.yml` | Candidate detection + XcodeGen spec asset | Stored as asset. |
| `.tenx/file_tree.json` | 11x `fileTree` / Version record | Primary source for the in-app file tree used by canvas and preview. |
| `.tenx/messages.json` | 11x `messages` + chat state | Mapped into a single 11x chat; empty `conversation_id` normalized to the chat id. |
| `.tenx/chats.json` + `chats/<id>/state.json` | Chat name/active chat fallback | Used to name the imported chat if present. |
| `.tenx/plan.md` | `projectPlan` / local `tenx/plan.md` + `planning/plan.md` | Saved via `LocalProjectStore.saveProjectStatus`. |
| `.tenx/tasks.md` | `projectTasks` / local `tenx/tasks.md` + `planning/tasks.md` | Saved via `LocalProjectStore.saveProjectStatus`. |
| `conversation.md` | Asset under `legacy-docs/` | Kept as read-only reference. |
| `README.md`, `PRODUCTION.md` | Assets under `legacy-docs/` | Inert reference docs. |
| `idea/*`, `release/*` | Assets under `legacy-docs/idea/` and `legacy-docs/release/` | Inert reference docs. |
| `growth/app-store/*` | Assets under `legacy-docs/growth/app-store/` | Inert marketing docs only; never wired to App Store submission automation. |

## Mapping into 11x SQLite Tables/Repositories

### New table: `legacy_imports`
```sql
CREATE TABLE IF NOT EXISTS legacy_imports (
    id TEXT PRIMARY KEY NOT NULL,
    source_path TEXT NOT NULL,
    legacy_project_id TEXT,
    manifest_id TEXT,
    content_fingerprint TEXT NOT NULL,
    project_id TEXT NOT NULL,
    imported_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_legacy_imports_source_path ON legacy_imports(source_path);
CREATE INDEX IF NOT EXISTS idx_legacy_imports_legacy_project_id ON legacy_imports(legacy_project_id);
```
This table is the source of truth for duplicate prevention and import reports.

### Existing tables used read/write
- `projects` — new row created via `ProjectRepository.createProject` with local `user_id` from `ProfileRepository`.
- `versions` — one version created via `VersionRepository.createVersion` using `file_tree.json` as the file tree and the first user prompt (or project name) as the prompt.
- `messages` — not written directly; chat state is persisted through `LocalProjectStore` which stores structured JSON in the app support `tenx/` directory. The `MessageRepository` table will naturally contain the same messages if future code synchronizes there; the import path does not bypass `LocalProjectStore`.
- `assets` — each imported doc/markdown/spec is written through `LocalAssetStorage` + `AssetRepository` under `projects/<projectId>/generated/legacy-docs/...`.

## Generated Source Copy Destination

The legacy `ios/` directory is copied into the 11x project directory produced by `XcodePreviewService.projectDir(for:projectId:)`:
```
~/Library/Application Support/11x/<safeName>-<projectIdPrefix>/
  ios/                                     # copied from legacy ios/
  tenx/                                    # populated by LocalProjectStore
  planning/                                # populated by LocalProjectStore
  assets/                                  # legacy doc assets written here
```
Copying uses `FileManager.copyItem` so `.xcodeproj` bundles and `Assets.xcassets` bundles are preserved recursively. `project.yml` and `.tenx-source-manifest.json` are copied with the rest of `ios/`.

## Asset/Docs Mapping

All non-source docs are stored via `LocalAssetStorage` with kind `.generated` and subdirectory prefixes:
- root docs → `legacy-docs/`
- `.tenx/plan.md` / `.tenx/tasks.md` → also stored as assets in `legacy-docs/tenx/` (in addition to being saved as active plan/tasks by `LocalProjectStore`).
- `idea/*` → `legacy-docs/idea/`
- `release/*` → `legacy-docs/release/`
- `growth/app-store/*` → `legacy-docs/growth/app-store/` (inert only)
- `ios/.tenx-source-manifest.json` → `legacy-docs/tenx/ios-source-manifest.json` (asset copy)
- `ios/project.yml` → `legacy-docs/tenx/ios-project.yml` (asset copy)

## Messages/History Mapping

Legacy message shape:
```json
{
  "id": "...",
  "role": "user" | "assistant",
  "content": "...",
  "conversation_id": "",
  "mode": "idea" | "build",
  "attachments": [],
  "created_at": "2026-07-01T23:37:23Z"
}
```

Mapping:
- `role` maps directly to `BuilderMessage.role`.
- `content` maps to `BuilderMessage.content`.
- `conversation_id` empty string is treated as missing; all messages are placed in a single imported chat with a deterministic id derived from the legacy active chat id or a fresh UUID.
- `created_at` maps to `BuilderMessage.createdAt`.
- `id` is reused when it is a valid UUID string; otherwise a fresh deterministic UUID is generated from `legacyProjectId|legacyMessageId`.
- `mode` maps to `BuilderMessage.mode`.
- Attachments are dropped (reported unavailable) because legacy attachment file paths are not reliably resolvable from the import source; the import still succeeds.

The resulting messages are stored through `LocalProjectStore.saveChatState`, `saveChatIndex`, and `saveMessages` so the existing chat loading path (`BuilderViewModel.initializeChats`) works unchanged.

## Duplicate-Import Strategy

Before creating a new 11x project, query `legacy_imports`:
1. If `source_path` matches exactly → report `alreadyImported`.
2. Else if `legacy_project_id` matches the stable id from `.tenx/project.json` → report `alreadyImported` with the existing 11x project reference.
3. Else compute a `content_fingerprint` (SHA-256 of `.tenx/project.json` + `ios/.tenx-source-manifest.json` + `ios/project.yml`, or of the available files). If the fingerprint matches an existing import → report `alreadyImported`.
4. Only if none match, create the project and insert a `legacy_imports` row.

## `.git` Handling Decision

`.git` is **skipped by default**. The importer accepts a `preserveGitHistory: Bool` parameter for future callers, but the default UI flow passes `false`. The scan enumerator ignores `.git`, and the file copy step skips it unconditionally. Tests verify the legacy `.git` directory is untouched and not copied.

## App Store / Growth Artifact Handling Decision

`growth/app-store/` files are copied only as inert assets under `legacy-docs/growth/app-store/`. They are **never** parsed into `AppStoreReviewState`, `AppStoreSubmissionDraft`, or any active App Store submission automation. `AppStoreSubmissionFactCollector` and `AppStoreReviewRenderer` are not invoked by the import path.

## Failure Modes

| Failure | Behavior |
|---|---|
| Selected folder is not a legacy 10x project | Throw `LegacyTenXImportError.notLegacyProject` with a clear message. |
| Duplicate import detected | Return report with `alreadyImported == true` and the existing 11x project id; no mutation. |
| Legacy `ios/` missing but `file_tree.json` present | Still create project, import `file_tree.json` into the version, report `iosDirectoryUnavailable`. The project opens in canvas but preview/build requires regenerating sources. |
| `file_tree.json` missing but `ios/` present | Create project, copy `ios/` sources, report `fileTreeUnavailable`. Preview/build may work if the xcode project is intact. |
| Both `file_tree.json` and `ios/` missing | Throw `LegacyTenXImportError.nothingImportable`. |
| Messages/history missing | Report `messagesUnavailable`; project still created. |
| Plan/tasks missing | Report `planUnavailable`/`tasksUnavailable`; project still created. |
| Asset copy fails for an individual doc | Log error, add to `unavailable` list, continue import. |
| Project name in `project.json` is empty or unusable | Fall back to sanitized folder name. |

## Tests Needed

Add `10x-macosTests/LegacyTenXProjectImporterTests.swift` with in-memory fixture projects:

1. Detects a legacy project fixture with `.tenx/project.json`.
2. Detects a legacy project fixture with `ios/project.yml` (and no `.tenx/project.json`).
3. Imports a project without remote login (uses `ProfileRepository` + `ProjectRepository` only).
4. Copy semantics: legacy folder still exists and is unchanged after import.
5. Does not mutate legacy folder (file modification times unchanged where possible; at minimum no deletions/moves).
6. Skips `.git` by default (legacy `.git/` untouched, copied project has no `.git`).
7. Creates an 11x SQLite `projects` row.
8. Imports generated `ios/` files into the 11x project directory.
9. Imports messages/history if present and loads them through `LocalProjectStore`.
10. Imports plan/tasks/docs if present and saves them as active plan/tasks + legacy-doc assets.
11. Imports `growth/app-store/` files as inert assets only (no active App Store submission state).
12. Handles missing/partial `.tenx` metadata gracefully.
13. Duplicate import is prevented or clearly reported.
14. After import, forbidden-audit active checks still pass.

## Implementation Files (planned)

1. `10x-macos/Services/DB/migrations/011_legacy_imports.sql` — new `legacy_imports` table.
2. `10x-macos/Services/DB/MigrationSet.swift` — register migration 011.
3. `10x-macos/Services/DB/Repositories/LegacyImportRepository.swift` — duplicate checks and record insertion.
4. `10x-macos/Services/LegacyTenXProjectImporter.swift` — detection, scanning, copying, mapping, report.
5. `10x-macos/Models/LegacyTenXImportReport.swift` — import report model.
6. `10x-macos/ViewModels/BuilderViewModel+LegacyTenXImport.swift` — thin wrapper methods for UI.
7. `10x-macos/Views/LegacyTenXImportSheet.swift` — scan + manual import sheet.
8. `10x-macos/Views/HomeView.swift` — add `Import from 10x` button.
9. `10x-macos/Views/Settings/StorageSettingsView.swift` — add `Import Legacy 10x Projects` button.
10. `10x-macosTests/LegacyTenXProjectImporterTests.swift` — unit/integration tests with fixture helpers.

## Verification Plan

After implementation:
1. `git diff --check`
2. `xcrun swift test`
3. `./scripts/forbidden-audit`
4. `./scripts/build-lanes/verify-unsigned.sh`

Commit message:
```
feat(import): add legacy 10x local project import
```
