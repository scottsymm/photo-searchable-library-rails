class ClusteringRun < ApplicationRecord
  has_many :face_assignments, foreign_key: :run_id, dependent: :destroy
  has_many :cluster_suggestions, foreign_key: :run_id, dependent: :destroy
end
