require "test_helper"

class ImportJobTest < ActiveSupport::TestCase
  test "import failure does not delete apple photos originals" do
    path = File.join(PICS_LIBRARY, "apple-photos", "original.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "original bytes")
    job = Job.create!(kind: "import", params: { paths: [ path ] }.to_json)
    original = AssetImporter.method(:import)
    AssetImporter.define_singleton_method(:import) { |*| raise "worker failed" }

    ImportJob.perform_now(job_id: job.id, path: path, index: 0, total: 1)

    assert File.file?(path)
    assert_equal "error", job.reload.status
  ensure
    AssetImporter.define_singleton_method(:import, original) if original
    FileUtils.rm_f(path)
  end

  test "import failure deletes uploads originals" do
    path = File.join(PICS_LIBRARY, "imports", "upload.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "upload bytes")
    job = Job.create!(kind: "import", params: { paths: [ path ] }.to_json)
    original = AssetImporter.method(:import)
    AssetImporter.define_singleton_method(:import) { |*| raise "worker failed" }

    ImportJob.perform_now(job_id: job.id, path: path, index: 0, total: 1)

    assert_not File.exist?(path)
    assert_equal "error", job.reload.status
  ensure
    AssetImporter.define_singleton_method(:import, original) if original
    FileUtils.rm_f(path)
  end
end
