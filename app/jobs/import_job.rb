require "fileutils"

class ImportJob < ApplicationJob
  queue_as :default

  def perform(job_id:, path:, index:, total:)
    job = Job.find(job_id)
    AssetImporter.import(path)
    job.record_completion!(total)
  rescue StandardError => e
    FileUtils.rm_f(path) if job&.kind == "import"
    job&.fail!(e.message)
  end
end
