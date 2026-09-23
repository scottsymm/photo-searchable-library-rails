class Face < ApplicationRecord
  belongs_to :asset
  has_one :face_embed, dependent: :destroy
  has_many :person_faces, dependent: :destroy
  has_many :persons, through: :person_faces

  validates :bbox, presence: true

  def box
    bbox.to_s.split(",").map(&:to_f)
  end
end
