class PersonFacesController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    person.assign_face!(Face.find(params[:face_id]))
    respond_to { |format| format.json { render json: person }; format.html { redirect_to persons_path } }
  end

  def crop
    face = Face.find(params[:face_id])
    path = FaceCrop.contained_path(face.crop_path.to_s)
    return head :not_found unless File.file?(path)
    send_data File.binread(path), type: "image/jpeg", disposition: "inline"
  rescue ActiveRecord::RecordNotFound, FaceCrop::UnsafePath
    head :not_found
  end
end
