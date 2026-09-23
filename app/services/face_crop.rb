require "digest"
require "fileutils"
require "json"
require "pathname"
require "vips"

class FaceCrop
  class UnsafePath < StandardError; end

  def self.create(asset:, box:, source_digest: asset.sha256)
    image = Vips::Image.new_from_file(asset.path, access: :sequential)
    x, y, width, height = clamp_box(box, image.width, image.height)
    raise Vips::Error, "empty face box" if width.zero? || height.zero?

    key = detection_key([ x, y, width, height ])
    relative = "#{asset.id}-#{Digest::SHA256.hexdigest("#{key}:#{source_digest}")}.jpg"
    root = crop_root
    FileUtils.mkdir_p(root)
    path = contained_path(relative)
    image.crop(x, y, width, height).write_to_file(path, Q: 90)
    relative
  end

  def self.detection_key(box)
    box.map { |value| value.to_f.round(2) }.join(",")
  end

  def self.contained_path(relative)
    raise UnsafePath if relative.blank? || Pathname.new(relative).absolute? || relative.split("/").include?("..")
    root = Pathname.new(crop_root).realpath
    candidate = Pathname.new(File.expand_path(relative, root))
    raise UnsafePath unless candidate.to_s == root.to_s || candidate.to_s.start_with?("#{root}/")
    if File.exist?(candidate) && !Pathname.new(candidate).realpath.to_s.start_with?("#{root}/")
      raise UnsafePath
    end
    candidate.to_s
  rescue Errno::ENOENT
    raise UnsafePath
  end

  def self.crop_root
    File.join(PICS_LIBRARY, ".crops")
  end

  def self.clamp_box(box, image_width, image_height)
    x, y, width, height = box.map(&:to_f)
    left = x.clamp(0, image_width)
    top = y.clamp(0, image_height)
    right = (x + width).clamp(0, image_width)
    bottom = (y + height).clamp(0, image_height)
    [ left.round, top.round, [ right.round - left.round, 0 ].max, [ bottom.round - top.round, 0 ].max ]
  end
end
