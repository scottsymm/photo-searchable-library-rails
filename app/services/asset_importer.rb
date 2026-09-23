require "digest"

class AssetImporter
  def self.import(path)
    metadata = ExifMetadata.extract(path)
    mime = metadata[:mime]
    thumb = ThumbnailMaker.thumbnail(path, mime)

    gps_lat = metadata[:gps_lat]
    gps_lon = metadata[:gps_lon]
    city = country = nil
    if gps_lat && gps_lon
      geo = SidecarClient.reverse_geocode(lat: gps_lat, lon: gps_lon)
      city = geo["city"]
      country = geo["country"]
    end

    sha256 = Digest::SHA256.file(path).hexdigest
    stored = StoredFile.find_or_initialize_by(sha256: "#{sha256}:thumbnail")
    stored.kind = "thumbnail"
    stored.bytes = thumb
    stored.save!

    source = Source.classify_path(path)
    asset = Asset.find_or_initialize_by(path: File.expand_path(path))
    asset.assign_attributes(
      sha256: sha256,
      size_bytes: File.size(path),
      mime: mime,
      source: source,
      taken_at: metadata[:taken_at],
      gps_lat: gps_lat,
      gps_lon: gps_lon,
      place_city: city,
      place_country: country,
      thumbnail_id: stored.id,
      extra: metadata.to_json,
      deleted: 0,
    )
    asset.save!

    embed = SidecarClient.embed_image(thumb, mime: mime)
    EmbeddingStore.add_content(
      asset_id: asset.id,
      model: embed["model"],
      model_version: embed["version"],
      vector: embed["embed"],
    )
    FaceDetection.process(asset)
    asset.id
  end
end
