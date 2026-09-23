class PersonsController < ApplicationController
  def index
    @persons = Person.search(params[:q]).includes(:aliases, :faces).order(:name)
    @suggestions = ClusterSuggestion.pending.includes(:representative_face, :face_assignments)
    respond_to do |format|
      format.html
      format.json { render json: { persons: @persons.as_json(include: :aliases), suggestions: @suggestions } }
    end
  end

  def update
    person = Person.find(params[:id])
    person.update!(person_params)
    render_person(person)
  end

  def cluster
    job = Job.create!(kind: "cluster", status: "queued", params: {})
    ClusterFacesJob.perform_later(job_id: job.id)
    respond_to { |format| format.json { render json: job, status: :accepted }; format.html { redirect_to persons_path } }
  end

  private

  def person_params
    params.require(:person).permit(:name)
  end

  def render_person(person)
    respond_to { |format| format.json { render json: person }; format.html { redirect_to persons_path } }
  end
end
