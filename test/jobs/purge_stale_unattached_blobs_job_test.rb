require "test_helper"

class PurgeStaleUnattachedBlobsJobTest < ActiveSupport::TestCase
  test "purges old unattached blobs and preserves recent or attached blobs" do
    now = Time.current
    stale_blob = create_blob("stale source audio")
    stale_blob.update_column(:created_at, 2.days.ago)
    recent_blob = create_blob("recent upload")
    attached_blob = create_blob("attached media")

    project = create_project(name: "Blob cleanup project")
    chat = create_chat(project)
    run = chat.runs.create!(project:, operation: "image", status: :succeeded, requested_by: "test")
    artifact = run.artifacts.build(kind: "image", name: "attached.png", metadata_json: {})
    artifact.media_file.attach(attached_blob)
    artifact.save!

    PurgeStaleUnattachedBlobsJob.perform_now(now)

    assert_not ActiveStorage::Blob.exists?(stale_blob.id)
    assert ActiveStorage::Blob.exists?(recent_blob.id)
    assert ActiveStorage::Blob.exists?(attached_blob.id)
    assert_equal "attached media", artifact.reload.media_file.download
  end

  private

  def create_blob(contents)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(contents),
      filename: "cleanup-test.txt",
      content_type: "text/plain",
      identify: false
    )
  end
end
