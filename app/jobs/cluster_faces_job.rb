class ClusterFacesJob < ApplicationJob
  queue_as :default

  def perform(job_id: nil, eps: FaceClustering::DEFAULT_EPS, min_samples: FaceClustering::DEFAULT_MIN_SAMPLES)
    job = job_id && Job.find(job_id)
    FaceClustering.run(eps: eps, min_samples: min_samples, job: job)
  end
end
