---
title: Holistic README Rework — Design
tags:
  - design
  - readme-rework
  - documentation
  - developer-experience
created: 2026-09-30
---

# Holistic README Rework — Design

*Created: 2026-09-30*

**Goal:** Replace the stale `README.md` with a single, onboarding-first document
that accurately describes the application and stack, documents every supported
local run path, treats the Apple Photos bridge as first-class, and uses
collapsible `<details>` sections for technical deep dives — serving both a
first-run developer and a technical evaluator/AI agent.

**Source:** `readme-rework-spec.md` (this dir). Approach confirmed: single file,
`<details>` collapsibles; host-native Rails is a collapsible advanced section.

---

## Architecture Overview

One `README.md` file, ordered for a first-run developer, with a table of
contents and deep dives collapsed by default. The main flow reads top-to-bottom
on a single screen; every advanced topic is one `<details>` click away.
GitHub renders `<details>` natively, and because the content is present in the
raw markdown, AI crawlers and grep-based evaluators see everything.

```
1. Title + one-paragraph pitch
2. Feature / What it is (accurate Phases 1–4)
3. Architecture diagram + one-paragraph summary
4. Quick start (bin/dev-docker)  ← default path
5. What you get (routes/features map)
6. Apple Photos bridge (first-class, macOS)
7. Configuration table
8. Local run paths (details)
   ├─ raw docker compose
   └─ host-native Rails + sidecar
9. Production image & Kamal posture (details)
10. Technical deep dives (details)
    ├─ architecture/data ownership
    ├─ Rails multi-database
    ├─ Solid Queue / Cable
    ├─ sqlite-vec / vector search
    ├─ import pipeline
    ├─ Apple Photos bridge protocol
    └─ Kamal/Thruster
11. Quality gates
12. Roadmap & tradeoffs
13. Data & backups
14. Project layout
15. License
```

## Components

### 1. `README.md` (the only deliverable)
Complete rewrite. Every existing section is relocated (none silently dropped),
per the "ask before removing" rule — the current sections (Requirements, Quick
Start, Configuration, Main Routes, Development Commands, Data and Files, Project
Layout, License) are reorganized into the new flow rather than deleted.

### 2. Content inventory (source material)
Collected from the implemented repo, not invented:
- Routes: `config/routes.rb` (health, search, places, catalog, uploads, assets,
  jobs, admin/settings, persons/faces/suggestions, apple-photos bridge)
- Env vars: `config/initializers/pics.rb` (`PICS_*`, `MEDIA_SUFFIXES`) and
  `PICS_MAX_UPLOAD_BYTES`
- Dev commands: `bin/dev-docker`, `bin/dev-reset-docker`, `bin/dev`,
  `bin/jobs`, `bin/dev-photos-bridge`
- Quality gates: `bin/rails test`, `bin/rubocop`, `bin/brakeman`,
  `bin/bundler-audit`, `bin/importmap audit`, production `docker build`
- Deploy posture: `config/deploy.yml`, `script/prod-smoke.sh`, sidecar accessory
  image build/`bin/kamal accessory` lifecycle

### 3. Scope boundary (explicitly excluded)
The `kamal-local-deploy` loop is documented only as "future work"; the README
must not present `bin/kamal deploy -d local` as operational. The sidecar image
build + accessory commands ARE documented as current posture, since those are
verified.

## Data Flow (reader journey)

A new developer opens the README, reads the one-paragraph pitch, skims the
feature list, and runs the single quick-start command. When they hit a topic
that needs depth (why two SQLite DBs, how search works, how the bridge syncs),
the adjacent `<details>` block expands in place. An evaluator skims the TOC,
then greps/scrolls for architecture, quality gates, and tradeoffs — all present
as visible markdown text even when collapsed.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| File structure | Single `README.md` | One source of truth; GitHub-native; crawler-visible |
| Collapsible mechanism | `<details>/<summary>` | Spec requirement; GitHub renders it; content stays in markdown |
| Default run path | `bin/dev-docker` | Spec decision; raw compose stays in a `<details>` |
| Host-native Rails | Collapsible advanced section | Spec decision; preserves the path without front-loading |
| Bridge prominence | First-class section after quick start | Required to get photos on macOS; spec decision |
| Kamal | Config + production image + smoke; local loop deferred | `kamal-local-deploy` is a separate parked effort |
| Section preservation | All current sections relocated | Spec rule: ask before removing anything not simply moved |
| Evidence | Quality-gate commands verbatim | Evaluator/AI reads exact commands, not claims |

## Error Handling (maintainability)

- Deep dives point at source paths (`app/services/*`, `sidecar/`, `config/`)
  instead of duplicating code, so the README drifts less as code changes.
- Commands are copied verbatim from the repo's `bin/` scripts and the
  `kamal-thruster-deploy` verification, reducing the chance of stale docs.
- The "What's implemented" roadmap states Phases 1–4 accurately and lists
  deferred items (CLI, conformance harness, local Kamal loop) so the README
  cannot be mistaken for claiming unbuilt features.

## Testing Approach

Documentation has no runtime tests. The plan-level gates are:
1. Every command in the README is verified to exist (`ls bin/`, `bin/kamal
   config`, `script/prod-smoke.sh`).
2. Every route in the "What you get" section matches `config/routes.rb`.
3. Every env var matches `config/initializers/pics.rb`.
4. Links resolve and the file renders without broken markdown (TOC anchors,
   `<details>` balanced).
5. A reviewer (human or AI) can answer: what is this, how do I run it, how does
   the bridge fit, what are the quality gates — from the README alone.
6. The `kamal-local-deploy` boundary sentence is present and correct.