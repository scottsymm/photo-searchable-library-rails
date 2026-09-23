class FaceAssignment < ApplicationRecord
  belongs_to :run, class_name: "ClusteringRun"
  belongs_to :face
  belongs_to :suggestion, class_name: "ClusterSuggestion", optional: true
  validates :face_id, uniqueness: { scope: :run_id }
end
