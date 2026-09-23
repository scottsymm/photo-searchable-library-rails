class Person < ApplicationRecord
  self.table_name = "persons"

  has_many :person_faces
  has_many :faces, through: :person_faces
  has_many :aliases, class_name: "PersonAlias", dependent: :destroy
  has_many :cluster_suggestions, dependent: :nullify

  validates :name, presence: true, allow_blank: true

  def self.search(query)
    return all if query.blank?
    escaped = "%#{sanitize_sql_like(query)}%"
    left_joins(:aliases).where("persons.name LIKE :q OR person_aliases.alias LIKE :q", q: escaped).distinct
  end

  def assign_face!(face, source: "manual")
    PersonFace.find_or_create_by!(person: self, face: face) { |link| link.source = source }
  end

  def face_count
    person_faces.count
  end

  def representative_url
    face_id = prototype_face_id || faces.first&.id
    face_id && "/persons/faces/#{face_id}/crop"
  end
end
