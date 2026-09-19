class SearchController < ApplicationController
  def index
    @results = SearchService.search(
      q: params[:q], who: params[:who], place: params[:place],
      before: params[:before], after: params[:after], tag: params[:tag],
      limit: (params[:limit] || 50).to_i,
    )
    respond_to do |format|
      format.json { render json: { results: @results } }
      format.html
    end
  end
end
