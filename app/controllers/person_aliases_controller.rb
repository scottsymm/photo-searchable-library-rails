class PersonAliasesController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    alias_record = person.aliases.create!(alias_params)
    respond_to { |format| format.json { render json: alias_record, status: :created }; format.html { redirect_to persons_path } }
  end

  def destroy
    PersonAlias.find_by!(id: params[:id], person_id: params[:person_id]).destroy!
    respond_to { |format| format.json { head :no_content }; format.html { redirect_to persons_path } }
  end

  private

  def alias_params
    params.require(:person_alias).permit(:alias)
  end
end
