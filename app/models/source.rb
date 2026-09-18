class Source < ApplicationRecord
  has_many :assets
  has_many :source_syncs

  def self.library_root
    Pathname.new(PICS_LIBRARY)
  end

  def self.watch_root
    Pathname.new(PICS_WATCH_ROOT)
  end

  def self.classify_path(path)
    resolved = Pathname.new(path).expand_path.to_s
    [ [ "apple-photos", "apple_photos" ], [ "imports", "uploads" ] ].each do |subdir, kind|
      prefix = library_root.join(subdir).expand_path.to_s
      return find_by!(kind: kind) if resolved.start_with?(prefix + File::SEPARATOR) || resolved == prefix
    end
    prefix = watch_root.expand_path.to_s
    return find_by!(kind: "mounted_folder") if resolved.start_with?(prefix + File::SEPARATOR) || resolved == prefix
    nil
  end
end
