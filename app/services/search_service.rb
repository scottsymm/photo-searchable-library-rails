require "set"

class SearchService
  def self.search(q: nil, who: nil, place: nil, before: nil, after: nil, tag: nil, limit: 50)
    limit = [[limit, 1].max, 200].min
    allowed = filter_ids(who: who, place: place, before: before, after: after, tag: tag)

    if q.present?
      resp = SidecarClient.embed_text(q)
      ranked = EmbeddingStore.content_knn(resp["results"].first, limit * 4)
      ranked.filter_map { |asset_id, distance| asset_result(asset_id, distance) if allowed.include?(asset_id) }.first(limit)
    else
      Asset.not_deleted.where(id: allowed)
           .order(Arel.sql("taken_at DESC, id DESC"))
           .limit(limit * 4)
           .map { |asset| asset_result(asset.id) }
           .first(limit)
    end
  end

  def self.asset_result(asset_id, distance = nil)
    asset = Asset.not_deleted.find_by(id: asset_id)
    return nil if asset.nil?
    result = {
      id: asset.id,
      path: asset.path,
      mime: asset.mime,
      taken_at: asset.taken_at&.iso8601,
      place_city: asset.place_city,
      place_country: asset.place_country,
      thumbnail_id: asset.thumbnail_id,
      thumbnail_url: asset.thumbnail_url,
    }
    result[:distance] = distance if distance
    result
  end

  def self.filter_ids(who: nil, place: nil, before: nil, after: nil, tag: nil)
    sql = "SELECT id FROM assets WHERE deleted = 0"
    params = []

    if place.present?
      like = "%#{escape_like(place)}%"
      sql += " AND (place_city LIKE ? ESCAPE '\\' OR place_country LIKE ? ESCAPE '\\')"
      params += [like, like]
    end
    if before.present?
      sql += " AND taken_at IS NOT NULL AND taken_at <= ?"
      params << before
    end
    if after.present?
      sql += " AND taken_at IS NOT NULL AND taken_at >= ?"
      params << after
    end
    if tag.present?
      sql += " AND id IN (SELECT asset_id FROM tags WHERE tag = ?)"
      params << tag
    end
    if who.present?
      like = "%#{escape_like(who)}%"
      sql += <<~SQL
        AND id IN (
          SELECT faces.asset_id FROM faces
          JOIN person_faces ON person_faces.face_id = faces.id
          JOIN persons ON persons.id = person_faces.person_id
          LEFT JOIN person_aliases ON person_aliases.person_id = persons.id
          WHERE persons.name LIKE ? COLLATE NOCASE ESCAPE '\\'
             OR person_aliases.alias LIKE ? COLLATE NOCASE ESCAPE '\\'
        )
      SQL
      params += [like, like]
    end

    rows = ActiveRecord::Base.connection.raw_connection.execute(sql, params)
    rows.map { |row| row["id"].to_i }.to_set
  end

  def self.escape_like(value)
    value.to_s.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
  end
end
