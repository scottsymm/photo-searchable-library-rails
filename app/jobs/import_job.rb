require "fileutils"

class ImportJob < ApplicationJob
  queue_as :default

  def perform(job_id:, path:, index:, total:)
    job = Job.find(job_id)
    AssetImporter.import(path)
    job.record_completion!(total)
    broadcast_catalog if job.reload.status == "done"
  rescue StandardError => e
    FileUtils.rm_f(path) if job&.kind == "import"
    job&.record_attempt!(total, error: "#{path}: #{e.message}")
    broadcast_catalog if job&.reload&.status == "error"
  end

  private

  def broadcast_catalog
    Turbo::StreamsChannel.broadcast_replace_later_to "catalog",
      target: "catalog_overview",
      partial: "catalog/overview",
      locals: { overview: CatalogOverview.call }
  end
end
