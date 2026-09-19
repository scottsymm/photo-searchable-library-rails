class Person < ApplicationRecord
  self.table_name = "persons"

  has_many :person_faces
end
