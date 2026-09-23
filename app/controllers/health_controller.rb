class HealthController < ApplicationController
  def index
    respond_to do |format|
      format.html do
        @results = []
        render template: "search/index"
      end
      format.json { render json: { ok: true } }
    end
  end
end
