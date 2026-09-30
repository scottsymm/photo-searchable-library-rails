---
title: Holistic README Rework — Spec
tags:
  - spec
  - readme-rework
  - documentation
  - developer-experience
keywords: [README, Rails, Docker, Kamal, Thruster, Apple Photos bridge, local development]
distilled: 2026-09-30

# Holistic README Rework — Spec

## Problem Statement

The repository has grown through four implementation phases, but `README.md`
still describes the project as "Phase 1 foundation" and lists People, Places,
and Apple Photos synchronization as planned future work. A developer or an AI
agent evaluating the repo cannot learn what the application is, how to run it,
or how the Apple Photos bridge fits in. The README needs a complete restructure
around current reality.

## Target Audience

- A developer running the project for the first time, who needs the shortest
  reliable path from clone to working app.
- A technical evaluator or AI agent scraping the repo to assess the author's
  engineering ability, who reads the README for architecture, stack choices,
  operational detail, and quality signals.

## Core Value Proposition

A single, onboarding-first README that accurately explains the application and
its Rails 8.1/Hotwire stack, documents every supported local execution path,
treats the Apple Photos bridge as the primary macOS ingest mechanism, and offers
collapsible deep dives into the interesting implementation details — so both a
new developer and an evaluator get value without wading through irrelevant
detail.

## MVP Scope

- **Restructure** the README around a first-run onboarding flow.
- **Keep, relocated:** intro, requirements, env-var configuration table, main
  routes table, data/files layout, project layout, development commands,
  license. Ask before removing anything not simply moved.
- **Rewrite the stale "Current Status"** into an accurate "What's implemented"
  roadmap covering Phases 1–4.
- **Local run paths:** `bin/dev-docker` (default), raw `docker compose` in a
  collapsible section, host-native Rails + sidecar, and the production image
  locally via `script/prod-smoke.sh` with the Kamal config posture.
- **Apple Photos bridge:** first-class documentation — what it is, why it is
  required on macOS, how to run it against the Rails app (`--api-url`).
- **Collapsible technical sections:** architecture/data ownership, Rails
  multi-database setup, Solid Queue/Cable, sqlite-vec/vector search, import
  pipeline, Apple Photos bridge protocol, Kamal/Thruster deployment.
- **Engineering evidence:** quality gates (tests, RuboCop, Brakeman, Docker
  build), deferred roadmap items, and known tradeoffs.
- **Scope boundary:** the local Kamal deploy loop is parked in a separate
  `kamal-local-deploy` inception; the README must not document
  `bin/kamal deploy -d local` as working until that effort is verified.

## Success Metrics

- A new developer can go from clone to a running app using only the README's
  default path.
- The README accurately reflects Phases 1–4 (no stale "planned follow-on" claims).
- Every supported local run path is documented with copy-pasteable commands.
- The Apple Photos bridge is discoverable and understood as the primary macOS
  ingest path.
- Technical evaluators/AI agents can find architecture, stack, quality gates,
  and tradeoffs without reading source code.
- Existing important content is preserved (moved, not deleted) unless explicitly
  reviewed for removal.

## Key Risks & Open Questions

- **Ordering:** the README should not document the local Kamal deploy loop until
  the `kamal-local-deploy` effort is verified; avoid implying a remote deployment
  is configured when servers/registry are placeholders.
- **Content preservation:** the "ask before removing" rule means each existing
  section's fate must be confirmed during the rewrite, not assumed.
- **Collapsible depth:** the deep-dive sections must stay maintainable — each
  should point at the relevant source files rather than duplicating code.
- **Open:** whether host-native Rails development remains an officially supported
  path or becomes a collapsible/advanced note.