CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "solid_queue_jobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "queue_name" varchar NOT NULL, "class_name" varchar NOT NULL, "arguments" text, "priority" integer DEFAULT 0 NOT NULL, "active_job_id" varchar, "scheduled_at" datetime(6), "finished_at" datetime(6), "concurrency_key" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "batch_id" bigint);
CREATE INDEX "index_solid_queue_jobs_on_active_job_id" ON "solid_queue_jobs" ("active_job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_jobs_on_batch_id" ON "solid_queue_jobs" ("batch_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_jobs_on_class_name" ON "solid_queue_jobs" ("class_name") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_jobs_on_finished_at" ON "solid_queue_jobs" ("finished_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_jobs_for_filtering" ON "solid_queue_jobs" ("queue_name", "finished_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_jobs_for_alerting" ON "solid_queue_jobs" ("scheduled_at", "finished_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_pauses" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "queue_name" varchar NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_solid_queue_pauses_on_queue_name" ON "solid_queue_pauses" ("queue_name") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_processes" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "last_heartbeat_at" datetime(6) NOT NULL, "supervisor_id" bigint, "pid" integer NOT NULL, "hostname" varchar, "metadata" text, "created_at" datetime(6) NOT NULL, "name" varchar NOT NULL);
CREATE INDEX "index_solid_queue_processes_on_last_heartbeat_at" ON "solid_queue_processes" ("last_heartbeat_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE UNIQUE INDEX "index_solid_queue_processes_on_name_and_supervisor_id" ON "solid_queue_processes" ("name", "supervisor_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_processes_on_supervisor_id" ON "solid_queue_processes" ("supervisor_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_recurring_tasks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "schedule" varchar NOT NULL, "command" varchar(2048), "class_name" varchar, "arguments" text, "queue_name" varchar, "priority" integer DEFAULT 0, "static" boolean DEFAULT TRUE NOT NULL, "description" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_solid_queue_recurring_tasks_on_key" ON "solid_queue_recurring_tasks" ("key") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_recurring_tasks_on_static" ON "solid_queue_recurring_tasks" ("static") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_semaphores" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "value" integer DEFAULT 1 NOT NULL, "expires_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_solid_queue_semaphores_on_expires_at" ON "solid_queue_semaphores" ("expires_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_semaphores_on_key_and_value" ON "solid_queue_semaphores" ("key", "value") /*application='PhotoSearchableLibraryRails'*/;
CREATE UNIQUE INDEX "index_solid_queue_semaphores_on_key" ON "solid_queue_semaphores" ("key") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_batches" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "active_job_batch_id" varchar, "description" varchar, "on_finish" text, "on_success" text, "on_failure" text, "metadata" text, "total_jobs" integer DEFAULT 0 NOT NULL, "completed_jobs" integer DEFAULT 0 NOT NULL, "failed_jobs" integer DEFAULT 0 NOT NULL, "enqueued_at" datetime(6), "finished_at" datetime(6), "failed_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_solid_queue_batches_on_active_job_batch_id" ON "solid_queue_batches" ("active_job_batch_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_batches_on_finished_at" ON "solid_queue_batches" ("finished_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_batch_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "batch_id" bigint NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7c5e073422"
FOREIGN KEY ("batch_id")
  REFERENCES "solid_queue_batches" ("id")
 ON DELETE CASCADE, CONSTRAINT "fk_rails_bc9f981155"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_solid_queue_batch_executions_on_job_id" ON "solid_queue_batch_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_batch_executions_on_batch_id" ON "solid_queue_batch_executions" ("batch_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_blocked_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "queue_name" varchar NOT NULL, "priority" integer DEFAULT 0 NOT NULL, "concurrency_key" varchar NOT NULL, "expires_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_4cd34e2228"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE INDEX "index_solid_queue_blocked_executions_for_release" ON "solid_queue_blocked_executions" ("concurrency_key", "priority", "job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_blocked_executions_for_maintenance" ON "solid_queue_blocked_executions" ("expires_at", "concurrency_key") /*application='PhotoSearchableLibraryRails'*/;
CREATE UNIQUE INDEX "index_solid_queue_blocked_executions_on_job_id" ON "solid_queue_blocked_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_claimed_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "process_id" bigint, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_9cfe4d4944"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_solid_queue_claimed_executions_on_job_id" ON "solid_queue_claimed_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_claimed_executions_on_process_id_and_job_id" ON "solid_queue_claimed_executions" ("process_id", "job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_failed_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "error" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_39bbc7a631"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_solid_queue_failed_executions_on_job_id" ON "solid_queue_failed_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_ready_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "queue_name" varchar NOT NULL, "priority" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_81fcbd66af"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_solid_queue_ready_executions_on_job_id" ON "solid_queue_ready_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_poll_all" ON "solid_queue_ready_executions" ("priority", "job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_poll_by_queue" ON "solid_queue_ready_executions" ("queue_name", "priority", "job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_recurring_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "task_key" varchar NOT NULL, "run_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_318a5533ed"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_solid_queue_recurring_executions_on_job_id" ON "solid_queue_recurring_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE UNIQUE INDEX "index_solid_queue_recurring_executions_on_task_key_and_run_at" ON "solid_queue_recurring_executions" ("task_key", "run_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "solid_queue_scheduled_executions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "job_id" bigint NOT NULL, "queue_name" varchar NOT NULL, "priority" integer DEFAULT 0 NOT NULL, "scheduled_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c4316f352d"
FOREIGN KEY ("job_id")
  REFERENCES "solid_queue_jobs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_solid_queue_scheduled_executions_on_job_id" ON "solid_queue_scheduled_executions" ("job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_solid_queue_dispatch_all" ON "solid_queue_scheduled_executions" ("scheduled_at", "priority", "job_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "schema_meta" ("key" varchar NOT NULL, "value" varchar NOT NULL);
CREATE UNIQUE INDEX "index_schema_meta_on_key" ON "schema_meta" ("key") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "sources" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "display_name" varchar NOT NULL, "status" varchar DEFAULT 'not_connected' NOT NULL, "authorization_state" varchar, "bridge_status" varchar DEFAULT 'offline' NOT NULL, "bridge_last_seen_at" datetime(6), "last_sync_at" datetime(6), "last_error" varchar, "asset_count" integer DEFAULT 0 NOT NULL, "imported_count" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_sources_on_kind" ON "sources" ("kind") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "assets" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "path" varchar NOT NULL, "sha256" varchar NOT NULL, "size_bytes" integer DEFAULT 0 NOT NULL, "mime" varchar NOT NULL, "source_id" integer, "source_asset_id" varchar, "original_filename" varchar, "taken_at" datetime(6), "gps_lat" float, "gps_lon" float, "place_city" varchar, "place_country" varchar, "thumbnail_id" integer, "stripped" integer DEFAULT 0 NOT NULL, "deleted" integer DEFAULT 0 NOT NULL, "skipped" integer DEFAULT 0 NOT NULL, "extra" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7487898106"
FOREIGN KEY ("source_id")
  REFERENCES "sources" ("id")
);
CREATE UNIQUE INDEX "index_assets_on_path" ON "assets" ("path") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_assets_on_taken_at" ON "assets" ("taken_at") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_assets_on_place_city_and_place_country" ON "assets" ("place_city", "place_country") /*application='PhotoSearchableLibraryRails'*/;
CREATE UNIQUE INDEX "index_assets_on_source_id_and_source_asset_id" ON "assets" ("source_id", "source_asset_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "files" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "sha256" varchar NOT NULL, "kind" varchar NOT NULL, "bytes" blob, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_files_on_sha256" ON "files" ("sha256") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "source_syncs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "source_id" integer NOT NULL, "status" varchar DEFAULT 'queued' NOT NULL, "limit_count" integer DEFAULT 25 NOT NULL, "full_sync" integer DEFAULT 0 NOT NULL, "started_at" datetime(6), "completed_at" datetime(6), "imported_count" integer DEFAULT 0 NOT NULL, "failed_count" integer DEFAULT 0 NOT NULL, "error" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_0d2c1041c9"
FOREIGN KEY ("source_id")
  REFERENCES "sources" ("id")
);
CREATE TABLE IF NOT EXISTS "persons" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar DEFAULT '' NOT NULL, "prototype_face_id" integer, "status" varchar DEFAULT 'new' NOT NULL);
CREATE TABLE IF NOT EXISTS "person_aliases" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "person_id" integer NOT NULL, "alias" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_a4cf4f8aaa"
FOREIGN KEY ("person_id")
  REFERENCES "persons" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_person_aliases_on_person_id_and_alias" ON "person_aliases" ("person_id", "alias") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "faces" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "asset_id" integer NOT NULL, "crop_path" varchar, "bbox" varchar NOT NULL, "cluster_id" integer, CONSTRAINT "fk_rails_dea876eb87"
FOREIGN KEY ("asset_id")
  REFERENCES "assets" ("id")
 ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS "content_embeds" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "asset_id" integer NOT NULL, "model" varchar NOT NULL, "model_version" varchar NOT NULL, "embed" blob NOT NULL, CONSTRAINT "fk_rails_719131f5ae"
FOREIGN KEY ("asset_id")
  REFERENCES "assets" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_content_embeds_on_asset_id" ON "content_embeds" ("asset_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "face_embeds" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "face_id" integer NOT NULL, "model" varchar NOT NULL, "embed" blob NOT NULL, CONSTRAINT "fk_rails_015a1239ce"
FOREIGN KEY ("face_id")
  REFERENCES "faces" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_face_embeds_on_face_id" ON "face_embeds" ("face_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "clustering_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "model" varchar NOT NULL, "model_version" varchar NOT NULL, "algorithm" varchar NOT NULL, "metric" varchar NOT NULL, "eps" float NOT NULL, "min_samples" integer NOT NULL, "status" varchar DEFAULT 'running' NOT NULL, "completed_at" datetime(6), "error" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "cluster_suggestions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "run_id" integer NOT NULL, "cluster_key" integer NOT NULL, "representative_face_id" integer, "face_count" integer NOT NULL, "confidence" varchar DEFAULT 'candidate' NOT NULL, "status" varchar DEFAULT 'unreviewed' NOT NULL, "person_id" integer, CONSTRAINT "fk_rails_1e778bc24a"
FOREIGN KEY ("run_id")
  REFERENCES "clustering_runs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_cluster_suggestions_on_run_id_and_cluster_key" ON "cluster_suggestions" ("run_id", "cluster_key") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "face_assignments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "run_id" integer NOT NULL, "face_id" integer NOT NULL, "suggestion_id" integer, "distance" float, "status" varchar DEFAULT 'suggested' NOT NULL, CONSTRAINT "fk_rails_09f516d734"
FOREIGN KEY ("run_id")
  REFERENCES "clustering_runs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_face_assignments_on_run_id_and_face_id" ON "face_assignments" ("run_id", "face_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "person_faces" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "person_id" integer NOT NULL, "face_id" integer NOT NULL, "source" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_90ff722d41"
FOREIGN KEY ("person_id")
  REFERENCES "persons" ("id")
 ON DELETE CASCADE, CONSTRAINT "fk_rails_3a530c67d1"
FOREIGN KEY ("face_id")
  REFERENCES "faces" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_person_faces_on_person_id_and_face_id" ON "person_faces" ("person_id", "face_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE INDEX "index_person_faces_on_face_id" ON "person_faces" ("face_id") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "settings" ("key" varchar NOT NULL, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_settings_on_key" ON "settings" ("key") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "tags" ("asset_id" integer NOT NULL, "tag" varchar NOT NULL, "source" varchar DEFAULT 'manual' NOT NULL, CONSTRAINT "fk_rails_d17b006589"
FOREIGN KEY ("asset_id")
  REFERENCES "assets" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_tags_on_asset_id_and_tag" ON "tags" ("asset_id", "tag") /*application='PhotoSearchableLibraryRails'*/;
CREATE TABLE IF NOT EXISTS "jobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "status" varchar DEFAULT 'queued' NOT NULL, "progress" float DEFAULT 0.0 NOT NULL, "error" varchar, "params" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_jobs_on_status" ON "jobs" ("status") /*application='PhotoSearchableLibraryRails'*/;
CREATE VIRTUAL TABLE vec0_content USING vec0(content_embed float[512]);
CREATE TABLE IF NOT EXISTS "vec0_content_info" (key text primary key, value any);
CREATE TABLE IF NOT EXISTS "vec0_content_chunks"(chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,size INTEGER NOT NULL,validity BLOB NOT NULL,rowids BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS "vec0_content_rowids"(rowid INTEGER PRIMARY KEY AUTOINCREMENT,id,chunk_id INTEGER,chunk_offset INTEGER);
CREATE TABLE IF NOT EXISTS "vec0_content_vector_chunks00"(rowid PRIMARY KEY,vectors BLOB NOT NULL);
CREATE VIRTUAL TABLE vec0_face USING vec0(face_embed float[512]);
CREATE TABLE IF NOT EXISTS "vec0_face_info" (key text primary key, value any);
CREATE TABLE IF NOT EXISTS "vec0_face_chunks"(chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,size INTEGER NOT NULL,validity BLOB NOT NULL,rowids BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS "vec0_face_rowids"(rowid INTEGER PRIMARY KEY AUTOINCREMENT,id,chunk_id INTEGER,chunk_offset INTEGER);
CREATE TABLE IF NOT EXISTS "vec0_face_vector_chunks00"(rowid PRIMARY KEY,vectors BLOB NOT NULL);
INSERT INTO "schema_migrations" (version) VALUES
('20260918221755'),
('20260918221705'),
('20260918221603'),
('1');

