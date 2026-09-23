class FaceClustering
  DEFAULT_EPS = 0.35
  DEFAULT_MIN_SAMPLES = 2
  LOCK_KEY = "face_clustering_lock"

  def self.run(eps: DEFAULT_EPS, min_samples: DEFAULT_MIN_SAMPLES, job: nil)
    run = nil
    Setting.create_or_find_by!(key: LOCK_KEY).with_lock do
      faces = Face.left_joins(:persons)
        .where(person_faces: { id: nil })
        .where.not(id: FaceAssignment.select(:face_id))
        .includes(:face_embed)
        .filter_map { |face| face if face.face_embed&.embed&.bytesize == 2048 }
      run = ClusteringRun.create!(model: "insightface", model_version: "v1", algorithm: "dbscan", metric: "cosine", eps: eps, min_samples: min_samples, status: "running")
      job&.update!(status: "working", progress: 0)
      labels = SidecarClient.cluster_faces(faces.map { |face| face.face_embed.vector }, eps: eps, min_samples: min_samples).fetch("labels")
      ActiveRecord::Base.transaction do
        clusters = Hash.new { |hash, key| hash[key] = [] }
        labels.each_with_index { |label, index| clusters[label] << faces[index] if label.to_i >= 0 }
        clusters.each do |label, members|
          suggestion = run.cluster_suggestions.create!(cluster_key: label, representative_face: members.first, face_count: members.length)
          members.each { |face| run.face_assignments.create!(face: face, suggestion: suggestion, status: "suggested") }
        end
        run.update!(status: "done", completed_at: Time.current)
      end
      job&.complete!
    end
    run
  rescue StandardError => error
    run&.update(status: "error", error: error.message.to_s[0, 4000])
    job&.fail!(error.message)
    raise
  end
end
