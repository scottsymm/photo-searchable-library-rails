class PersonMergesController < ApplicationController
  def create
    keep = Person.find(params[:person_id])
    remove = Person.find(params[:remove_id])
    Person.transaction do
      remove.aliases.each { |record| keep.aliases.find_or_create_by!(alias: record.alias) }
      remove.faces.each { |face| keep.assign_face!(face, source: "merge") }
      remove.destroy!
    end
    respond_to { |format| format.json { render json: keep }; format.html { redirect_to persons_path } }
  end

  def split
    person = Person.find(params[:person_id])
    face_ids = Array(params[:face_ids])
    faces = person.faces.where(id: face_ids).to_a
    unless faces.map { |face| face.id.to_s }.sort == face_ids.map(&:to_s).uniq.sort
      raise ActiveRecord::RecordNotFound, "requested face is not assigned to this person"
    end

    target = Person.transaction do
      target = Person.create!(name: params.require(:person).permit(:name)[:name].to_s)
      faces.each { |face| PersonFace.where(person: person, face: face).delete_all; target.assign_face!(face, source: "split") }
      target
    end
    respond_to { |format| format.json { render json: target, status: :created }; format.html { redirect_to persons_path } }
  end
end
