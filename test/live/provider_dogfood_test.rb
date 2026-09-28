require "test_helper"
require_relative "../support/dogfood_report"

# Opt-in live provider acceptance. Every scenario drives the same controllers,
# jobs and services as the application, against a real provider, and asserts
# on the durable records it leaves behind.
#
#   LIVE_DOGFOOD=1        free-model scenarios
#   LIVE_DOGFOOD_PAID=1   also run scenarios that cost money (a few cents total)
#
# Prefer `bin/dogfood`, which runs this file serially and prints a summary.
# Model choices can be overridden with the DOGFOOD_*_MODEL variables below.
class ProviderDogfoodTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include DogfoodReport::TestHelpers

  PROVIDER = ENV.fetch("DOGFOOD_PROVIDER", "openrouter")
  MODELS = {
    chat: ENV.fetch("DOGFOOD_CHAT_MODEL", "nvidia/nemotron-3-super-120b-a12b:free"),
    structured: ENV.fetch("DOGFOOD_STRUCTURED_MODEL", "nvidia/nemotron-3-super-120b-a12b:free"),
    structured_alt: ENV.fetch("DOGFOOD_STRUCTURED_ALT_MODEL", "dots-studio/dots-3-note-preview:free"),
    tools: ENV.fetch("DOGFOOD_TOOLS_MODEL", "nvidia/nemotron-3-super-120b-a12b:free"),
    agent: ENV.fetch("DOGFOOD_AGENT_MODEL", "openai/gpt-5-nano"),
    embedding: ENV.fetch("DOGFOOD_EMBEDDING_MODEL", "liquid/lfm-2.5-embedding-350m:free"),
    rerank: ENV.fetch("DOGFOOD_RERANK_MODEL", "nvidia/llama-nemotron-rerank-vl-1b-v2:free"),
    speech: ENV.fetch("DOGFOOD_SPEECH_MODEL", "deepgram/flux-tts:free"),
    speech_voice: ENV.fetch("DOGFOOD_SPEECH_VOICE", "flux-bree-en"),
    transcription: ENV.fetch("DOGFOOD_TRANSCRIPTION_MODEL", "mistralai/voxtral-mini-3b-2507"),
    image: ENV.fetch("DOGFOOD_IMAGE_MODEL", "black-forest-labs/flux.2-klein-4b")
  }.freeze

  setup do
    skip "set LIVE_DOGFOOD=1 to run live provider dogfood" if ENV["LIVE_DOGFOOD"].blank?
    skip "#{PROVIDER} is not configured" unless RubyLLM::Provider.resolve(PROVIDER).configured?(RubyLLM.config)

    @project = Project.create!(name: "Dogfood #{name.delete_prefix('test_').tr('_', ' ')}", description: "Live provider dogfood.")
  end

  test "chat_streaming" do
    chat = create_chat(MODELS[:chat])

    run = post_message(chat, "Reply with exactly the words: workbench dogfood ok")

    assert run.succeeded?, run_failure(run)
    reply = chat.messages.where(role: "assistant").order(:id).last
    assert reply&.content.present?, "no assistant reply was persisted"
    assert run.attempts.first.time_to_first_output_ms.present?, "streaming did not record time to first output"
    note "reply=#{reply.content.squish.truncate(60)}"
  end

  test "structured_output" do
    chat = create_chat(MODELS[:structured])
    experiment = @project.experiments.create!(
      name: "Structured dogfood",
      input_prompt: 'Return summary "live smoke" and confidence 0.5.',
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
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

    summary = Ai::Knowledge::Embedder.call(collection:, model_id: MODELS[:embedding], provider: PROVIDER)
    assert_equal "ready", summary.status, summary.error.to_s
    note "embedded=#{summary.embedded} dims=#{summary.dimensions}"

    semantic = Ai::Knowledge::Search.call(collection: collection.reload, query: "background job processing in Rails", mode: "semantic")
    assert_equal "semantic", semantic.mode, semantic.degraded_reason.to_s
    note "semantic_top=#{semantic.results.first&.chunk&.knowledge_item&.title}"

    reranked = Ai::Knowledge::Search.call(
      collection:, query: "background job processing in Rails", mode: "hybrid",
      rerank: true, rerank_model_id: MODELS[:rerank]
    )
    assert reranked.rerank_applied, reranked.rerank_note.to_s
    note "rerank_top=#{reranked.results.first&.chunk&.knowledge_item&.title}"
  end

  test "evaluation_comparison_with_judge" do
    experiment = @project.experiments.create!(
      name: "Evaluation dogfood",
      input_prompt: "Summarize the input in at most five words and give your confidence from 0 to 1.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    rubric = [ { "key" => "faithful", "description" => "The summary reflects the input without inventing facts." } ]
    dataset = @project.evaluation_datasets.create!(name: "Dogfood cases")
    dataset.create_revision!(
      [ "Rails ships Solid Queue by default.", "SQLite works well for single-user apps.", "Turbo updates pages without full reloads." ]
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
    assert_equal 6, results.size
    results.each { |result| track_run(result.run) if result.run }
    results.filter_map(&:evaluation_case_judgment).each { |judgment| track_run(judgment.run) }

    comparison.evaluation_executions.each do |execution|
      execution.reload
      rows = execution.evaluation_case_results
      note "#{execution.model_id}: status=#{execution.status} received=#{rows.count(&:transport_status_received?)}/3 valid=#{rows.count(&:schema_status_valid?)}/3"
    end
    assert results.all? { |result| %w[completed failed].include?(result.reload.status) }, "cases left unfinished"
    assert results.any?(&:schema_status_valid?), "no model produced a schema-valid answer"
    judgments = results.filter_map(&:evaluation_case_judgment)
    note "judgments=#{judgments.map(&:status).tally}"
    assert judgments.any? { |judgment| judgment.status == "completed" }, "no rubric judgment completed"
  end

  test "speech_and_transcription_round_trip" do
    speech_model = registry_model(MODELS[:speech])
    chat = create_chat(MODELS[:chat])
    message = chat.messages.create!(role: "assistant", content: "The workbench records every provider call.")

    perform_enqueued_jobs do
      post project_chat_message_speech_run_path(@project, chat, message),
        params: { speech_run: { model_reference: "#{speech_model.provider}|#{speech_model.id}", voice: MODELS[:speech_voice] } }
    end
    speech_run = track_run(chat.runs.where(operation: "speech").order(:id).last)
    assert speech_run&.succeeded?, run_failure(speech_run)
    audio = speech_run.artifacts.find_by!(kind: "audio").audio_file
    assert audio.attached?
    note "audio=#{audio.content_type} #{audio.byte_size}B"

    skip_unless_paid
    extension = Rack::Mime::MIME_TYPES.invert[audio.content_type] || ".mp3"
    Tempfile.create([ "dogfood-speech", extension ], binmode: true) do |file|
      file.write(audio.download)
      file.rewind
      perform_enqueued_jobs do
        post project_chat_transcription_runs_path(@project, chat), params: {
          transcription_run: {
            audio_file: Rack::Test::UploadedFile.new(file.path, audio.content_type),
            model_reference: "#{PROVIDER}|#{MODELS[:transcription]}"
          }
        }
      end
    end
    transcription_run = track_run(chat.runs.where(operation: "transcription").order(:id).last)
    assert transcription_run&.succeeded?, run_failure(transcription_run)
    transcript = transcription_run.artifacts.find_by!(kind: "transcript").content_text
    note "transcript=#{transcript.squish.truncate(80)}"
    assert_match(/workbench|provider/i, transcript)
  end

  test "agent_with_hosted_web_search" do
    skip_unless_paid
    Ai::ToolRegistry.sync_project!(@project)
    model = registry_model(MODELS[:agent])
    definition = @project.agent_definitions.create!(
      name: "Hosted search dogfood",
      provider: model.provider,
      model_id: model.id,
      instructions: "Use the available tools as requested, then answer concisely with source citations.",
      tool_keys: [ "project_snapshot" ],
      provider_tools: [ "web_search" ],
      options: { max_output_tokens: 4096 }
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
      note "answer=#{message.content.to_s.squish.truncate(160)}" if message.role == "assistant" && message.content.present?
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
    skip_unless_paid
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
    skip "set LIVE_DOGFOOD_PAID=1 to run paid scenarios" if ENV["LIVE_DOGFOOD_PAID"].blank?
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
