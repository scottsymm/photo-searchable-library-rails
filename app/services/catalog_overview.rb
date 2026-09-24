require "json"
require "set"

class CatalogOverview
  STAGE_KEYS = %w[discovered ready_to_import importing imported processing searchable failed_or_blocked].freeze

  def self.call
    new.call
  end

  def call
    inventory = LibraryInventory.call
    active = job_paths
    failed = failed_job_counts
    entries = [
      apple_entry(active, failed),
      mounted_entry(inventory, active, failed),
      uploads_entry(active, failed)
    ]
    funnel = STAGE_KEYS.each_with_object({}) { |key, acc| acc[key] = entries.sum { |e| e[:stages][key] } }
    {
      generated_at: Time.now.utc.iso8601,
      funnel: funnel,
      sources: entries,
      context: context(inventory)
    }
  end

  private

  def apple_entry(active, failed)
    src = Source.find_by!(kind: "apple_photos")
    latest_sync = src.source_syncs.order(id: :desc).first
    counts = processing_counts(src.id, active.fetch("apple_photos", Set.new))
    stages = empty_stages
    stages["discovered"] = src.asset_count
    stages["imported"] = counts[:imported]
    stages["ready_to_import"] = [ src.asset_count - counts[:imported], 0 ].max
    if latest_sync && %w[queued running].include?(latest_sync.status)
      stages["importing"] = latest_sync.full_sync == 1 ? stages["ready_to_import"] : [ latest_sync.limit_count, stages["ready_to_import"] ].min
    end
    stages["processing"] = counts[:processing]
    stages["searchable"] = counts[:searchable]
    stages["failed_or_blocked"] = counts[:stuck] +
      (latest_sync && %w[partial error].include?(latest_sync.status) ? latest_sync.failed_count : 0) +
      failed.fetch("apple_photos", 0)
    readiness, detail = readiness_for(src, latest_sync)
    {
      kind: "apple_photos",
      display_name: src.display_name,
      readiness: readiness,
      readiness_detail: detail,
      reported_at: src.last_sync_at&.iso8601,
      stages: stages,
      bridge_status: ApplePhotosBridge.source_with_bridge_status.bridge_status,
      bridge_last_seen_at: src.bridge_last_seen_at&.iso8601,
      authorization_state: src.authorization_state,
      watch_enabled: false,
      ingest_mode: "bridge",
      sync: ApplePhotosBridge.sync_json(latest_sync),
      actions: { can_sync: true }
    }
  end

  def mounted_entry(inventory, active, failed)
    src = Source.find_by!(kind: "mounted_folder")
    available = inventory[:available]
    counts = processing_counts(src.id, active.fetch("mounted_folder", Set.new))
    stages = empty_stages
    stages["discovered"] = available ? inventory[:media_files] : 0
    stages["imported"] = counts[:imported]
    stages["ready_to_import"] = [ stages["discovered"] - counts[:imported], 0 ].max
    stages["importing"] = active.fetch("mounted_folder", Set.new).size
    stages["processing"] = counts[:processing]
    stages["searchable"] = counts[:searchable]
    stages["failed_or_blocked"] = counts[:stuck] + failed.fetch("mounted_folder", 0)
    readiness, detail = available ? [ "connected", nil ] : [ "failed", "watch root is not available: #{inventory[:root]}" ]
    {
      kind: "mounted_folder",
      display_name: src.display_name,
      readiness: readiness,
      readiness_detail: detail,
      reported_at: LibraryInventory.scanned_at&.iso8601,
      stages: stages,
      sync: nil,
      watch_enabled: Setting.get("watch_enabled") == "1",
      ingest_mode: "watch",
      actions: { can_sync: false }
    }
  end

  def uploads_entry(active, failed)
    src = Source.find_by!(kind: "uploads")
    counts = processing_counts(src.id, active.fetch("uploads", Set.new))
    stages = empty_stages
    stages["discovered"] = counts[:imported]
    stages["imported"] = counts[:imported]
    stages["importing"] = active.fetch("uploads", Set.new).size
    stages["processing"] = counts[:processing]
    stages["searchable"] = counts[:searchable]
    stages["failed_or_blocked"] = counts[:stuck] + failed.fetch("uploads", 0)
    {
      kind: "uploads",
      display_name: src.display_name,
      readiness: "connected",
      readiness_detail: nil,
      reported_at: nil,
      stages: stages,
      sync: nil,
      watch_enabled: false,
      ingest_mode: "manual",
      actions: { can_sync: false }
    }
  end

  def readiness_for(src, latest_sync)
    auth = src.authorization_state
    if %w[denied restricted notDetermined].include?(auth)
      return [ "authorization_required", "Photos authorization is #{auth}" ]
    end
    if latest_sync && latest_sync.status == "error"
      return [ "failed", latest_sync.error || "last sync failed" ]
    end
    return [ "failed", src.last_error ] if src.last_error.present?

    if src.status == "not_connected" && src.last_sync_at.nil? && latest_sync.nil?
      return [ "not_configured", nil ]
    end
    if src.asset_count.zero? && !(latest_sync && %w[done partial].include?(latest_sync.status))
      return [ "inventory_pending", "waiting for the bridge to report library totals" ]
    end
    [ "connected", nil ]
  end

  def processing_counts(source_id, active_paths)
    counts = { imported: 0, searchable: 0, processing: 0, stuck: 0 }
    Asset.not_deleted.where(source_id: source_id).find_each do |asset|
      counts[:imported] += 1
      if asset.content_embed.present?
        counts[:searchable] += 1
      elsif active_paths.include?(asset.path)
        counts[:processing] += 1
      else
        counts[:stuck] += 1
      end
    end
    counts
  end

  def job_paths
    job_paths_for(%w[queued working])
  end

  def job_paths_for(statuses)
    result = Hash.new { |h, k| h[k] = Set.new }
    Job.where(kind: %w[import scan], status: statuses).find_each do |job|
      JSON.parse(job.params || "{}").dig("paths").to_a.each do |path|
        kind = Source.classify_path(path)&.kind
        result[kind] << path if kind
      end
    end
    result
  end

  def failed_job_counts
    resolved = job_paths_for(%w[queued working done])
    counts = Hash.new(0)
    counted = Hash.new { |h, k| h[k] = Set.new }
    Job.where(kind: %w[import scan], status: "error").find_each do |job|
      JSON.parse(job.params || "{}").dig("paths").to_a.each do |path|
        kind = Source.classify_path(path)&.kind
        next if kind.nil?
        next if resolved[kind].include?(path)
        next if counted[kind].include?(path)

        counted[kind] << path
        counts[kind] += 1
      end
    end
    counts
  end

  def empty_stages
    STAGE_KEYS.each_with_object({}) { |key, acc| acc[key] = 0 }
  end

  def context(inventory)
    recent = Asset.not_deleted
                  .order(Arel.sql("thumbnail_id IS NULL, created_at DESC, taken_at DESC"))
                  .limit(6)
                  .includes(:source)
    faces_total = Face.count
    assigned = PersonFace.count
    located = Asset.not_deleted.where.not(gps_lat: nil).count
    total = Asset.not_deleted.count
    {
      recent_imports: recent.map do |asset|
        {
          id: asset.id,
          source_kind: asset.source&.kind,
          original_filename: asset.original_filename,
          imported_at: asset.created_at&.iso8601,
          taken_at: asset.taken_at&.iso8601
        }
      end,
      photos_libraries: inventory[:photos_libraries],
      faces: {
        total: faces_total,
        assigned: assigned,
        unassigned: [ faces_total - assigned, 0 ].max,
        embeddings_ready: FaceEmbed.count,
        embeddings_pending: [ faces_total - FaceEmbed.count, 0 ].max,
        assets_processing: Asset.not_deleted.where.missing(:content_embed).count,
        clustering_status: "ready"
      },
      places: { located: located, unlocated: [ total - located, 0 ].max }
    }
  end
end
