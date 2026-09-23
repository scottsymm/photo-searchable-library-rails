class FaceEnrichment
  def self.call
    total = Face.count
    ready = FaceEmbed.count
    run = ClusteringRun.order(id: :desc).first
    {
      total: total,
      embeddings_ready: ready,
      embeddings_pending: [ total - ready, 0 ].max,
      assets_processing: Asset.not_deleted.where.missing(:content_embed).count,
      clustering_status: clustering_status(total, run)
    }
  end

  def self.clustering_status(total, run)
    return "no_faces" if total.zero?
    return "ready" if run.nil?
    return run.status if %w[running queued].include?(run.status)
    return "completed_no_suggestions" if run.status == "done" && !run.cluster_suggestions.exists?
    return "ready" if run.status == "done"
    return "error" if run.status == "error"

    "not_ready"
  end
end
