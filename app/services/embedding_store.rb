class EmbeddingStore
  def self.to_blob(vector)
    vector.pack("f*")
  end

  def self.add_content(asset_id:, model:, model_version:, vector:)
    blob = to_blob(vector)
    ContentEmbed.upsert(
      { asset_id: asset_id, model: model, model_version: model_version, embed: blob },
      unique_by: :asset_id,
    )
    db = ActiveRecord::Base.connection.raw_connection
    db.execute("DELETE FROM vec0_content WHERE rowid = ?", [ asset_id ])
    db.execute("INSERT INTO vec0_content(rowid, content_embed) VALUES (?, ?)", [ asset_id, blob ])
  end

  def self.content_knn(vector, limit)
    blob = to_blob(vector)
    rows = ActiveRecord::Base.connection.raw_connection.execute(
      "SELECT rowid, distance FROM vec0_content WHERE content_embed MATCH ? AND k = ?",
      [ blob, limit ],
    )
    rows.map { |row| [ row["rowid"].to_i, row["distance"].to_f ] }
  end
end
