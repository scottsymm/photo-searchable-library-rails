class ClusterSuggestion < ApplicationRecord
  belongs_to :run, class_name: "ClusteringRun"
  belongs_to :representative_face, class_name: "Face", optional: true
  belongs_to :person, optional: true
  has_many :face_assignments, foreign_key: :suggestion_id, dependent: :nullify

  scope :pending, -> { where(status: "unreviewed") }

  def confirm!(person: nil)
    transaction do
      target = person || Person.create!(name: "")
      face_assignments.includes(:face).each { |assignment| target.assign_face!(assignment.face, source: "cluster") }
      update!(person: target, status: "confirmed")
    end
  end

  def reject!
    update!(status: "rejected") unless status == "rejected"
  end

  def restore!
    update!(status: "unreviewed") unless status == "unreviewed"
  end
end
