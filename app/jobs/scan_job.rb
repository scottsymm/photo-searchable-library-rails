class ScanJob < ApplicationJob
  queue_as :default

  def perform(job_id:, root:)
    job = Job.find(job_id)
    job.mark_working!

    paths = Dir.glob(File.join(root, "**", "*")).select do |path|
      File.file?(path) && MEDIA_SUFFIXES.include?(File.extname(path).downcase)
    end.sort

    job.update!(params: { paths: paths }.to_json)

    if paths.empty?
      job.complete!
      return
    end

    paths.each_with_index do |path, index|
      ImportJob.perform_later(job_id: job.id, path: path, index: index, total: paths.length)
    end
  end
end
