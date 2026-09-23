class HealthController < ApplicationController
  def index
    respond_to do |format|
      format.html do
        @overview = CatalogOverview.call
        render :dashboard
      end
      format.json { render json: { ok: true } }
    end
  end
end
