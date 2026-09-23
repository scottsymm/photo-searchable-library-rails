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
    "no_faces" => "No faces indexed yet"
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
    if source[:kind] == "mounted_folder"
      source[:watch_enabled] ? "badge badgeOk" : "badge badgeMuted"
    else
      "badge badgeMuted"
    end
  end

  def source_badge_label(source)
    case source[:ingest_mode]
    when "manual" then "Manual upload"
    when "watch" then source[:watch_enabled] ? "Watching" : "Watch paused"
    else "Bridge offline"
    end
  end
end
