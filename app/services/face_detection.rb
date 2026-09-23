require "json"

class FaceDetection
  IMAGE_MIMES = %w[image/jpeg image/png image/heic image/heif image/avif image/x-adobe-dng].freeze

  def self.process(asset)
    return [] unless IMAGE_MIMES.include?(asset.mime.to_s.downcase)

    faces = SidecarClient.detect_faces(File.binread(asset.path), filename: File.basename(asset.path), mime: asset.mime)
    seen = []
    asset.with_lock do
      faces.each do |result|
        box = result.fetch("box")
        key = FaceCrop.detection_key(box)
        next if seen.include?(key)
        seen << key
        face = asset.faces.find_or_initialize_by(bbox: key)
        old_crop = face.crop_path
        crop = FaceCrop.create(asset: asset, box: box)
        Face.transaction do
          face.crop_path = crop
          face.save!
          FaceEmbed.upsert({ face_id: face.id, model: "insightface", embed: EmbeddingStore.to_blob(result.fetch("embedding")) }, unique_by: :face_id)
          db = ActiveRecord::Base.connection.raw_connection
          db.execute("DELETE FROM vec0_face WHERE rowid = ?", [ face.id ])
          db.execute("INSERT INTO vec0_face(rowid, face_embed) VALUES (?, ?)", [ face.id, EmbeddingStore.to_blob(result.fetch("embedding")) ])
        rescue StandardError
          File.delete(File.join(FaceCrop.crop_root, crop)) if crop && File.exist?(File.join(FaceCrop.crop_root, crop))
          raise
        end
        File.delete(File.join(FaceCrop.crop_root, old_crop)) if old_crop.present? && old_crop != crop
      end
    end
    asset.faces.where(bbox: seen).to_a
  end
end
