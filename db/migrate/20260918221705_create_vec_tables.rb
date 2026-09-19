class CreateVecTables < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE VIRTUAL TABLE IF NOT EXISTS vec0_content USING vec0(content_embed float[512])"
    execute "CREATE VIRTUAL TABLE IF NOT EXISTS vec0_face USING vec0(face_embed float[512])"
  end

  def down
    execute "DROP TABLE IF EXISTS vec0_content"
    execute "DROP TABLE IF EXISTS vec0_face"
  end
end
