class CatalogController < ApplicationController
  def overview
    @overview = CatalogOverview.call
    respond_to do |format|
      format.json { render json: @overview }
      format.html
    end
  end
end
