class SeedPicsDefaults < ActiveRecord::Migration[8.1]
  def up
    [
      ["apple_photos", "Apple Photos"],
      ["mounted_folder", "Mounted folder"],
      ["uploads", "Uploads"],
    ].each do |kind, display_name|
      execute <<~SQL
        INSERT INTO sources(kind, display_name, status, created_at, updated_at)
        VALUES ('#{kind}', '#{display_name}', 'not_connected', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(kind) DO NOTHING
      SQL
    end

    { "watch_enabled" => "0", "watch_backfill" => "prompt", "watch_initialized" => "0" }.each do |key, value|
      execute <<~SQL
        INSERT INTO settings(key, value, created_at, updated_at)
        VALUES ('#{key}', '#{value}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO NOTHING
      SQL
    end
  end

  def down
    execute "DELETE FROM sources WHERE kind IN ('apple_photos','mounted_folder','uploads')"
    execute "DELETE FROM settings WHERE key IN ('watch_enabled','watch_backfill','watch_initialized')"
  end
end
