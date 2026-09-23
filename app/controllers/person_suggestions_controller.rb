class PersonSuggestionsController < ApplicationController
  before_action :load_suggestion

  def confirm
    person = Person.find_by(id: params[:person_id]) ||
             (params[:name].present? ? Person.create!(name: params[:name]) : nil)
    @suggestion.confirm!(person: person)
    render_result
  end

  def reject
    @suggestion.reject!
    render_result
  end

  def restore
    @suggestion.restore!
    render_result
  end

  private

  def load_suggestion
    @suggestion = ClusterSuggestion.find(params[:id])
  end

  def render_result
    respond_to { |format| format.json { render json: @suggestion }; format.html { redirect_to persons_path } }
  end
end
