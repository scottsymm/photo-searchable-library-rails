require "securerandom"
require "fileutils"

class UploadsController < ApplicationController
  def create
    file = params[:file]
    raise ActionController::ParameterMissing, "file" if file.nil?
    suffix = File.extname(file.original_filename).downcase
    raise ActionController::BadRequest, "unsupported file type" unless MEDIA_SUFFIXES.include?(suffix)
    raise ActionController::BadRequest, "file is too large" if file.size > PICS_MAX_UPLOAD_BYTES

    destination = Pathname.new(PICS_LIBRARY) / "imports" / "#{SecureRandom.hex}#{suffix}"
    begin
      destination.dirname.mkpath
      file.tempfile.rewind
      File.open(destination, "wb") { |output| IO.copy_stream(file.tempfile, output) }

      job = Job.create!(kind: "import", params: { paths: [ destination.to_s ] }.to_json)
      ImportJob.perform_later(job_id: job.id, path: destination.to_s, index: 0, total: 1)
    rescue StandardError
      FileUtils.rm_f(destination)
      raise
    end

    render json: { job_id: job.id, status: "queued", path: destination.to_s }
  end
end
