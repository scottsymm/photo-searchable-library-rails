class SearchController < ApplicationController
  def index
    parsed = SearchQuery.parse(params[:q])
    @results = SearchService.search(
      q: parsed[:text], who: parsed[:who], place: parsed[:place],
      before: parsed[:before], after: parsed[:after], tag: parsed[:tag],
      limit: (params[:limit] || 50).to_i
    )
    respond_to do |format|
      format.json { render json: { results: @results } }
      format.html
    end
  end
end
