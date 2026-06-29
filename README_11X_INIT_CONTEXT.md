# 11x Init Context
This repository is a fork of the original 10x source.

The active product target is now 11x, an unlimited single-user local cockpit.

## Current Authoritative Docs

Current implementation docs live in:

    docs/10x-local-cockpit/

Start with:

    docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md

    docs/10x-local-cockpit/01_AGENT_EXECUTION_PROMPT.md

    docs/10x-local-cockpit/16_LOCAL_IMPLEMENTATION_DEFAULTS.md

## Archived Historical Docs

Archived 10x-era docs live in:

    docs/archive/

Archived docs are historical reference only and must not be treated as current scope.

## Locked Identity

App name: 11x

Bundle ID: app.kasey.11x

URL scheme: elevenx

Owned domain for optional Universal Links: asherlewis.online

## Scope Lock

Supabase: remove entirely

Superwall: remove entirely

Billing/pricing/credits/paywalls: remove entirely

Hosted vendor deploy: replace with local folder/zip export

Provider: OpenAI-compatible BYOK/local gateway

Persistence: SQLite by default

Vendor DMG: reference only; never modify, unpack, patch, resign, overwrite, or depend on it
