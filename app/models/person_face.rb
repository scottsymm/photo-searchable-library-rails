class PersonFace < ApplicationRecord
  self.table_name = "person_faces"
  belongs_to :person
  belongs_to :face
end
