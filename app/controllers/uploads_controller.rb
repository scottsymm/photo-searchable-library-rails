require "securerandom"
require "fileutils"

class UploadsController < ApplicationController
  def create
    file = params[:file]
    raise ActionController::ParameterMissing, "file" if file.nil?
    suffix = (File.extname(file.original_filename).presence || ".jpg").downcase
    destination = Pathname.new(PICS_LIBRARY) / "imports" / "#{SecureRandom.hex}#{suffix}"
    destination.dirname.mkpath
    File.binwrite(destination, file.read)

    job = Job.create!(kind: "import", params: { paths: [ destination.to_s ] }.to_json)
    ImportJob.perform_later(job_id: job.id, path: destination.to_s, index: 0, total: 1)

    render json: { job_id: job.id, status: "queued", path: destination.to_s }
  end
end
