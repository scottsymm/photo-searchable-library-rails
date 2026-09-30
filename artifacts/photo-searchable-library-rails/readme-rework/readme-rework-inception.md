---
title: Holistic README Rework
  - inception
  - readme-rework
  - documentation
  - developer-experience
keywords: [README, Rails, Docker, Kamal, Thruster, Apple Photos bridge, local development]
incepted: 2026-09-30

# Holistic README Rework

## Idea

Rework `README.md` from its stale "Phase 1 foundation" description into a
complete, onboarding-first reference for the photo-searchable library Rails app.
The README explains what the application is and its technology stack, shows every
supported way to run it locally (with `bin/dev-docker` as the default and raw
`docker compose` in a collapsible section), treats the Apple Photos bridge as a
first-class citizen, and provides collapsible deep dives into the Rails/framework
implementation details. It is written for a first-time developer and doubles as
engineering evidence for a technical evaluator or AI reviewer.

## Goal

- Complete restructure of the README around onboarding, keeping all currently
  important sections (env-var table, routes, data/files, project layout,
  requirements, dev commands, license) relocated rather than removed.
- Describe the app and its technology accurately through Phases 1–4 (foundation,
  faces/people, UI parity, Apple Photos bridge).
- Document multiple local run paths: `bin/dev-docker` (default), raw `docker
  compose`, host-native Rails + sidecar, and the production image
  (`script/prod-smoke.sh`) with Kamal config posture.
- Document the Apple Photos bridge as the primary macOS ingest path, including
  pointing `--api-url` at the app.
- Add collapsible technical sections: architecture/data ownership, Rails
  multi-database setup, Solid Queue/Cable, sqlite-vec/vector search, import
  pipeline, Apple Photos bridge protocol, and Kamal/Thruster deployment.
- Highlight quality gates (tests, RuboCop, Brakeman, Docker build) and deferred
  roadmap items/tradeoffs as engineering evidence.
- Explicitly note the local Kamal deploy loop (`kamal-local-deploy`) as a
  separate, future effort; do not document `bin/kamal deploy -d local` until
  that work is verified.
- Ask before removing any existing section that is not simply relocated.

## Interview Results

**What should the README accomplish?**
I want it to describe the application and it's technology. i want to explain how to run the project locally: detailing multiple ways if that is true. i want to dive into tech details of some parts of the implementation or rails or framework usage in a collapsible way if a lot of detail

**Who is the primary reader?**
The primary reader is a developer running for the first time, as well as possibly an ai agent scraping for evaluating me as a developer for a job. We want to run through `bin/dev-docker` or using Kamal, if those are different and make sense. For collapsible technical detail, the architecture/data ownership, Rails multi-database setup, Solid Queue/Cable, sqlite-vec/vector search, import pipeline, Apple Photos bridge protocol, and Kamal/Thruster deployment all seem important.

**Which local paths are officially supported?**
`bin/dev-docker` is the default workflow, with raw `docker compose` steps available under a collapsible section. Kamal is a second officially supported path, but its exact local shape needs clarification.

**What should we showcase for a developer/evaluator audience?**
The README should include engineering evidence: Rails 8.1 and Hotwire, sidecar separation for ML inference, SQLite/sqlite-vec and multi-database Solid adapters, background processing with Turbo Stream updates, Apple Photos bridge protocol compatibility, quality gates (tests, RuboCop, Brakeman, Docker build), and deferred roadmap items with known tradeoffs.

**How should Kamal be described?**
Kamal is documented per the local-only posture: the production image and `bin/kamal config` are verifiable locally, `script/prod-smoke.sh` exercises the production image, and a future section covers the local Kamal deploy loop once that separate effort (`kamal-local-deploy`) is verified working. `bin/dev-docker` is the default run path, with raw `docker compose` steps in a collapsible section.

**Should the README keep existing accurate sections?**
Do a complete restructure, but ask questions before completely removing something that is not just moved around.

**How central is the Apple Photos bridge?**
The Apple Photos bridge is a first class citizen — you really need it to get any photos on a Mac.

## Timeline
(Consider the time taken to complete the task. Include any timelines or deadlines that are expected, but leave placeholders during the interview.)
