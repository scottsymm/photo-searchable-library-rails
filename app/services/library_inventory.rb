class LibraryInventory
  TTL = PICS_INVENTORY_CACHE_TTL

  @mutex = Mutex.new
  @cache = nil
  @cached_at = nil
  @cache_root = nil
  @cache_wall_at = nil

  class << self
    def call(root = PICS_WATCH_ROOT)
      now = Time.now.to_f
      return @cache if fresh?(now, root)

      @mutex.synchronize do
        return @cache if fresh?(now, root)

        @cache = new.scan(root)
        @cached_at = now
        @cache_root = root
        @cache_wall_at = Time.current
        @cache
      end
    end

    def scanned_at
      @cache_wall_at
    end

    def clear!
      @cache = nil
      @cached_at = nil
      @cache_root = nil
      @cache_wall_at = nil
    end

    private

    def fresh?(now, root)
      @cache && @cached_at && @cache_root == root && (now - @cached_at) <= TTL
    end
  end

  def scan(root)
    @photos_libraries = []
    @extensions = Hash.new(0)
    @media_files = 0
    @directory_errors = []

    unless File.directory?(root)
      return {
        root: root,
        available: false,
        media_files: 0,
        extensions: {},
        photos_libraries: [],
        directory_errors: []
      }
    end

    walk(root)
    {
      root: root,
      available: true,
      media_files: @media_files,
      extensions: @extensions.sort.to_h,
      photos_libraries: @photos_libraries,
      directory_errors: @directory_errors.first(20)
    }
  end

  private

  def walk(dir)
    Dir.children(dir).sort.each do |entry|
      path = File.join(dir, entry)
      next if File.symlink?(path)

      if File.directory?(path)
        if entry.end_with?(".photoslibrary")
          @photos_libraries << { name: entry, path: path }
        else
          walk(path)
        end
      elsif File.file?(path)
        suffix = File.extname(path).downcase
        if MEDIA_SUFFIXES.include?(suffix)
          @media_files += 1
          @extensions[suffix] += 1
        end
      end
    rescue Errno::EACCES, Errno::ENOENT => e
      @directory_errors << e.message
    end
  end
end
