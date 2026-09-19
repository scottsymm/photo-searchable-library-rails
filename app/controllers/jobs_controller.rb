class JobsController < ApplicationController
  def index
    @jobs = Job.order(id: :desc).limit(100)
    respond_to do |format|
      format.json { render json: { jobs: @jobs.as_json(only: [ :id, :kind, :status, :progress, :error, :params, :created_at, :updated_at ]) } }
      format.html
    end
  end

  def show
    job = Job.find(params[:id])
    render json: job.as_json(only: [ :id, :kind, :status, :progress, :error, :params, :created_at, :updated_at ])
  end
end
