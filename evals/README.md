# CLI Evals

`10x-evals` runs YAML-defined eval suites against the real builder stack. It does not reimplement agent behavior. Each run uses the existing `BuilderViewModel` flow, including planning, `ask_user` handling, context compaction, tool execution, project creation, build-fix loops, Xcode project generation, and simulator preview.

## Current Smoke Benchmarks

The default [smoke suite](./smoke-suite.yml) now covers five benchmark apps:

- `habit_tracker_build`: multi-screen CRUD, forms, streak state, and dashboard polish
- `budget_dashboard_build`: finance dashboard, scoped post-plan follow-up, and preview generation
- `recipe_library_answers_build`: content browsing plus `ask_user` handling with scripted answers
- `mindful_journal_onboarding_build`: design-sensitive build with onboarding context
- `travel_planner_plan_only`: higher-complexity planning benchmark that stops after the plan

## Prerequisites

- Sign in through the macOS app first.
  - The CLI reuses the saved session from `UserDefaults(suiteName: "app.10x.macos")`.
- Have simulator runtimes installed.
- Have a usable `10x-evals` binary.

## Fast Terminal Flow

Use the shell wrappers from the repo root:

```bash
./scripts/evals list
./scripts/evals smoke
./scripts/evals smoke --case habit_tracker_build
./scripts/evals run evals/smoke-suite.yml --case travel_planner_plan_only
./scripts/evals build
```

There is also a short alias for the default smoke run:

```bash
./scripts/evals-smoke --case budget_dashboard_build
```

## Binary Resolution

`./scripts/evals` resolves the CLI in this order:

1. `TENX_EVALS_BIN`
2. `./.derivedData/10x-evals/Build/Products/Debug/10x-evals`
3. a shared `10x-evals` Xcode scheme, if the checkout exposes one

If your checkout does not have a shared `10x-evals` scheme, point the wrapper at an existing binary:

```bash
TENX_EVALS_BIN=/absolute/path/to/10x-evals ./scripts/evals smoke
```

## Manual Build

If your checkout exposes the shared `10x-evals` scheme, you can still build manually:

```bash
xcodebuild \
  -project 10x-macos.xcodeproj \
  -scheme 10x-evals \
  -configuration Debug \
  -derivedDataPath .derivedData/10x-evals \
  build CODE_SIGNING_ALLOWED=NO
```

The expected binary path is:

```bash
./.derivedData/10x-evals/Build/Products/Debug/10x-evals
```

## Suite Format

Top-level keys:

- `suite`
- `defaults` (optional)
- `cases`

Per-case keys:

- `id`
- `prompt`
- `project_name` (optional)
- `onboarding` with `design_style`, `target_audience`, `additional_details` (optional)
- `question_strategy` (`skip`, `answers_then_skip`, `fail`)
- `question_answers` (optional)
- `steps` (optional)
- `timeouts` (optional)

Supported v1 steps:

- `wait_for_plan`
- `approve_plan`
- `send_message`
- `wait_for_preview`
- `wait_for_idle`
- `stop`

## What Gets Saved

Each eval run creates a normal builder project under:

```text
~/Library/Developer/TenXApp/<project-slug>/
```

Typical artifacts:

- `tenx/messages.json`
- `tenx/plan.md`
- `tenx/tasks.md`
- `planning/plan.md`
- `planning/tasks.md`
- `ios/<TargetName>.xcodeproj`
- `tenx/preview-screens/*.png`

## macOS App History

Yes. Eval-created projects and conversations are saved through the same project/message flow the macOS app uses:

- projects are created in `builder_projects`
- conversation history is fetched by the app from `builder_conversations` and `builder_messages`
- local chat/project artifacts are also written into the normal `~/Library/Developer/TenXApp/...` folders

That means eval-created projects show up in the app’s project history. If the app is already open, reload the home/project list or relaunch the app to fetch the newest remote projects.
