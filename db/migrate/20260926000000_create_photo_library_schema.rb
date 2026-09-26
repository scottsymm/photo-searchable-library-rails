class CreatePhotoLibrarySchema < ActiveRecord::Migration[8.1]
  def change
    create_table :schema_meta, id: false do |t|
      t.string :key, null: false
      t.string :value, null: false
    end
    add_index :schema_meta, :key, unique: true

    create_table :sources do |t|
      t.string :kind, null: false
      t.string :display_name, null: false
      t.string :status, null: false, default: "not_connected"
      t.string :authorization_state
      t.string :bridge_status, null: false, default: "offline"
      t.datetime :bridge_last_seen_at
      t.datetime :last_sync_at
      t.string :last_error
      t.integer :asset_count, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.timestamps
    end
    add_index :sources, :kind, unique: true

    create_table :assets do |t|
      t.string :path, null: false
      t.string :sha256, null: false
      t.integer :size_bytes, null: false, default: 0
      t.string :mime, null: false
      t.integer :source_id
      t.string :source_asset_id
      t.string :original_filename
      t.datetime :taken_at
      t.float :gps_lat
      t.float :gps_lon
      t.string :place_city
      t.string :place_country
      t.integer :thumbnail_id
      t.integer :stripped, null: false, default: 0
      t.integer :deleted, null: false, default: 0
      t.integer :skipped, null: false, default: 0
      t.text :extra
      t.timestamps
    end
    add_index :assets, :path, unique: true
    add_index :assets, :taken_at
    add_index :assets, [ :place_city, :place_country ]
    add_index :assets, [ :source_id, :source_asset_id ], unique: true
    add_foreign_key :assets, :sources

    create_table :files do |t|
      t.string :sha256, null: false
      t.string :kind, null: false
      t.binary :bytes
      t.timestamps
    end
    add_index :files, :sha256, unique: true

    create_table :source_syncs do |t|
      t.integer :source_id, null: false
      t.string :status, null: false, default: "queued"
      t.integer :limit_count, null: false, default: 25
      t.integer :full_sync, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :imported_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.string :error
      t.timestamps
    end
    add_foreign_key :source_syncs, :sources

    create_table :persons do |t|
      t.string :name, null: false, default: ""
      t.integer :prototype_face_id
      t.string :status, null: false, default: "new"
    end

    create_table :person_aliases do |t|
      t.integer :person_id, null: false
      t.string :alias, null: false
      t.timestamps
    end
    add_index :person_aliases, [ :person_id, :alias ], unique: true
    add_foreign_key :person_aliases, :persons, on_delete: :cascade

    create_table :faces do |t|
      t.integer :asset_id, null: false
      t.string :crop_path
      t.string :bbox, null: false
      t.integer :cluster_id
    end
    add_foreign_key :faces, :assets, on_delete: :cascade

    create_table :content_embeds do |t|
      t.integer :asset_id, null: false
      t.string :model, null: false
      t.string :model_version, null: false
      t.binary :embed, null: false
    end
    add_index :content_embeds, :asset_id, unique: true
    add_foreign_key :content_embeds, :assets, on_delete: :cascade

    create_table :face_embeds do |t|
      t.integer :face_id, null: false
      t.string :model, null: false
      t.binary :embed, null: false
    end
    add_index :face_embeds, :face_id, unique: true
    add_foreign_key :face_embeds, :faces, on_delete: :cascade

    create_table :clustering_runs do |t|
      t.string :model, null: false
      t.string :model_version, null: false
      t.string :algorithm, null: false
      t.string :metric, null: false
      t.float :eps, null: false
      t.integer :min_samples, null: false
      t.string :status, null: false, default: "running"
      t.datetime :completed_at
      t.string :error
      t.timestamps
    end

    create_table :cluster_suggestions do |t|
      t.integer :run_id, null: false
      t.integer :cluster_key, null: false
      t.integer :representative_face_id
      t.integer :face_count, null: false
      t.string :confidence, null: false, default: "candidate"
      t.string :status, null: false, default: "unreviewed"
      t.integer :person_id
    end
    add_index :cluster_suggestions, [ :run_id, :cluster_key ], unique: true
    add_foreign_key :cluster_suggestions, :clustering_runs, column: :run_id, on_delete: :cascade

    create_table :face_assignments do |t|
      t.integer :run_id, null: false
      t.integer :face_id, null: false
      t.integer :suggestion_id
      t.float :distance
      t.string :status, null: false, default: "suggested"
    end
    add_index :face_assignments, [ :run_id, :face_id ], unique: true
    add_foreign_key :face_assignments, :clustering_runs, column: :run_id, on_delete: :cascade

    create_table :person_faces do |t|
      t.integer :person_id, null: false
      t.integer :face_id, null: false
      t.string :source, null: false
      t.timestamps
    end
    add_index :person_faces, [ :person_id, :face_id ], unique: true
    add_index :person_faces, :face_id
    add_foreign_key :person_faces, :persons, on_delete: :cascade
    add_foreign_key :person_faces, :faces, on_delete: :cascade

    create_table :settings, id: false do |t|
      t.string :key, null: false
      t.string :value
      t.timestamps
    end
    add_index :settings, :key, unique: true

    create_table :tags, id: false do |t|
      t.integer :asset_id, null: false
      t.string :tag, null: false
      t.string :source, null: false, default: "manual"
    end
    add_index :tags, [ :asset_id, :tag ], unique: true
    add_foreign_key :tags, :assets, on_delete: :cascade

    create_table :jobs do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "queued"
      t.float :progress, null: false, default: 0
      t.string :error
      t.text :params
      t.timestamps
    end
    add_index :jobs, :status

    ensure_virtual_table("vec0_content", "content_embed")
    ensure_virtual_table("vec0_face", "face_embed")

    seed_defaults

    add_index :source_syncs, :source_id,
      unique: true,
      where: "status IN ('queued', 'running')",
      name: "index_source_syncs_on_source_id_active"
  end

  private

  def ensure_virtual_table(name, column)
    execute "CREATE VIRTUAL TABLE IF NOT EXISTS #{name} USING vec0(#{column} float[512])"
  end

  def seed_defaults
    [
      [ "apple_photos", "Apple Photos" ],
      [ "mounted_folder", "Mounted folder" ],
      [ "uploads", "Uploads" ]
    ].each do |kind, display_name|
      execute <<~SQL
        INSERT INTO sources(kind, display_name, status, created_at, updated_at)
        VALUES (#{connection.quote(kind)}, #{connection.quote(display_name)}, 'not_connected', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(kind) DO NOTHING
      SQL
    end

    { "watch_enabled" => "0", "watch_backfill" => "prompt", "watch_initialized" => "0" }.each do |key, value|
      execute <<~SQL
        INSERT INTO settings(key, value, created_at, updated_at)
        VALUES (#{connection.quote(key)}, #{connection.quote(value)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO NOTHING
      SQL
    end
  end
end
