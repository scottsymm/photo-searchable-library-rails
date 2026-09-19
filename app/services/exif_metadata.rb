require "mini_exiftool"

class ExifMetadata
  def self.extract(path)
    tag = MiniExiftool.new(path, numerical: true)
    {
      taken_at: tag.datetimeoriginal || tag.createdate,
      gps_lat: signed(tag.gpslatitude, tag.gpslatituderef),
      gps_lon: signed(tag.gpslongitude, tag.gpslongituderef),
      mime: tag.mimetype || "application/octet-stream",
      size_bytes: tag.filesize.to_i,
      model: tag.model
    }
  rescue MiniExiftool::Error, Errno::ENOENT
    { mime: "application/octet-stream", size_bytes: File.size(path).to_i }
  end

  def self.signed(value, reference)
    return nil if value.nil?

    number = value.to_f
    if %w[S W South West].include?(reference.to_s)
      -number.abs
    else
      number.abs
    end
  end
end
