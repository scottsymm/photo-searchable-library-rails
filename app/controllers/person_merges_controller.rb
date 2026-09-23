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
    target = Person.create!(name: params.require(:person).permit(:name)[:name].to_s)
    Array(params[:face_ids]).each { |id| PersonFace.where(person: person, face_id: id).delete_all; target.assign_face!(Face.find(id), source: "split") }
    respond_to { |format| format.json { render json: target, status: :created }; format.html { redirect_to persons_path } }
  end
end
