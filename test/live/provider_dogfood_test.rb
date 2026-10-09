require "test_helper"
require_relative "../support/dogfood_report"
require_relative "../support/live_acceptance_policy"
require_relative "../../script/diagnostics/support/openrouter_speech_probe"

# Opt-in live provider acceptance. Every scenario drives the same controllers,
# jobs and services as the application, against a real provider, and asserts
# on the durable records it leaves behind.
#
#   LIVE_DOGFOOD=1        free-model scenarios
#   LIVE_DOGFOOD_PAID=1   explicitly allow paid/manual scenarios
#
# Prefer `bin/dogfood`, which runs this file serially and prints a summary.
# Model choices can be overridden with the DOGFOOD_*_MODEL variables below.
class ProviderDogfoodTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include DogfoodReport::TestHelpers

  PROVIDER = ENV.fetch("DOGFOOD_PROVIDER", "openrouter")
  MODELS = {
    chat: ENV.fetch("DOGFOOD_CHAT_MODEL", "liquid/lfm-2.5-2.6b:free"),
    structured: ENV.fetch("DOGFOOD_STRUCTURED_MODEL", "liquid/lfm-2.5-2.6b:free"),
    structured_alt: ENV.fetch("DOGFOOD_STRUCTURED_ALT_MODEL", "nvidia/nemotron-3-super-120b-a12b:free"),
    tools: ENV.fetch("DOGFOOD_TOOLS_MODEL", "liquid/lfm-2.5-2.6b:free"),
    agent: ENV.fetch("DOGFOOD_AGENT_MODEL", ENV.fetch("DOGFOOD_CHAT_MODEL", "liquid/lfm-2.5-2.6b:free")),
    embedding: ENV.fetch("DOGFOOD_EMBEDDING_MODEL", "liquid/lfm-2.5-embedding-350m:free"),
    rerank: ENV.fetch("DOGFOOD_RERANK_MODEL", "nvidia/llama-nemotron-rerank-vl-1b-v2:free"),
    speech: ENV.fetch("DOGFOOD_SPEECH_MODEL", OpenRouterSpeechProbe::DEFAULT_MODEL),
    transcription: ENV.fetch("DOGFOOD_TRANSCRIPTION_MODEL", "mistralai/voxtral-mini-3b-2507"),
    image: ENV.fetch("DOGFOOD_IMAGE_MODEL", "black-forest-labs/flux.2-klein-4b")
  }.freeze
  SCENARIO_MODELS = {
    "chat_streaming" => [ :chat ],
    "structured_output" => [ :structured ],
    "tool_approval_continuation" => [ :tools ],
    "knowledge_embedding_and_rerank" => [ :embedding, :rerank ],
    "evaluation_comparison_with_judge" => [ :structured, :structured_alt ],
    "saved_agent_with_local_tool" => [ :agent ],
    "agent_with_hosted_web_search" => [ :agent ],
    "openrouter_free_speech" => [ :speech ],
    "transcription" => [ :chat, :transcription ],
    "image_generation" => [ :chat, :image ]
  }.freeze

  setup do
    skip "set LIVE_DOGFOOD=1 to run live provider dogfood" unless ENV["LIVE_DOGFOOD"] == "1"
    expected_profile = ENV["LIVE_DOGFOOD_PAID"] == "1" ? "integration" : "free"
    unless ENV["RUN_LIVE_AI"] == "1" && ENV["AI_TEST_PROFILE"] == expected_profile
      manual_skip "Use bin/dogfood or explicitly set RUN_LIVE_AI=1 and AI_TEST_PROFILE=#{expected_profile}."
    end
    request_models!(*SCENARIO_MODELS.fetch(name.delete_prefix("test_"), []))
    @live_policy = LiveAcceptancePolicy.new(provider: PROVIDER, models: MODELS)
    @live_policy.configure!

    @project = Project.create!(name: "Dogfood #{name.delete_prefix('test_').tr('_', ' ')}", description: "Live provider dogfood.")
  rescue LiveAcceptancePolicy::Unavailable => error
    manual_skip(error.message)
  end

  teardown do
    LiveAcceptancePolicy.active = nil if LiveAcceptancePolicy.active == @live_policy
  end

  test "chat_streaming" do
    require_models!(:chat)
    chat = create_chat(MODELS[:chat])

    run = post_message(chat, "Reply with exactly the words: workbench dogfood ok")

    assert run.succeeded?, run_failure(run)
    reply = chat.messages.where(role: "assistant").order(:id).last
    assert reply&.content.present?, "no assistant reply was persisted"
    assert run.attempts.first.time_to_first_output_ms.present?, "streaming did not record time to first output"
    note "assistant_message_persisted=true streaming_first_output_recorded=true"
  end

  test "structured_output" do
    require_models!(:structured)
    chat = create_chat(MODELS[:structured])
    experiment = @project.experiments.create!(
      name: "Structured dogfood",
      input_prompt: 'Return summary "live smoke" and confidence 0.5.',
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json),
      generation_options_json: { "max_output_tokens" => 1024 }
    )
    model = registry_model(MODELS[:structured])
    run = track_run(chat.runs.create!(
      project: @project,
      experiment: experiment,
      operation: "structured",
      status: :queued,
      requested_by: "dogfood",
      input_snapshot_json: {
        "experiment" => experiment.snapshot,
        "target" => { "provider" => model.provider, "model_id" => model.id, "name" => model.name }
      },
      app_version: "dogfood",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    ))
    run.attempts.create!(sequence: 1, provider: model.provider, model_id: model.id, status: :queued)

    StructuredResponseJob.perform_now(run.id)

    run.reload
    assert run.succeeded?, run_failure(run)
    assert_equal "valid", run.result_summary["schema_validation"]
    assert_equal "json", run.artifacts.first.kind
  end

  test "tool_approval_continuation" do
    require_models!(:tools)
    chat = create_chat(MODELS[:tools])

    run = post_message(chat, <<~PROMPT)
      Call the save_run_note tool exactly once with the note "dogfood approval check".
      After the tool result arrives, reply with the single word: saved
    PROMPT

    assert run.waiting_for_approval?, "expected an approval request; #{run_failure(run)}"
    invocation = run.tool_invocations.find_by!(tool_key: "save_run_note")

    perform_enqueued_jobs do
      patch project_chat_approval_path(@project, chat, invocation.approval),
        params: { approval: { decision: "approved", note: "Approved by live dogfood" } }
    end

    run.reload
    assert run.succeeded?, run_failure(run)
    assert invocation.reload.succeeded?
    assert run.artifacts.where(kind: "report").exists?, "approved note did not create a report Artifact"
  end

  test "knowledge_embedding_and_rerank" do
    require_models!(:embedding, :rerank)
    collection = @project.knowledge_collections.create!(name: "Dogfood corpus")
    {
      "Solid Queue" => "Solid Queue is a database-backed Active Job backend that runs recurring tasks and workers.",
      "Tomatoes" => "Tomatoes grow best in warm soil with full sun and regular watering.",
      "Turbo Streams" => "Turbo Streams deliver page changes over WebSockets as HTML fragments."
    }.each do |title, text|
      post project_knowledge_collection_items_path(@project, collection),
        params: { knowledge_item: { title:, source_reference: "dogfood", content_text: text } }
    end
    assert_equal 3, collection.knowledge_chunks.count

    untracked_cost_operations("embedding")
    summary = Ai::Knowledge::Embedder.call(collection:, model_id: MODELS[:embedding], provider: PROVIDER)
    assert_equal "ready", summary.status, summary.error.to_s
    note "embedded=#{summary.embedded} dims=#{summary.dimensions}"

    semantic = Ai::Knowledge::Search.call(collection: collection.reload, query: "background job processing in Rails", mode: "semantic")
    assert_equal "semantic", semantic.mode, semantic.degraded_reason.to_s
    note "semantic_results=#{semantic.results.size}"

    untracked_cost_operations("rerank")
    reranked = Ai::Knowledge::Search.call(
      collection:, query: "background job processing in Rails", mode: "hybrid",
      rerank: true, rerank_model_id: MODELS[:rerank]
    )
    assert reranked.rerank_applied, reranked.rerank_note.to_s
    note "rerank_results=#{reranked.results.size} rerank_applied=true"
  end

  test "evaluation_comparison_with_judge" do
    require_models!(:structured, :structured_alt)
    experiment = @project.experiments.create!(
      name: "Evaluation dogfood",
      input_prompt: "Summarize the input in at most five words and give your confidence from 0 to 1.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json),
      generation_options_json: { "max_output_tokens" => 2048 }
    )
    rubric = [ { "key" => "faithful", "description" => "The summary reflects the input without inventing facts." } ]
    dataset = @project.evaluation_datasets.create!(name: "Dogfood cases")
    dataset.create_revision!(
      [ "Rails ships Solid Queue by default." ]
        .each_with_index.map do |prompt, index|
          { "key" => "case-#{index + 1}", "input" => { "prompt" => prompt }, "expected_output" => { "summary" => prompt, "confidence" => 1 }, "rubric" => rubric }
        end
    )
    references = [ MODELS[:structured], MODELS[:structured_alt] ].map { |model_id| "#{PROVIDER}|#{model_id}" }

    perform_enqueued_jobs do
      post project_evaluation_dataset_executions_path(@project, dataset), params: {
        execution: { experiment_id: experiment.id, model_references: references, judge_model_reference: references.first }
      }
    end

    comparison = dataset.evaluation_comparisons.order(:id).last
    assert comparison, flash[:alert].to_s
    results = comparison.evaluation_executions.flat_map(&:evaluation_case_results)
    assert_equal 2, results.size
    results.each { |result| track_run(result.run) if result.run }
    results.filter_map(&:evaluation_case_judgment).each { |judgment| track_run(judgment.run) }

    comparison.evaluation_executions.each do |execution|
      execution.reload
      rows = execution.evaluation_case_results
      note "#{execution.model_id}: status=#{execution.status} received=#{rows.count(&:transport_status_received?)}/1 valid=#{rows.count(&:schema_status_valid?)}/1"
    end
    results.each do |result|
      result.reload
      attempt = result.run&.attempts&.order(:sequence)&.last
      note "case_model=#{result.evaluation_execution.model_id} schema=#{result.schema_status} finish=#{attempt&.finish_reason} error=#{attempt&.error_class}"
      assert result.completed?, "case #{result.case_key} did not complete: #{result.status}; #{run_failure(result.run)}"
      assert result.transport_status_received?, "case #{result.case_key} did not receive a response"
      assert result.schema_status_valid?, "case #{result.case_key} did not receive schema-valid output"
      assert result.run.succeeded?, run_failure(result.run)
    end
    judgments = results.filter_map(&:evaluation_case_judgment)
    assert_equal 2, judgments.size, "each completed case must have an intended judgment"
    note "judgments=#{judgments.map(&:status).tally}"
    judgments.each do |judgment|
      assert_equal "completed", judgment.reload.status
      assert judgment.run.succeeded?, run_failure(judgment.run)
    end
  end

  test "openrouter_free_speech" do
    require_models!(:speech)
    # A saved assistant fixture avoids an unrelated chat inference request.
    chat = create_chat(MODELS[:chat])
    message = chat.messages.create!(role: "assistant", content: OpenRouterSpeechProbe::TEXT)
    observed_speech = nil
    statuses = []
    speech_listener = ->(*args) { observed_speech = args.last[:result] }
    request_listener = lambda do |*args|
      payload = args.last
      statuses << payload[:status] if payload[:method].to_s == "post"
    end

    ActiveSupport::Notifications.subscribed(speech_listener, "speech.ruby_llm") do
      ActiveSupport::Notifications.subscribed(request_listener, "request.ruby_llm") do
        perform_enqueued_jobs do
          post project_chat_message_speech_run_path(@project, chat, message), params: {
            speech_run: { model_reference: "#{PROVIDER}|#{MODELS[:speech]}", voice: ENV["DOGFOOD_SPEECH_VOICE"] }
          }
        end
      end
    end

    assert_response :see_other
    run = track_run(chat.runs.where(operation: "speech").order(:id).last)
    assert run&.succeeded?, run_failure(run)
    assert_instance_of RubyLLM::Speech, observed_speech
    assert_equal MODELS[:speech], observed_speech.model
    assert_equal "mp3", observed_speech.format
    assert_equal [ 200 ], statuses, "expected exactly one successful speech POST"
    artifact = run.artifacts.find_by!(kind: "audio")
    audio = artifact.audio_file
    assert audio.attached?
    data = audio.download.b
    assert OpenRouterSpeechProbe.validate_mp3!(data:, mime_type: audio.content_type)
    assert_equal observed_speech.to_blob, data
    assert_equal Digest::SHA256.hexdigest(data), artifact.metadata_json.fetch("sha256")

    get run_path(run)
    assert_response :success
    assert_select "audio[controls]"
    assert_select "a", text: "Download"
    note "ruby_llm_speech_object=true http_status=200 mp3_signature=true attachment=#{data.bytesize}B playback_controls=true"
    note "MIME here is RubyLLM-derived; raw REST probe records the independent HTTP MIME. Audio quality/listening remains manual."
  end

  test "local_speech" do
    manual_skip "Local TTS acceptance is pending the local provider adapter and API configuration."
  end

  test "transcription" do
    request_models!(:chat, :transcription)
    skip_unless_paid
    require_models!(:chat, :transcription)
    fixture_path = ENV["DOGFOOD_TRANSCRIPTION_FILE"].to_s
    manual_skip "Transcription requires a short local DOGFOOD_TRANSCRIPTION_FILE for manual acceptance." unless File.file?(fixture_path)
    chat = create_chat(MODELS[:chat])
    content_type = Rack::Mime.mime_type(File.extname(fixture_path), "application/octet-stream")
    perform_enqueued_jobs do
      post project_chat_transcription_runs_path(@project, chat), params: {
        transcription_run: {
          audio_file: Rack::Test::UploadedFile.new(fixture_path, content_type),
          model_reference: "#{PROVIDER}|#{MODELS[:transcription]}"
        }
      }
    end
    transcription_run = track_run(chat.runs.where(operation: "transcription").order(:id).last)
    assert transcription_run&.succeeded?, run_failure(transcription_run)
    transcript = transcription_run.artifacts.find_by!(kind: "transcript").content_text
    assert transcript.present?, "no transcript was persisted"
    note "transcript_persisted=true"
  end

  test "saved_agent_with_local_tool" do
    require_models!(:agent)
    Ai::ToolRegistry.sync_project!(@project)
    model = registry_model(MODELS[:agent])
    definition = @project.agent_definitions.create!(
      name: "Local tool dogfood",
      provider: model.provider,
      model_id: model.id,
      instructions: "Call project_snapshot once, then return a short final answer. Do not call any other tools.",
      tool_keys: [ "project_snapshot" ],
      provider_tools: [],
      options: { max_output_tokens: 2048 }
    )
    run = track_run(Ai::AgentRunExecutor.enqueue(
      agent_definition: definition,
      prompt: "Call project_snapshot to inspect this project's non-secret summary, then confirm that the tool completed.",
      requested_by: "dogfood"
    ))
    delivery = run.agent_run_deliveries.find_by!(intent: "execute")
    perform_enqueued_jobs { AgentRunJob.perform_later(*delivery.job_arguments) }

    run.reload
    assert run.succeeded?, run_failure(run)
    assert run.tool_invocations.find_by!(tool_key: "project_snapshot").succeeded?
    report = run.artifacts.where(kind: "report").find do |artifact|
      artifact.metadata_json["report_type"] == Ai::AgentResearchReportRecorder::REPORT_TYPE
    end
    assert report, "no Agent report Artifact was persisted"
    assert report.content_text.present?, "Agent report has no final answer"
    assert_empty run.input_snapshot.fetch("provider_tools")
    note "local_tool_completed=true report_persisted=true steps=#{run.result_summary['agent_step_count']}"
  end

  test "agent_with_hosted_web_search" do
    request_models!(:agent)
    skip_unless_paid
    require_models!(:agent)
    Ai::ToolRegistry.sync_project!(@project)
    model = registry_model(MODELS[:agent])
    definition = @project.agent_definitions.create!(
      name: "Hosted search dogfood",
      provider: model.provider,
      model_id: model.id,
      instructions: "Use the available tools as requested, then answer concisely with source citations.",
      tool_keys: [ "project_snapshot" ],
      provider_tools: [ "web_search" ],
      options: { max_output_tokens: 2048 }
    )
    run = track_run(Ai::AgentRunExecutor.enqueue(agent_definition: definition, prompt: <<~PROMPT))
      First call project_snapshot to inspect this project's non-secret summary.
      Then use web_search to find the official RubyLLM documentation for its
      text-to-speech API. Cite the official page and state the method name.
    PROMPT
    delivery = run.agent_run_deliveries.find_by!(intent: "execute")

    perform_enqueued_jobs { AgentRunJob.perform_later(*delivery.job_arguments) }

    run.reload
    run.chat.messages.order(:id).each do |message|
      note "#{message.role}: tools=#{message.ruby_llm_tool_calls.map(&:name).join(',')} server_tools=#{Array(message.server_tool_calls).size} citations=#{message.citations.size}"
    end
    note "finish_reasons=#{run.attempts.order(:sequence).pluck(:finish_reason).join(',')}"
    assert run.succeeded?, run_failure(run)
    summary = run.result_summary
    searches = summary.dig("provider_tool_usage", "web_search_requests").to_i + summary["provider_tool_step_count"].to_i
    note "steps=#{summary['agent_step_count']} searches=#{searches} citations=#{summary['citation_count']}"
    assert_operator searches, :>, 0, "the provider reported no hosted search"
    assert run.tool_invocations.find_by!(tool_key: "project_snapshot").succeeded?
    assert run.artifacts.where(kind: "report").exists?, "no research report Artifact"
    assert run.artifacts.where(kind: "citation_set").exists?, "the model did not return citations"
  end

  test "image_generation" do
    request_models!(:chat, :image)
    skip_unless_paid
    require_models!(:chat, :image)
    chat = create_chat(MODELS[:chat])

    perform_enqueued_jobs do
      post project_chat_image_runs_path(@project, chat), params: {
        image_run: { prompt: "A small paper boat on a calm blue lake, flat illustration", model_reference: "#{PROVIDER}|#{MODELS[:image]}" }
      }
    end

    run = track_run(chat.runs.where(operation: "image").order(:id).last)
    assert run&.succeeded?, run_failure(run)
    image = run.artifacts.find_by!(kind: "image").media_file
    assert image.attached?
    assert_match %r{\Aimage/}, image.content_type
    note "image=#{image.content_type} #{image.byte_size}B cost_status=#{run.cost_status}"
  end

  private

  def skip_unless_paid
    manual_skip "This paid capability needs manual acceptance with LIVE_DOGFOOD_PAID=1." unless ENV["LIVE_DOGFOOD_PAID"] == "1"
  end

  def request_models!(*keys)
    keys.each { |key| request_model("#{PROVIDER}/#{MODELS.fetch(key)}") }
  end

  def require_models!(*keys)
    request_models!(*keys)
    @live_policy.check!(*keys)
  rescue LiveAcceptancePolicy::Unavailable => error
    manual_skip(error.message)
  end

  def manual_skip(reason)
    @dogfood_skip_reason = Ai::ErrorText.safe(reason.to_s, limit: 300)
    skip "Manual acceptance: #{@dogfood_skip_reason}"
  end

  def registry_model(model_id)
    RubyLLM.models.find(model_id, provider: PROVIDER)
  end

  def create_chat(model_id)
    post project_chats_path(@project), params: { chat: { title: "Dogfood chat", model: "#{PROVIDER}|#{model_id}" } }
    @project.chats.order(:id).last || flunk("chat was not created for #{model_id}")
  end

  def post_message(chat, content)
    perform_enqueued_jobs do
      post project_chat_messages_path(@project, chat), params: { message: { content: } }
    end
    track_run(chat.runs.order(:id).last.reload)
  end

  def run_failure(run)
    return "no Run was created" unless run

    run.reload
    attempt = run.attempts.order(:sequence).last
    "Run ##{run.id} #{run.status}: #{run.error_summary} #{attempt&.error_class} #{attempt&.error_message.to_s.truncate(200)}"
  end
end
