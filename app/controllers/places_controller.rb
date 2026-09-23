class PlacesController < ApplicationController
  def index
    @places = Asset.not_deleted
                   .where.not(place_city: nil)
                   .group(:place_city, :place_country)
                   .count
                   .map { |(city, country), count| { place_city: city, place_country: country, count: count } }
                   .sort_by { |place| [ -place[:count], place[:place_city] ] }
    respond_to do |format|
      format.json { render json: { places: @places } }
      format.html
    end
  end
end
