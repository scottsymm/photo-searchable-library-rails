class SearchController < ApplicationController
  def index
    parsed = SearchQuery.parse(params[:q])
    @results = SearchService.search(
      q: parsed[:text], who: parsed[:who] || params[:who], place: parsed[:place] || params[:place],
      before: parsed[:before] || params[:before], after: parsed[:after] || params[:after], tag: parsed[:tag] || params[:tag],
      limit: (params[:limit] || 50).to_i
    )
    respond_to do |format|
      format.json { render json: { results: @results } }
      format.html
    end
  end
end
