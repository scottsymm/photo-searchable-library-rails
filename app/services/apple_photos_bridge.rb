require "digest"
require "json"
require "securerandom"

class ApplePhotosBridge
  def self.source
    Source.find_by!(kind: "apple_photos")
  end

  def self.library_root
    Pathname.new(PICS_LIBRARY)
  end

  def self.sync_request(limit: 25, full: false)
    src = source
    recover_stale!(src)
    active = src.source_syncs.where(status: %w[queued running]).order(id: :desc).first
    return { sync: active, already_active: true } if active

    sync = src.source_syncs.create!(limit_count: limit.clamp(1, 500), full_sync: full ? 1 : 0)
    { sync: sync, already_active: false }
  rescue ActiveRecord::RecordNotUnique
    active = src.source_syncs.where(status: %w[queued running]).order(id: :desc).first
    raise if active.nil?

    { sync: active, already_active: true }
  end

  def self.sync_status
    src = source
    recover_stale!(src)
    { sync: src.source_syncs.order(id: :desc).first }
  end

  def self.claim
    src = source
    recover_stale!(src)
    loop do
      sync = src.source_syncs.where(status: "queued").order(:id).first
      return { sync: nil } if sync.nil?

      started_at = Time.current
      claimed = src.source_syncs.where(id: sync.id, status: "queued").update_all(
        status: "running", started_at: started_at, updated_at: started_at
      )
      return { sync: sync.reload } if claimed == 1
    end
  end

  def self.complete(sync_id, imported_count: 0, failed_count: 0, error: nil)
    sync = SourceSync.find(sync_id)
    imported_count = imported_count.to_i
    failed_count = failed_count.to_i
    status = if error.present?
               imported_count.positive? ? "partial" : "error"
    else
               "done"
    end
    sync.update!(
      status: status,
      completed_at: Time.current,
      imported_count: imported_count,
      failed_count: failed_count,
      error: error
    )
    { sync: sync }
  end

  def self.recover_stale!(src)
    cutoff = Time.current - PICS_SOURCE_SYNC_LEASE_SECONDS
    src.source_syncs.where(status: "running").where("started_at < ?", cutoff).update_all(
      status: "error", error: "bridge lease expired", completed_at: Time.current
    )
  end

  def self.heartbeat(authorization_state:, asset_count:)
    src = source
    bridge_status = if %w[denied restricted notDetermined].include?(authorization_state.to_s)
                      "authorization_required"
    elsif asset_count.to_i.zero?
                      "inventory_pending"
    else
                      "connected"
    end
    src.update!(
      bridge_status: bridge_status,
      bridge_last_seen_at: Time.current,
      authorization_state: authorization_state,
      asset_count: asset_count.to_i
    )
    { source: source_with_bridge_status }
  end

  def self.source_with_bridge_status
    src = source
    if src.bridge_last_seen_at.nil? || (Time.current - src.bridge_last_seen_at) > PICS_BRIDGE_LEASE_SECONDS
      src.bridge_status = "offline"
    end
    src
  end

  def self.known(source_asset_ids)
    ids = Array(source_asset_ids).first(500)
    found = source.assets.not_deleted.where(source_asset_id: ids).pluck(:source_asset_id)
    { source_asset_ids: found }
  end

  def self.ingest(file:, source_asset_id:, original_filename: nil, media_type: nil, taken_at: nil, authorization_state: nil, asset_count: nil)
    suffix = File.extname(original_filename.presence || file.original_filename.to_s).downcase
    raise ActionController::BadRequest, "unsupported file type" unless MEDIA_SUFFIXES.include?(suffix)
    raise ActionController::BadRequest, "file is too large" if file.size > PICS_MAX_UPLOAD_BYTES

    src = source
    existing = src.assets.not_deleted.find_by(source_asset_id: source_asset_id)
    if existing && File.file?(existing.path)
      mark_connected!(src, authorization_state, asset_count)
      if existing.content_embed.present? || active_import_for?(existing.path)
        return { status: "duplicate", duplicate: true, asset_id: existing.id, source_asset_id: source_asset_id }
      end
      job = queue_import(existing.path)
      return { status: "queued", duplicate: true, retried: true, asset_id: existing.id, job_id: job.id, source_asset_id: source_asset_id, path: existing.path }
    end

    destination = library_root.join("apple-photos", "#{SecureRandom.hex}#{suffix}")
    destination.dirname.mkpath
    file.tempfile.rewind
    File.open(destination, "wb") { |output| IO.copy_stream(file.tempfile, output) }

    asset = src.assets.find_or_initialize_by(source_asset_id: source_asset_id)
    asset.assign_attributes(
      original_filename: original_filename.presence || file.original_filename,
      path: destination.to_s,
      sha256: Digest::SHA256.file(destination).hexdigest,
      size_bytes: File.size(destination),
      mime: file.content_type.presence || "application/octet-stream",
      taken_at: taken_at,
      deleted: 0
    )
    asset.save!
    job = queue_import(destination.to_s)
    mark_connected!(src, authorization_state, asset_count)
    { status: "queued", duplicate: false, asset_id: asset.id, job_id: job.id, source_asset_id: source_asset_id, path: destination.to_s }
  end

  def self.mark_connected!(src, authorization_state, asset_count)
    src.update!(
      status: "connected",
      authorization_state: authorization_state,
      asset_count: asset_count.nil? ? src.asset_count : asset_count.to_i,
      last_error: nil,
      last_sync_at: Time.current
    )
  end

  def self.queue_import(path)
    job = Job.create!(kind: "import", params: { paths: [ path ] }.to_json)
    ImportJob.perform_later(job_id: job.id, path: path, index: 0, total: 1)
    job
  end

  def self.active_import_for?(path)
    Job.where(kind: "import", status: %w[queued working]).find_each do |job|
      return true if JSON.parse(job.params || "{}").dig("paths").to_a.include?(path)
    end
    false
  end

  def self.sync_json(sync)
    return nil if sync.nil?

    {
      id: sync.id,
      source_id: sync.source_id,
      status: sync.status,
      limit_count: sync.limit_count,
      full_sync: sync.full_sync,
      requested_at: sync.created_at&.iso8601,
      started_at: sync.started_at&.iso8601,
      completed_at: sync.completed_at&.iso8601,
      imported_count: sync.imported_count,
      failed_count: sync.failed_count,
      error: sync.error
    }
  end

  def self.source_json(source)
    {
      id: source.id,
      kind: source.kind,
      display_name: source.display_name,
      status: source.status,
      authorization_state: source.authorization_state,
      bridge_status: source.bridge_status,
      bridge_last_seen_at: source.bridge_last_seen_at&.iso8601,
      last_sync_at: source.last_sync_at&.iso8601,
      last_error: source.last_error,
      asset_count: source.asset_count,
      imported_count: source.imported_count,
      watch_enabled: false,
      ingest_mode: "bridge"
    }
  end
end
