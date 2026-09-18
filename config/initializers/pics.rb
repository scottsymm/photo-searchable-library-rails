PICS_LIBRARY = ENV.fetch("PICS_LIBRARY", File.expand_path("library", Rails.root))
PICS_WATCH_ROOT = ENV.fetch("PICS_WATCH_ROOT", "/media/photos")
PICS_WORKER_URL = ENV.fetch("PICS_WORKER_URL", "http://localhost:9090")
PICS_MODEL = ENV.fetch("PICS_MODEL", "openai/clip-vit-base-patch32")
PICS_MODEL_VERSION = ENV.fetch("PICS_MODEL_VERSION", "clip-vit-base-patch32-v1")
MEDIA_SUFFIXES = %w[.jpg .jpeg .png .heic .heif .mov .mp4 .avif .dng].freeze
