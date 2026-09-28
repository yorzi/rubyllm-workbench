require "test_helper"
require "tempfile"

class EvaluationCaseAttachmentsTest < ActionDispatch::IntegrationTest
  setup do
    @upload_tempfiles = []
    @project = create_project(name: "Evaluation attachment project")
    @dataset = @project.evaluation_datasets.create!(name: "Attachment cases")
    @first_revision = @dataset.create_revision!([ evaluation_case ])
  end

  test "upload creates a new immutable revision and exposes a project-scoped download" do
    post project_evaluation_dataset_case_attachments_path(@project, @dataset), params: {
      evaluation_case_attachment: { case_key: "case-1", files: [ upload_file ] }
    }

    assert_response :see_other
    @dataset.reload
    attachment_revision = @dataset.current_revision_record
    attachment = attachment_revision.case_attachments.sole

    assert_equal 2, attachment_revision.revision
    assert_empty @first_revision.case_attachments
    assert_equal "case-1", attachment.case_key
    assert_equal "review material: file-content-secret", attachment.file.download
    assert_response_notice_revision(2)

    get project_evaluation_dataset_revision_case_attachment_path(@project, @dataset, attachment_revision, attachment)

    assert_response :success
    assert_equal "review material: file-content-secret", response.body
    assert_match(/attachment;.*case-evidence\.txt/, response.headers.fetch("Content-Disposition"))

    get project_evaluation_dataset_path(@project, @dataset)
    assert_response :success
    assert_includes response.body, "case-evidence.txt"
    assert_includes response.body, "Add files as new revision"
    assert_includes response.body, "not sent to providers"
  end

  test "removal creates a new revision while earlier revisions retain the file" do
    attached_revision = @dataset.create_revision!([ evaluation_case ], uploads_by_case_key: { "case-1" => [ upload_file ] })
    attachment = attached_revision.case_attachments.sole
    blob_id = attachment.file.blob.id

    delete project_evaluation_dataset_case_attachment_path(@project, @dataset, attachment)

    assert_response :see_other
    current_revision = @dataset.reload.current_revision_record
    assert_equal 3, current_revision.revision
    assert_empty current_revision.case_attachments
    assert_equal [ attachment.id ], attached_revision.reload.case_attachments.pluck(:id)
    assert ActiveStorage::Blob.exists?(blob_id)

    get project_evaluation_dataset_revision_case_attachment_path(@project, @dataset, attached_revision, attachment)

    assert_response :success
    assert_equal "review material: file-content-secret", response.body
  end

  test "rejects uploads with unsupported types, excess size or excess per-case count" do
    invalid_type = direct_upload_file(
      filename: "unknown.gif",
      contents: "GIF89a unsupported image format",
      content_type: "image/gif"
    )
    error = assert_raises(ActiveRecord::RecordInvalid) do
      @dataset.create_revision!([ evaluation_case ], uploads_by_case_key: { "case-1" => [ invalid_type ] })
    end

    assert_includes error.record.errors.full_messages.join(" "), "one of:"
    assert_equal 1, @dataset.reload.current_revision

    oversized = Struct.new(:original_filename, :size).new(
      "too-large.txt",
      EvaluationDatasetCaseAttachment::MAX_FILE_BYTES + 1
    )
    error = assert_raises(ActiveRecord::RecordInvalid) do
      @dataset.create_revision!([ evaluation_case ], uploads_by_case_key: { "case-1" => [ oversized ] })
    end

    assert_includes error.record.errors.full_messages.join(" "), "10 MB or smaller"
    assert_equal 1, @dataset.reload.current_revision

    post_upload(Array.new(EvaluationDatasetCaseAttachment::MAX_FILES_PER_CASE) { |index| upload_file(filename: "case-#{index}.txt") })

    assert_response :see_other
    assert_equal 2, @dataset.reload.current_revision
    error = assert_raises(ActiveRecord::RecordInvalid) do
      @dataset.create_revision!(
        @dataset.current_revision_record.cases,
        uploads_by_case_key: { "case-1" => [ direct_upload_file(filename: "sixth.txt", contents: "extra file", content_type: "text/plain") ] }
      )
    end

    assert_includes error.record.errors.full_messages.join(" "), "at most 5 files"
    assert_equal 2, @dataset.reload.current_revision
  end

  test "upload and download routes reject records outside the project dataset" do
    other_project = create_project(name: "Other attachment project")
    other_dataset = other_project.evaluation_datasets.create!(name: "Other attachment cases")
    other_revision = other_dataset.create_revision!([ evaluation_case ])
    other_revision = other_dataset.create_revision!(
      [ evaluation_case ], uploads_by_case_key: { "case-1" => [ upload_file ] }
    )
    foreign_attachment = other_revision.case_attachments.sole

    get project_evaluation_dataset_revision_case_attachment_path(@project, @dataset, other_revision, foreign_attachment)
    assert_response :not_found

    delete project_evaluation_dataset_case_attachment_path(@project, @dataset, foreign_attachment)
    assert_response :see_other
    assert_equal 1, @dataset.reload.current_revision
    assert_equal 2, other_dataset.reload.current_revision
  end

  test "project deletion removes attachment records and purges their blobs" do
    revision = @dataset.create_revision!([ evaluation_case ], uploads_by_case_key: { "case-1" => [ upload_file ] })
    attachment = revision.case_attachments.sole
    blob_id = attachment.file.blob.id

    perform_enqueued_jobs { @project.destroy! }

    refute EvaluationDatasetCaseAttachment.exists?(attachment.id)
    refute ActiveStorage::Attachment.exists?(record_type: "EvaluationDatasetCaseAttachment", record_id: attachment.id)
    refute ActiveStorage::Blob.exists?(blob_id)
  end

  test "stale attachment forms cannot overwrite a newer case revision" do
    stale_revision = @dataset.current_revision_record
    @dataset.create_revision!([ evaluation_case.merge("input" => { "question" => "newer revision" }) ])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      @dataset.create_revision!(
        stale_revision.cases,
        uploads_by_case_key: { "case-1" => [ direct_upload_file(filename: "stale.txt", contents: "stale upload", content_type: "text/plain") ] },
        base_revision_id: stale_revision.id
      )
    end

    assert_includes error.record.errors.full_messages.join(" "), "dataset changed"
    assert_equal 2, @dataset.reload.current_revision
    assert_equal "newer revision", @dataset.current_revision_record.cases.first.dig("input", "question")
    assert_empty @dataset.current_revision_record.case_attachments
  end

  private

  def evaluation_case
    { "key" => "case-1", "input" => { "question" => "sample" }, "expected_output" => { "answer" => "sample" } }
  end

  def post_upload(files)
    post project_evaluation_dataset_case_attachments_path(@project, @dataset), params: {
      evaluation_case_attachment: { case_key: "case-1", files: Array(files) }
    }
  end

  def upload_file(filename: "case-evidence.txt", contents: "review material: file-content-secret", content_type: "text/plain")
    upload = Rack::Test::UploadedFile.new(
      StringIO.new(contents),
      content_type,
      true,
      original_filename: filename
    )
    @upload_tempfiles << upload.tempfile
    upload
  end

  def direct_upload_file(filename:, contents:, content_type:)
    tempfile = Tempfile.new([ "evaluation-case-attachment", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(contents)
    tempfile.rewind
    @upload_tempfiles << tempfile
    ActionDispatch::Http::UploadedFile.new(tempfile:, filename:, type: content_type)
  end

  def teardown
    super
    @upload_tempfiles&.each { |tempfile| tempfile.close if tempfile.respond_to?(:close) && !tempfile.closed? }
  end

  def assert_response_notice_revision(number)
    assert_equal number, @dataset.current_revision
  end
end
