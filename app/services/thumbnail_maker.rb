require "vips"
require "open3"

class ThumbnailMaker
  MAX_DIM = 512

  def self.thumbnail(path, mime)
    if mime.to_s.start_with?("video/")
      video_frame(path)
    else
      image_thumbnail(path)
    end
  end

  def self.image_thumbnail(path)
    image = Vips::Image.new_from_file(path)
    image = image.flatten(background: [ 244, 241, 233 ]) if image.has_alpha?
    image = image.thumbnail_image(MAX_DIM, height: MAX_DIM)
    image.jpegsave_buffer(Q: 82)
  rescue Vips::Error => e
    raise "thumbnail failed for #{path}: #{e.message}"
  end

  def self.video_frame(path)
    stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-loglevel", "error", "-i", path, "-frames:v", "1",
      "-vf", "scale='if(gt(iw,ih),#{MAX_DIM},-1)':'if(gt(iw,ih),-1,#{MAX_DIM})'",
      "-f", "image2pipe", "-vcodec", "mjpeg", "-",
    )
    raise "ffmpeg produced no frame for #{path}: #{stderr}" if stdout.empty? || !status.success?
    stdout
  end
end
