---
title: Rails Port Phase 2 — Faces and People
tags:
  - design
  - rails-port
  - phase-2
  - faces
  - people
  - insightface
created: 2026-09-19
---

# Rails Port Phase 2 — Faces and People

## Goal

Add face detection, face embedding storage, clustering, and people review to
the completed Phase 1 Rails application. A successful Phase 2 import produces
zero or more persisted faces and searchable face embeddings without changing
the existing content search or import contract.

## Architecture

The Python sidecar remains the only ML runtime. It performs InsightFace face
detection and face embedding generation, and it performs DBSCAN clustering over
face embeddings. Rails owns all application state: import orchestration,
database writes, Solid Queue jobs, people assignments, review actions, and the
ERB/Turbo UI.

Face crops are stored as JPEG files below `PICS_LIBRARY/.crops`. Rails writes
only generated crop filenames, and the crop controller resolves and serves a
path only after verifying that the resolved path remains below the configured
crop directory.

The existing Phase 1 schema is sufficient. Phase 2 uses `faces`, `face_embeds`,
`vec0_face`, `persons`, `person_aliases`, `person_faces`, `clustering_runs`,
`cluster_suggestions`, and `face_assignments`; no migration is expected.

## Sidecar Contract

Add these endpoints to `sidecar/app.py`:

`POST /v1/detect-faces`

- Request: multipart field `file` containing an image.
- Response: `{ "faces": [{ "box": [x, y, width, height], "embedding": [512 floats] }] }`.
- Coordinates are pixel coordinates in the decoded source image.
- An image with no detected faces returns an empty `faces` array.
- Invalid image data returns HTTP 400; model/runtime failures return HTTP 503.

`POST /v1/cluster-faces`

- Request: `{ "embeddings": [[512 floats], ...], "eps": number, "min_samples": integer }`.
- Response: `{ "labels": [integer, ...] }`, using `-1` for noise.
- The endpoint validates dimensionality and matching lengths before clustering.
- Empty input returns an empty labels array.
- Clustering uses cosine distance and the existing Python DBSCAN behavior.

The sidecar status response reports face capability readiness along with the
existing model status. Stub mode returns deterministic face fixtures for tests;
real mode loads InsightFace lazily and reports unavailable readiness until the
model is usable.

## Import Data Flow

1. `AssetImporter` creates or updates the asset and content thumbnail as in
   Phase 1.
2. For supported image media, `FaceDetection` sends the source image to the
   sidecar and receives boxes plus 512-dimensional embeddings.
3. Each result is normalized and deduplicated against the asset's existing
   faces using a stable detection key derived from the box. Re-importing an
   unchanged file must not create duplicate faces.
4. Rails crops the source image to the returned box, writes a generated JPEG
   below `library/.crops`, and stores the relative crop path on the face row.
5. Rails stores the float32 embedding in `face_embeds` and inserts the same
   vector into `vec0_face`.
6. A detection failure records the asset import failure using the existing job
   contract. A no-face result is a successful import with zero faces. Existing
   content import remains intact when face detection is disabled by the sidecar
   capability flag.

Video assets are excluded from Phase 2 face detection. The implementation must
not attempt to extract video frames or create partial face rows for videos.

## Clustering and Review Flow

`ClusterFacesJob` loads face embeddings that are not assigned to a person,
sends them to `/v1/cluster-faces`, and creates a `clustering_runs` row. Each
non-noise cluster creates one `cluster_suggestions` row with its representative
face and member count. Cluster membership is represented through
`face_assignments` for the run; it does not automatically create or rename a
person.

People review creates a `Person` only when a suggestion is confirmed or a user
explicitly creates a person. Confirmation writes `person_faces` records and
marks the suggestion confirmed. Reject, restore, manual assignment, merge,
and split operations update the suggestion/assignment state transactionally.
All mutating people operations are idempotent for repeated requests.

## HTTP and UI Surface

Add the existing FastAPI-compatible people routes:

- `GET /persons`
- `GET /persons/search?q=...`
- `POST /persons/cluster`
- `PATCH /persons/:id`
- `POST /persons/:id/aliases`
- `DELETE /persons/:id/aliases/:alias_id`
- `POST /persons/:id/faces/:face_id`
- `POST /persons/:id/split`
- `POST /persons/:keep/merge/:remove`
- `POST /persons/suggestions/:id/confirm`
- `POST /persons/suggestions/:id/reject`
- `POST /persons/suggestions/:id/restore`
- `GET /persons/faces/:face_id/crop`

HTML responses render a people index and review queue using Turbo-compatible
forms/links. JSON responses preserve the route contract. The UI displays
cluster suggestions, crop thumbnails, current assignments, aliases, and
actions for confirm/reject/restore, rename, merge, split, and manual assign.

## Error Handling and Security

- Sidecar 400 responses are recorded as a failed face-processing import with a
  useful job error; sidecar 503/network failures are retryable by the job.
- Face rows and crop files are created in one application-level operation; a
  failed database write removes the newly created crop file.
- Crop requests reject missing faces, absolute paths, `..` traversal, symlink
  escapes, and paths outside `PICS_LIBRARY/.crops`.
- Cluster actions use transactions and lock the affected person/suggestion
  records to prevent duplicate assignments from concurrent requests.
- All controller mutations use strong parameters and the existing Rails CSRF
  behavior for HTML requests.

## Testing Approach

- Sidecar unit tests cover stub and real-contract shapes, invalid dimensions,
  empty inputs, no-face images, and deterministic clustering labels.
- Rails service tests cover detection response parsing, crop containment,
  idempotent re-import, face embedding persistence, and video exclusion.
- Job tests cover successful detection, retryable sidecar failure, permanent
  invalid-image failure, clustering progress, and domain job state.
- Controller tests cover every people mutation, JSON responses, HTML render
  paths, authorization-safe parameter handling, and crop traversal rejection.
- The Phase 2 acceptance test imports a fixture with at least two detectable
  faces, verifies crops and `vec0_face` rows, clusters them, confirms a
  suggestion, and verifies the person filter returns the associated asset.

## Out of Scope

Places UI, Apple Photos synchronization, CLI work, deployment changes, and
video face extraction remain deferred to later phases.
