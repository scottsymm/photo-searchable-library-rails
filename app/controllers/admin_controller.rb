class AdminController < ApplicationController
  def status
    models_ready = SidecarClient.status["ok"] == true rescue false
    root_available = File.directory?(PICS_WATCH_ROOT)
    counts = {
      "assets" => Asset.count,
      "faces" => Face.count,
      "persons" => Person.count,
      "jobs" => Job.count
    }
    render json: {
      mount_source: ENV.fetch("PICS_MOUNT_SOURCE", nil),
      watch_root: PICS_WATCH_ROOT,
      root_available: root_available,
      models_ready: models_ready,
      disk: nil,
      counts: counts,
      settings: Setting.all_map
    }
  end

  def settings
    render json: { settings: Setting.all_map }
  end

  def update_settings
    if params[:watch_enabled].present?
      Setting.set_value("watch_enabled", params[:watch_enabled]) if %w[0 1].include?(params[:watch_enabled].to_s)
    end
    if params[:watch_backfill].present?
      Setting.set_value("watch_backfill", params[:watch_backfill]) if %w[prompt backfill done].include?(params[:watch_backfill].to_s)
    end
    render json: { settings: Setting.all_map }
  end

  def scan
    root = params[:root].presence || PICS_WATCH_ROOT
    raise ActiveRecord::RecordNotFound, "root is not a directory: #{root}" unless File.directory?(root)

    paths = Dir.glob(File.join(root, "**", "*")).select do |path|
      File.file?(path) && MEDIA_SUFFIXES.include?(File.extname(path).downcase)
    end
    job = Job.create!(kind: "scan", params: { paths: paths }.to_json)
    ScanJob.perform_later(job_id: job.id, root: root)
    render json: { job_id: job.id, paths: paths.length, status: "queued" }
  end
end
