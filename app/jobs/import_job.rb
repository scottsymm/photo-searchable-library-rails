class ImportJob < ApplicationJob
  queue_as :default

  def perform(job_id:, path:, index:, total:)
    job = Job.find(job_id)
    AssetImporter.import(path)
    job.bump_progress!((index + 1).to_f / total)
    job.complete! if index + 1 >= total
  rescue StandardError => e
    job.fail!(e.message)
  end
end
