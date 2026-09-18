class CatalogOverview
  STAGE_KEYS = %w[discovered ready_to_import importing imported processing searchable failed_or_blocked].freeze

  def self.call
    new.call
  end

  def call
    entries = sources
    funnel = STAGE_KEYS.each_with_object({}) { |key, acc| acc[key] = entries.sum { |e| e[:stages][key] } }
    {
      generated_at: Time.now.utc.iso8601,
      funnel: funnel,
      sources: entries,
      context: context,
    }
  end

  private

  def sources
    Source.all.map do |source|
      imported = Asset.not_deleted.where(source: source).count
      searchable = ContentEmbed.joins(:asset).where(assets: { source_id: source.id, deleted: 0 }).count
      stages = {
        "discovered" => imported,
        "ready_to_import" => 0,
        "importing" => 0,
        "imported" => imported,
        "processing" => [imported - searchable, 0].max,
        "searchable" => searchable,
        "failed_or_blocked" => 0,
      }
      {
        kind: source.kind,
        display_name: source.display_name,
        readiness: "connected",
        readiness_detail: nil,
        reported_at: source.last_sync_at&.iso8601,
        stages: stages,
        sync: nil,
        watch_enabled: source.kind == "mounted_folder" && Setting.get("watch_enabled") == "1",
        ingest_mode: { "apple_photos" => "bridge", "mounted_folder" => "watch", "uploads" => "manual" }.fetch(source.kind, "manual"),
        actions: { can_sync: source.kind == "apple_photos" },
      }
    end
  end

  def context
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
          taken_at: asset.taken_at&.iso8601,
        }
      end,
      photos_libraries: [],
      faces: {
        total: faces_total,
        assigned: assigned,
        unassigned: [faces_total - assigned, 0].max,
        embeddings_ready: FaceEmbed.count,
        embeddings_pending: [faces_total - FaceEmbed.count, 0].max,
        assets_processing: Asset.not_deleted.where.missing(:content_embed).count,
        clustering_status: "ready",
      },
      places: { located: located, unlocated: [total - located, 0].max },
    }
  end
end
