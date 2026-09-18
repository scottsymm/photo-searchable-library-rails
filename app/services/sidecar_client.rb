require "faraday"
require "base64"

class SidecarClient
  class SidecarError < StandardError; end

  def self.status
    new.get("/v1/status")
  end

  def self.embed_text(text)
    new.post("/v1/embed-text", { texts: [text] })
  end

  def self.embed_image(image_bytes, mime: "image/jpeg")
    new.post("/v1/embed-image", {
      image_base64: Base64.strict_encode64(image_bytes),
      mime: mime,
    })
  end

  def self.reverse_geocode(lat:, lon:)
    new.post("/v1/reverse-geocode", { lat: lat, lon: lon })
  end

  def initialize
    @conn = Faraday.new(url: PICS_WORKER_URL) do |faraday|
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
end
