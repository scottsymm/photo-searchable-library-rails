CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "schema_meta" ("key" varchar NOT NULL, "value" varchar NOT NULL);
CREATE UNIQUE INDEX "index_schema_meta_on_key" ON "schema_meta" ("key");
CREATE TABLE "sources" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "display_name" varchar NOT NULL, "status" varchar DEFAULT 'not_connected' NOT NULL, "authorization_state" varchar, "bridge_status" varchar DEFAULT 'offline' NOT NULL, "bridge_last_seen_at" datetime(6), "last_sync_at" datetime(6), "last_error" varchar, "asset_count" integer DEFAULT 0 NOT NULL, "imported_count" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_sources_on_kind" ON "sources" ("kind");
CREATE TABLE "assets" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "path" varchar NOT NULL, "sha256" varchar NOT NULL, "size_bytes" integer DEFAULT 0 NOT NULL, "mime" varchar NOT NULL, "source_id" integer, "source_asset_id" varchar, "original_filename" varchar, "taken_at" datetime(6), "gps_lat" float, "gps_lon" float, "place_city" varchar, "place_country" varchar, "thumbnail_id" integer, "stripped" integer DEFAULT 0 NOT NULL, "deleted" integer DEFAULT 0 NOT NULL, "skipped" integer DEFAULT 0 NOT NULL, "extra" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7487898106"
FOREIGN KEY ("source_id")
  REFERENCES "sources" ("id")
);
CREATE UNIQUE INDEX "index_assets_on_path" ON "assets" ("path");
CREATE INDEX "index_assets_on_taken_at" ON "assets" ("taken_at");
CREATE INDEX "index_assets_on_place_city_and_place_country" ON "assets" ("place_city", "place_country");
CREATE UNIQUE INDEX "index_assets_on_source_id_and_source_asset_id" ON "assets" ("source_id", "source_asset_id");
CREATE TABLE "files" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "sha256" varchar NOT NULL, "kind" varchar NOT NULL, "bytes" blob, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_files_on_sha256" ON "files" ("sha256");
CREATE TABLE "source_syncs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "source_id" integer NOT NULL, "status" varchar DEFAULT 'queued' NOT NULL, "limit_count" integer DEFAULT 25 NOT NULL, "full_sync" integer DEFAULT 0 NOT NULL, "started_at" datetime(6), "completed_at" datetime(6), "imported_count" integer DEFAULT 0 NOT NULL, "failed_count" integer DEFAULT 0 NOT NULL, "error" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_0d2c1041c9"
FOREIGN KEY ("source_id")
  REFERENCES "sources" ("id")
);
CREATE TABLE "persons" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar DEFAULT '' NOT NULL, "prototype_face_id" integer, "status" varchar DEFAULT 'new' NOT NULL);
CREATE TABLE "person_aliases" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "person_id" integer NOT NULL, "alias" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_a4cf4f8aaa"
FOREIGN KEY ("person_id")
  REFERENCES "persons" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_person_aliases_on_person_id_and_alias" ON "person_aliases" ("person_id", "alias");
CREATE TABLE "faces" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "asset_id" integer NOT NULL, "crop_path" varchar, "bbox" varchar NOT NULL, "cluster_id" integer, CONSTRAINT "fk_rails_dea876eb87"
FOREIGN KEY ("asset_id")
  REFERENCES "assets" ("id")
 ON DELETE CASCADE);
CREATE TABLE "content_embeds" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "asset_id" integer NOT NULL, "model" varchar NOT NULL, "model_version" varchar NOT NULL, "embed" blob NOT NULL, CONSTRAINT "fk_rails_719131f5ae"
FOREIGN KEY ("asset_id")
  REFERENCES "assets" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_content_embeds_on_asset_id" ON "content_embeds" ("asset_id");
CREATE TABLE "face_embeds" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "face_id" integer NOT NULL, "model" varchar NOT NULL, "embed" blob NOT NULL, CONSTRAINT "fk_rails_015a1239ce"
FOREIGN KEY ("face_id")
  REFERENCES "faces" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_face_embeds_on_face_id" ON "face_embeds" ("face_id");
CREATE TABLE "clustering_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "model" varchar NOT NULL, "model_version" varchar NOT NULL, "algorithm" varchar NOT NULL, "metric" varchar NOT NULL, "eps" float NOT NULL, "min_samples" integer NOT NULL, "status" varchar DEFAULT 'running' NOT NULL, "completed_at" datetime(6), "error" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "cluster_suggestions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "run_id" integer NOT NULL, "cluster_key" integer NOT NULL, "representative_face_id" integer, "face_count" integer NOT NULL, "confidence" varchar DEFAULT 'candidate' NOT NULL, "status" varchar DEFAULT 'unreviewed' NOT NULL, "person_id" integer, CONSTRAINT "fk_rails_1e778bc24a"
FOREIGN KEY ("run_id")
  REFERENCES "clustering_runs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_cluster_suggestions_on_run_id_and_cluster_key" ON "cluster_suggestions" ("run_id", "cluster_key");
CREATE TABLE "face_assignments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "run_id" integer NOT NULL, "face_id" integer NOT NULL, "suggestion_id" integer, "distance" float, "status" varchar DEFAULT 'suggested' NOT NULL, CONSTRAINT "fk_rails_09f516d734"
FOREIGN KEY ("run_id")
  REFERENCES "clustering_runs" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_face_assignments_on_run_id_and_face_id" ON "face_assignments" ("run_id", "face_id");
CREATE TABLE "person_faces" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "person_id" integer NOT NULL, "face_id" integer NOT NULL, "source" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_90ff722d41"
FOREIGN KEY ("person_id")
  REFERENCES "persons" ("id")
 ON DELETE CASCADE, CONSTRAINT "fk_rails_3a530c67d1"
FOREIGN KEY ("face_id")
  REFERENCES "faces" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_person_faces_on_person_id_and_face_id" ON "person_faces" ("person_id", "face_id");
CREATE INDEX "index_person_faces_on_face_id" ON "person_faces" ("face_id");
CREATE TABLE "settings" ("key" varchar NOT NULL, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_settings_on_key" ON "settings" ("key");
CREATE TABLE "tags" ("asset_id" integer NOT NULL, "tag" varchar NOT NULL, "source" varchar DEFAULT 'manual' NOT NULL, CONSTRAINT "fk_rails_d17b006589"
FOREIGN KEY ("asset_id")
  REFERENCES "assets" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_tags_on_asset_id_and_tag" ON "tags" ("asset_id", "tag");
CREATE TABLE "jobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "status" varchar DEFAULT 'queued' NOT NULL, "progress" float DEFAULT 0.0 NOT NULL, "error" varchar, "params" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_jobs_on_status" ON "jobs" ("status");
CREATE TABLE "vec0_content_info" (key text primary key, value any);
CREATE TABLE "vec0_content_chunks"(chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,size INTEGER NOT NULL,validity BLOB NOT NULL,rowids BLOB NOT NULL);
CREATE TABLE "vec0_content_rowids"(rowid INTEGER PRIMARY KEY AUTOINCREMENT,id,chunk_id INTEGER,chunk_offset INTEGER);
CREATE TABLE "vec0_content_vector_chunks00"(rowid PRIMARY KEY,vectors BLOB NOT NULL);
CREATE TABLE "vec0_face_info" (key text primary key, value any);
CREATE TABLE "vec0_face_chunks"(chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,size INTEGER NOT NULL,validity BLOB NOT NULL,rowids BLOB NOT NULL);
CREATE TABLE "vec0_face_rowids"(rowid INTEGER PRIMARY KEY AUTOINCREMENT,id,chunk_id INTEGER,chunk_offset INTEGER);
CREATE TABLE "vec0_face_vector_chunks00"(rowid PRIMARY KEY,vectors BLOB NOT NULL);
CREATE UNIQUE INDEX "index_source_syncs_on_source_id_active" ON "source_syncs" ("source_id") WHERE status IN ('queued', 'running');
INSERT INTO "schema_migrations" (version) VALUES
('20260926000000');
