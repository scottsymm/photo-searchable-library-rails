class ClusterSuggestion < ApplicationRecord
  belongs_to :run, class_name: "ClusteringRun"
end
