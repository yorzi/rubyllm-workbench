require "test_helper"
require "ostruct"
require "tempfile"

class Ai::EvaluationCaseAttachmentBoundaryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  AcceptedEnqueue = Data.define do
    def successfully_enqueued?
      true
    end
  end

  setup do
    @upload_tempfiles = []
    @project = create_project(name: "Attachment boundary project")
    @experiment = @project.experiments.create!(
      name: "Attachment boundary schema",
      input_prompt: "Use only the supplied structured input.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    @dataset = @project.evaluation_datasets.create!(name: "Attachment boundary cases")
    @revision = @dataset.create_revision!(
      [ { "key" => "case-1", "input" => { "question" => "input-sentinel" }, "expected_output" => { "answer" => "local-only" } } ],
      uploads_by_case_key: { "case-1" => [ upload_file ] }
    )
  end

  test "individual prompts exclude attachment names, bytes, IDs and checksums" do
    model = RubyLLM.models.chat_models.all.find { |candidate| candidate.supports?(:structured_output) }
    skip "RubyLLM registry has no structured-output model" unless model

    execution = enqueue_without_provider(model, execution_mode: "individual")

    assert_attachment_prompt_boundary(execution)
  end

  test "provider Batch prompts exclude attachment names, bytes, IDs and checksums" do
    model = RubyLLM.models.chat_models.all.find do |candidate|
      candidate.supports?(:structured_output) && candidate.supports?(:batch) && !candidate.id.to_s.end_with?(":batch")
    end
    skip "RubyLLM registry has no structured-output model with Batch support" unless model

    execution = enqueue_without_provider(model, execution_mode: "provider_batch")

    assert_attachment_prompt_boundary(execution)
  end

  private

  def enqueue_without_provider(model, execution_mode:)
    requirements = RubyLLM::Provider.resolve(model.provider).configuration_requirements
    catalog = Ai::ModelCatalog.new(
      models: [ model ],
      config: OpenStruct.new(requirements.to_h { |requirement| [ requirement, "test-only-key" ] })
    )
    job_class = execution_mode == "provider_batch" ? EvaluationBatchSubmissionJob : EvaluationCaseJob
    execution = nil

    with_provider_configuration(model.provider) do
      with_singleton_method_stub(job_class, :perform_later, ->(*) { AcceptedEnqueue.new }) do
        execution = Ai::EvaluationExecutor.enqueue(
          dataset: @dataset,
          experiment: @experiment,
          model_reference: "#{model.provider}|#{model.id}",
          execution_mode:,
          model_catalog: catalog
        )
      end
    end
    execution
  end

  def assert_attachment_prompt_boundary(execution)
    run = execution.runs.sole
    prompt = run.input_snapshot.dig("experiment", "input_prompt")
    attachment = @revision.case_attachments.sole
    blob = attachment.file.blob

    assert_includes prompt, "input-sentinel"
    refute_includes prompt, "provider-boundary-secret-filename.txt"
    refute_includes prompt, "provider-boundary-file-bytes"
    refute_includes prompt, attachment.id.to_s
    refute_includes prompt, blob.id.to_s
    refute_includes prompt, blob.checksum

    metadata = run.input_snapshot.dig("evaluation", "attachments").sole
    assert_equal attachment.id, metadata.fetch("id")
    assert_equal "provider-boundary-secret-filename.txt", metadata.fetch("filename")
    assert_equal blob.checksum, metadata.fetch("checksum")
    assert_equal [ metadata ], execution.input_snapshot.dig("dataset", "cases").sole.fetch("attachments")
  end

  def upload_file
    tempfile = Tempfile.new([ "provider-boundary", ".txt" ])
    tempfile.write("provider-boundary-file-bytes")
    tempfile.rewind
    @upload_tempfiles << tempfile
    ActionDispatch::Http::UploadedFile.new(
      tempfile:,
      filename: "provider-boundary-secret-filename.txt",
      type: "text/plain"
    )
  end

  def with_singleton_method_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  def teardown
    super
    @upload_tempfiles&.each { |tempfile| tempfile.close! if tempfile.respond_to?(:close!) }
  end
end
