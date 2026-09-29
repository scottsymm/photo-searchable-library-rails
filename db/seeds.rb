# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

db = ActiveRecord::Base.connection.raw_connection
{
  "vec0_content" => "content_embed",
  "vec0_face" => "face_embed"
}.each do |table, column|
  exists = db.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [ table ])
  unless exists
    %W[#{table}_info #{table}_chunks #{table}_rowids #{table}_vector_chunks00].each do |backing_table|
      db.execute("DROP TABLE IF EXISTS #{backing_table}")
    end
  end
  db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS #{table} USING vec0(#{column} float[512])")
end

[
  [ "apple_photos", "Apple Photos" ],
  [ "mounted_folder", "Mounted folder" ],
  [ "uploads", "Uploads" ]
].each do |kind, display_name|
  Source.find_or_create_by!(kind: kind) do |source|
    source.display_name = display_name
    source.status = "not_connected"
  end
end

{
  "watch_enabled" => "0",
  "watch_backfill" => "prompt",
  "watch_initialized" => "0"
}.each do |key, value|
  Setting.find_or_create_by!(key: key) { |setting| setting.value = value }
end
