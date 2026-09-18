ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      db = ActiveRecord::Base.connection.raw_connection
      begin
        db.execute("SELECT rowid FROM vec0_content LIMIT 0")
      rescue SQLite3::SQLException
        %w[vec0_content_info vec0_content_chunks vec0_content_rowids vec0_content_vector_chunks00].each do |table|
          db.execute("DROP TABLE IF EXISTS #{table}")
        end
        db.execute("CREATE VIRTUAL TABLE vec0_content USING vec0(content_embed float[512])")
      end
      begin
        db.execute("SELECT rowid FROM vec0_face LIMIT 0")
      rescue SQLite3::SQLException
        %w[vec0_face_info vec0_face_chunks vec0_face_rowids vec0_face_vector_chunks00].each do |table|
          db.execute("DROP TABLE IF EXISTS #{table}")
        end
        db.execute("CREATE VIRTUAL TABLE vec0_face USING vec0(face_embed float[512])")
      end
      [
        [ "apple_photos", "Apple Photos" ],
        [ "mounted_folder", "Mounted folder" ],
        [ "uploads", "Uploads" ]
      ].each do |kind, display_name|
        Source.find_or_create_by!(kind: kind) do |source|
          source.display_name = display_name
          source.status = "not_connected"
        end
      end
    end

    # Add more helper methods to be used by all tests here...
  end
end
