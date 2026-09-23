---
title: Rails Port Phase 2 — Faces and People Implementation Plan
tags:
  - plan
  - rails-port
  - phase-2
  - faces
  - people
created: 2026-09-19
---

# Rails Port Phase 2 — Faces and People Implementation Plan

*Created: 2026-09-19*

**Goal:** Add sidecar-backed face detection, face embeddings, clustering, and
people review to the completed Phase 1 Rails application without schema changes.

**Architecture:** InsightFace detection, face embeddings, and DBSCAN clustering
run in the stateless Python sidecar. Rails owns import orchestration, crop
files, vector persistence, Solid Queue jobs, people mutations, and Turbo/ERB
views. Face crops are JPEGs below `PICS_LIBRARY/.crops` and are served only
after containment validation.

**Tech Stack:** Rails 8.1, Active Record, SQLite/sqlite-vec, Solid Queue,
Minitest, FastAPI, InsightFace, NumPy/scikit-learn-compatible DBSCAN behavior,
ruby-vips, and Turbo/Stimulus.

**Source:** `rails-port-phase-2-design.md`; Phase 1 implementation and
`rails-port-discovery.md`.

## File Map

| File | Action | Responsibility |
|---|---|---|
| `sidecar/app.py` | Modify | Face detection, face embedding, clustering routes, and readiness |
| `sidecar/models.py` | Modify | Typed request/response models for face APIs |
| `sidecar/test_app.py` | Create | Sidecar API contract tests |
| `app/services/sidecar_client.rb` | Modify | Rails calls for detection and clustering |
| `app/services/face_detection.rb` | Create | Detect faces, crop images, persist face rows and vectors |
| `app/services/face_crop.rb` | Create | Crop naming, JPEG generation, and path containment |
| `app/services/face_clustering.rb` | Create | Cluster input selection and suggestion persistence |
| `app/jobs/import_job.rb` | Modify | Run face detection as part of image import |
| `app/jobs/cluster_faces_job.rb` | Create | Solid Queue wrapper for clustering and domain progress |
| `app/models/face.rb` | Modify | Face associations and validations |
| `app/models/face_embed.rb` | Modify | Face embedding association and vector metadata |
| `app/models/person.rb` | Modify | Person associations and mutation helpers |
| `app/models/person_alias.rb` | Modify | Alias validation and association |
| `app/models/person_face.rb` | Modify | Assignment associations and uniqueness behavior |
| `app/models/cluster_suggestion.rb` | Modify | Suggestion state helpers |
| `app/models/face_assignment.rb` | Modify | Cluster assignment state |
| `app/controllers/persons_controller.rb` | Create | People index, search, rename, and assignments |
| `app/controllers/person_suggestions_controller.rb` | Create | Confirm, reject, and restore actions |
| `app/controllers/person_aliases_controller.rb` | Create | Alias create/delete actions |
| `app/controllers/person_faces_controller.rb` | Create | Crop serving and manual assignment |
| `app/controllers/person_merges_controller.rb` | Create | Merge and split actions |
| `config/routes.rb` | Modify | People and face route mappings |
| `app/views/persons/index.html.erb` | Create | People list and review queue |
| `app/views/persons/_person.html.erb` | Create | Person card and aliases |
| `app/views/persons/_suggestion.html.erb` | Create | Cluster suggestion review card |
| `test/services/face_detection_test.rb` | Create | Detection, crop, vector, idempotency tests |
| `test/services/face_clustering_test.rb` | Create | Clustering and suggestion tests |
| `test/jobs/cluster_faces_job_test.rb` | Create | Job status and failure tests |
| `test/controllers/persons_controller_test.rb` | Create | People request tests |
| `test/controllers/person_mutations_controller_test.rb` | Create | Mutation and crop safety tests |
| `test/fixtures/two_faces.jpg` | Create | Deterministic face-detection acceptance fixture |
| `sidecar/pyproject.toml` | Modify | Add face model runtime dependencies |
| `sidecar/Dockerfile` | Modify | Install dependencies needed by InsightFace |
| `docker-compose.yml` | Modify | Pass face model configuration and readiness settings |

## Tasks

### Task 1: Lock the sidecar face API models

**Files:**
- Modify: `sidecar/models.py`
- Create: `sidecar/test_app.py`

- [x] Define request/response models for image face results, cluster requests,
  cluster responses, and 512-float validation.
- [x] Add tests for empty face results, invalid dimensions, mismatched label
  lengths, and accepted 512-dimensional vectors.
- [x] Verify with `docker compose run --rm --no-deps sidecar python -m unittest sidecar.test_app`.

### Task 2: Implement stub-mode face endpoints

**Files:**
- Modify: `sidecar/app.py`
- Modify: `sidecar/test_app.py`

- [x] Add `POST /v1/detect-faces` accepting multipart image data and returning
  deterministic stub boxes and 512-dimensional embeddings.
- [x] Add `POST /v1/cluster-faces` returning deterministic DBSCAN-compatible
  labels in stub mode, including `-1` noise labels.
- [x] Return HTTP 400 for invalid image/vector input and HTTP 503 when the real
  face model is unavailable.
- [x] Verify status, detection, and clustering with HTTP requests against a
  stub sidecar on port 9091.

### Task 3: Add real sidecar face inference

**Files:**
- Modify: `sidecar/app.py`
- Modify: `sidecar/pyproject.toml`
- Modify: `sidecar/Dockerfile`
- Modify: `docker-compose.yml`
- Modify: `sidecar/test_app.py`

- [x] Load InsightFace lazily in real mode and normalize each detected box to
  pixel coordinates plus a 512-dimensional float embedding.
- [x] Implement cosine-distance DBSCAN using the same `eps` and `min_samples`
  defaults as the reference implementation.
- [x] Keep model loading out of stub mode and report face readiness in
  `/v1/status`.
- [x] Verify the sidecar image builds and real mode reports readiness when the
  configured face model is available.

### Task 4: Implement safe crop generation

**Files:**
- Create: `app/services/face_crop.rb`
- Create: `test/services/face_detection_test.rb`

- [x] Generate a deterministic crop filename from asset ID, detection key, and
  source digest below `PICS_LIBRARY/.crops`.
- [x] Decode the source with ruby-vips, clamp boxes to image bounds, write a
  JPEG crop, and return a path relative to the crop root.
- [x] Add a containment helper that rejects traversal, absolute paths, and
  symlink escapes.
- [x] Verify normal crops, out-of-bounds boxes, missing sources, and path
  escape rejection with Minitest.

### Task 5: Persist detected faces and embeddings

**Files:**
- Create: `app/services/face_detection.rb`
- Modify: `app/services/sidecar_client.rb`
- Modify: `app/models/face.rb`
- Modify: `app/models/face_embed.rb`
- Modify: `app/jobs/import_job.rb`
- Modify: `test/services/face_detection_test.rb`

- [x] Add sidecar client methods for multipart face detection and JSON
  clustering with timeout and response validation.
- [x] For image assets, persist one face row per stable detection key, create
  its crop, store its 512-float little-endian vector in `face_embeds`, and
  insert the vector into `vec0_face`.
- [x] Make repeated imports update existing detections instead of duplicating
  faces or vector rows.
- [x] Skip videos and treat an empty face response as successful processing.
- [x] Ensure crop cleanup occurs when persistence fails and record retryable
  sidecar failures through the existing domain job.
- [x] Verify with a stub sidecar that import creates expected face rows,
  512-vector blobs, crop JPEGs, and no duplicates on re-import.

### Task 6: Add face clustering persistence

**Files:**
- Create: `app/services/face_clustering.rb`
- Create: `app/jobs/cluster_faces_job.rb`
- Modify: `app/models/cluster_suggestion.rb`
- Modify: `app/models/face_assignment.rb`
- Create: `test/services/face_clustering_test.rb`
- Create: `test/jobs/cluster_faces_job_test.rb`

- [x] Select unassigned faces with valid embeddings and create a
  `clustering_runs` record before calling the sidecar.
- [x] Persist cluster assignments and one reviewable suggestion per non-noise
  cluster without creating persons automatically.
- [x] Update the domain `jobs` row through queued, working, done, and error
  states with progress based on processed faces.
- [x] Make rerunning a completed run create a new run without corrupting prior
  review state.
- [x] Verify empty input, sidecar failure, noise labels, cluster persistence,
  and progress updates.

### Task 7: Add people models and transactional mutations

**Files:**
- Modify: `app/models/person.rb`
- Modify: `app/models/person_alias.rb`
- Modify: `app/models/person_face.rb`
- Modify: `app/models/cluster_suggestion.rb`
- Modify: `app/models/face_assignment.rb`
- Create: `test/models/person_test.rb`

- [x] Add associations, validations, and explicit `persons` table mapping.
- [x] Implement transactional confirm, reject, restore, manual assign, merge,
  and split operations with idempotent repeated calls.
- [x] Preserve aliases during merge and prevent duplicate person-face links.
- [x] Verify assignment uniqueness, merge behavior, split behavior, alias
  validation, and repeated mutation safety.

### Task 8: Add people and face HTTP routes

**Files:**
- Create: `app/controllers/persons_controller.rb`
- Create: `app/controllers/person_suggestions_controller.rb`
- Create: `app/controllers/person_aliases_controller.rb`
- Create: `app/controllers/person_faces_controller.rb`
- Create: `app/controllers/person_merges_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/persons_controller_test.rb`
- Create: `test/controllers/person_mutations_controller_test.rb`

- [x] Implement all Phase 2 people routes from the design with JSON and HTML
  responses where applicable.
- [x] Use strong parameters for rename, alias, merge, split, and assignment
  payloads.
- [x] Serve only crop paths that pass the containment check and return 404 for
  missing or unsafe paths.
- [x] Verify every route with request tests, including malformed IDs,
  duplicate actions, JSON shape, and crop traversal attempts.

### Task 9: Build the Turbo people review UI

**Files:**
- Create: `app/views/persons/index.html.erb`
- Create: `app/views/persons/_person.html.erb`
- Create: `app/views/persons/_suggestion.html.erb`
- Modify: `app/views/layouts/application.html.erb`

- [x] Render people, aliases, assigned face crops, and pending suggestions.
- [x] Add Turbo-compatible forms/actions for confirm, reject, restore, rename,
  alias management, manual assignment, merge, and split.
- [x] Show empty/loading/error states without breaking the existing Phase 1
  navigation.
- [x] Verify manually in a browser against the stub sidecar and confirm each
  mutation updates the rendered state.

### Task 10: Add the Phase 2 acceptance fixture and end-to-end check

**Files:**
- Create: `test/fixtures/two_faces.jpg`
- Modify: `test/services/face_detection_test.rb`
- Modify: `test/controllers/persons_controller_test.rb`

- [x] Add a deterministic fixture or stub response representing two detectable
  faces while keeping the test independent of downloaded model weights.
- [x] Import the fixture through the Rails job path and verify face rows,
  crop JPEGs, `face_embeds`, and `vec0_face` entries.
- [x] Run `ClusterFacesJob`, confirm a suggestion, and verify the person filter
  returns the related asset.
- [x] Verify the full suite with `docker compose run --rm --no-deps rails bin/rails test`.

## Verification Summary

- [x] `docker compose build rails sidecar` succeeds.
- [x] `docker compose run --rm --no-deps rails bin/rails test` passes.
- [x] `docker compose run --rm --no-deps rails bin/rubocop app lib test` reports no offenses.
- [x] `docker compose run --rm --no-deps rails bin/brakeman --no-pager` reports no warnings.
- [x] Stub sidecar detection and clustering endpoints return the documented
  shapes and 512-dimensional vectors.
- [x] A fixture import creates idempotent face rows, crops, and face vectors.
- [x] Clustering creates reviewable suggestions and updates the domain job.
- [x] Confirming a suggestion creates a person assignment and person-filtered
  search returns the associated asset.
- [x] Crop traversal and symlink escape requests return 404.

## Completion Status

Phase 2 functional verification is complete. The real InsightFace sidecar,
Rails import and persistence path, face clustering, people assignment and
mutation endpoints, person-filtered search, crop serving, and Docker/Rails
quality gates have been verified. A manual visual pass over every Turbo UI
mutation remains useful but is not a functional completion blocker.
