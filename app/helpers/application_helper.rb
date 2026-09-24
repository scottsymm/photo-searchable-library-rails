module ApplicationHelper
  FUNNEL_STAGES = [
    { key: "discovered", label: "Discovered", approximate: false, tone: "default" },
    { key: "ready_to_import", label: "Ready to import", approximate: false, tone: "default" },
    { key: "importing", label: "Importing", approximate: true, tone: "default" },
    { key: "imported", label: "Imported", approximate: false, tone: "default" },
    { key: "processing", label: "Processing", approximate: false, tone: "default" },
    { key: "searchable", label: "Searchable", approximate: false, tone: "goal" },
    { key: "failed_or_blocked", label: "Failed / Blocked", approximate: true, tone: "bad" }
  ].freeze

  CLUSTERING_LABELS = {
    "ready" => "Clustering ready",
    "completed_no_suggestions" => "Clustering complete · no new groups",
    "indexing" => "Clustering will cover indexed faces",
    "running" => "Clustering in progress",
    "queued" => "Clustering in progress",
    "no_faces" => "No faces indexed yet",
    "error" => "Clustering failed"
  }.freeze

  def funnel_stages
    FUNNEL_STAGES
  end

  def clustering_status_label(status)
    CLUSTERING_LABELS.fetch(status, "Clustering not ready")
  end

  def assigned_pct(faces)
    faces[:total].zero? ? 0 : (faces[:assigned].to_f / faces[:total] * 100).round
  end

  def located_pct(places)
    total = places[:located] + places[:unlocated]
    total.zero? ? 0 : (places[:located].to_f / total * 100).round
  end

  def source_badge_class(source)
    if source[:kind] == "apple_photos"
      case source[:bridge_status]
      when "connected" then "badge badgeOk"
      when "authorization_required" then "badge badgeWarn"
      else "badge badgeMuted"
      end
    elsif source[:ingest_mode] == "manual"
      "badge badgeMuted"
    elsif source[:ingest_mode] == "watch"
      source[:watch_enabled] ? "badge badgeOk" : "badge badgeMuted"
    elsif source[:readiness] == "connected"
      "badge badgeOk"
    elsif %w[failed authorization_required].include?(source[:readiness])
      "badge badgeWarn"
    else
      "badge badgeMuted"
    end
  end

  def source_badge_label(source)
    if source[:kind] == "apple_photos"
      bridge_label(source[:bridge_status])
    elsif source[:ingest_mode] == "manual"
      "Manual upload"
    elsif source[:ingest_mode] == "watch"
      source[:watch_enabled] ? "Watching" : "Watch paused"
    else
      readiness_label(source[:readiness])
    end
  end

  def bridge_label(status)
    {
      "offline" => "Bridge offline",
      "authorization_required" => "Photos access required",
      "inventory_pending" => "Reading Photos library",
      "connected" => "Connected",
      "syncing" => "Syncing"
    }.fetch(status.to_s, "Bridge offline")
  end

  def readiness_label(status)
    {
      "not_configured" => "Not configured",
      "authorization_required" => "Authorization required",
      "inventory_pending" => "Inventory pending",
      "connected" => "Connected",
      "failed" => "Failed"
    }.fetch(status.to_s, "Unknown")
  end

  def freshness_label(source)
    return "live" if source[:kind] == "uploads"
    return "never synced" if source[:reported_at].blank?

    reported = Time.zone.parse(source[:reported_at])
    return "as of last sync #{reported.to_fs(:short)}" unless source[:kind] == "mounted_folder"

    minutes = ((Time.current - reported) / 60).round
    return "scanned just now" if minutes < 1
    return "scanned #{minutes} min ago" if minutes < 60

    hours = minutes / 60
    return "scanned #{hours} h ago" if hours < 24

    "scanned #{hours / 24} d ago"
  end

  def sync_active?(sync)
    sync.present? && %w[queued running].include?(sync[:status])
  end

  def people_enrichment_message(enrichment)
    status = enrichment[:clustering_status]
    return "No faces have been indexed yet." if status == "no_faces"
    if status == "indexing"
      "Face indexing in progress. Run clustering again when it finishes."
    elsif enrichment[:assets_processing] > 0
      "Some assets are still processing. Run clustering again when processing finishes."
    elsif %w[queued running].include?(status)
      "Clustering is in progress. Suggestions will appear when the worker finishes."
    elsif status == "completed_no_suggestions"
      "Clustering completed without finding new groups."
    elsif status == "error"
      "Clustering failed. Review the latest job error and try again."
    else
      "Face indexing is complete. Clustering is ready."
    end
  end

  def watch_enabled?
    @status.present? && @status[:settings].is_a?(Hash) && @status[:settings]["watch_enabled"] == "1"
  end
end
