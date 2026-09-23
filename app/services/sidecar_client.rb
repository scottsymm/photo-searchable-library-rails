require "faraday"
require "faraday/multipart"
require "base64"
require "stringio"

class SidecarClient
  class SidecarError < StandardError; end

  def self.status
    new.get("/v1/status")
  end

  def self.embed_text(text)
    new.post("/v1/embed-text", { texts: [ text ] })
  end

  def self.embed_image(image_bytes, mime: "image/jpeg")
    new.post("/v1/embed-image", {
      image_base64: Base64.strict_encode64(image_bytes),
      mime: mime
    })
  end

  def self.reverse_geocode(lat:, lon:)
    new.post("/v1/reverse-geocode", { lat: lat, lon: lon })
  end

  def self.detect_faces(image_bytes, filename: "image.jpg", mime: "image/jpeg")
    new.detect_faces(image_bytes, filename: filename, mime: mime)
  end

  def self.cluster_faces(embeddings, eps: 0.35, min_samples: 2)
    new.post("/v1/cluster-faces", { embeddings: embeddings, eps: eps, min_samples: min_samples }).tap do |response|
      raise SidecarError, "invalid cluster response" unless response["labels"].is_a?(Array) && response["labels"].length == embeddings.length
    end
  end

  def initialize
    @conn = Faraday.new(url: PICS_WORKER_URL) do |faraday|
      faraday.request :multipart
      faraday.request :json
      faraday.response :json
      faraday.response :raise_error
      faraday.options.timeout = 120
    end
  end

  def get(path)
    @conn.get(path).body
  rescue Faraday::Error => e
    raise SidecarError, "sidecar GET #{path} failed: #{e.class}: #{e.message}"
  end

  def post(path, body)
    @conn.post(path, body).body
  rescue Faraday::Error => e
    raise SidecarError, "sidecar POST #{path} failed: #{e.class}: #{e.message}"
  end

  def detect_faces(image_bytes, filename:, mime:)
    multipart_conn = Faraday.new(url: PICS_WORKER_URL) do |faraday|
      faraday.request :multipart
      faraday.response :json
      faraday.response :raise_error
      faraday.options.timeout = 120
    end
    response = multipart_conn.post("/v1/detect-faces") do |request|
      request.body = { file: Faraday::Multipart::FilePart.new(StringIO.new(image_bytes), mime, filename) }
    end
    faces = response.body["faces"]
    raise SidecarError, "invalid face response" unless faces.is_a?(Array) && faces.all? { |face| face["box"].is_a?(Array) && face["embedding"]&.length == 512 }
    faces
  rescue Faraday::Error => e
    raise SidecarError, "sidecar face detection failed: #{e.class}: #{e.message}"
  end
end
