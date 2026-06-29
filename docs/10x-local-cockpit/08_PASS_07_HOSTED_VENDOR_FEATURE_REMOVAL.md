# Pass 07 — Hosted Vendor Feature Removal

## Goal

Remove or replace hosted vendor capabilities that depend on vendor infrastructure.

## Remove or Disable

```text
hosted app publishing
vendor deploy backend
vendor project hosting
vendor app download pipeline
vendor public URL generation
billing-backed deployment
credit-backed deployment
vendor account quota checks
vendor hosted dashboard links
```

## Replace With

```text
local export
project zip export
generated source folder
optional git output folder
local preview
manual deploy instructions if already present
```

## UX Rule

If removing a hosted feature would break navigation, replace it with a clear local-mode explanation:

```text
Hosted publishing is not available in 11x.
Use local export instead.
```

Do not leave dead buttons that fail with vendor auth or credits errors.

## Tests

Add tests proving:

- Hosted deploy button is absent or redirected to local export.
- Vendor hosted URL is not required.
- Export works offline.
- Generated project can be saved locally.
- No billing or credit gate controls deploy/export.
- No vendor deploy endpoint remains active.

## Acceptance Criteria

- No vendor-hosted capability is reachable.
- Local export is the replacement path.
- Hosted failures are not part of normal UX.
