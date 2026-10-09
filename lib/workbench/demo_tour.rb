module Workbench
  # Builds a "Demo tour" Project of synthetic, already-finished records so the
  # workbench can be explored without provider keys. No provider is called.
  # Every Run is marked requested_by "demo" and says it is synthetic.
  #
  #   bin/rails workbench:demo          # create or rebuild the tour
  #   bin/rails workbench:demo:remove   # delete it
  class DemoTour
    PROJECT_SLUG = "demo-tour".freeze
    REQUESTED_BY = "demo".freeze
    SYNTHETIC_NOTE = "Synthetic demo record: no provider was called.".freeze
    PREFERRED_MODELS = [
      [ "openrouter", "openai/gpt-5-nano" ],
      [ "openai", "gpt-5-nano" ],
      [ "anthropic", "claude-haiku-4-5" ]
    ].freeze

    def self.build!
      new.build!
    end

    def self.remove!
      Project.find_by(slug: PROJECT_SLUG)&.destroy!
    end

    def build!
      self.class.remove!
      ActiveRecord::Base.transaction do
        @project = Project.create!(
          name: "Demo tour",
          slug: PROJECT_SLUG,
          description: "Synthetic records for exploring the workbench without provider keys. Delete with bin/rails workbench:demo:remove."
        )
        Ai::ToolRegistry.sync_project!(@project)
        chat_run
        structured_run
        approved_tool_run
        agent_run
        failed_run
        knowledge_collection
        evaluation_dataset
      end
      @project
    end

    private

    def model
      @model ||= begin
        catalog = Ai::ModelCatalog.new
        preferred = PREFERRED_MODELS.lazy.filter_map do |provider, id|
          catalog.find!(id, provider:)
        rescue RubyLLM::ModelNotFoundError
          nil
        end.first
        preferred || RubyLLM.models.chat_models.find { |candidate| candidate.supports?(:function_calling) }
      end
    end

    def new_chat(title, target_model: model)
      chat = @project.chats.new(title:)
      chat.model = target_model
      chat.save!
      chat
    end

    # Synthetic Runs start and finish instantly; spread their timestamps so the
    # inspector shows plausible duration and first-output figures.
    def settle(run, seconds: 2.4)
      finished = run.reload.finished_at || Time.current
      run.update_columns(started_at: finished - seconds, time_to_first_output_ms: 420)
    end

    def new_run(chat, operation:, input:, experiment: nil)
      chat.runs.create!(
        project: @project,
        experiment:,
        operation:,
        status: :queued,
        requested_by: REQUESTED_BY,
        input_snapshot_json: input.merge("demo_note" => SYNTHETIC_NOTE),
        app_version: "demo",
        ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
      )
    end

    def attempt_for(run, sequence: 1, input_tokens: 120, output_tokens: 48, status: :succeeded, finish_reason: "stop", target_model: model)
      now = Time.current
      run.attempts.create!(
        sequence:, provider: target_model.provider.to_s, model_id: target_model.id, status:,
        input_tokens:, output_tokens:, estimated_cost: ((input_tokens * 0.05) + (output_tokens * 0.4)) / 1_000_000,
        cost_status: "estimated", currency: "USD", finish_reason:,
        started_at: now - 2.seconds, finished_at: now, duration_ms: 1_850, time_to_first_output_ms: 420
      )
    end

    def chat_run
      chat = new_chat("Explain a Run")
      prompt = "In two sentences, what does the workbench record for each provider call?"
      run = new_run(chat, operation: "chat", input: { "prompt" => prompt, "tools" => [], "provider_tools" => [] })
      run.start!
      chat.messages.create!(role: "user", content: prompt)
      reply = chat.messages.create!(role: "assistant", content: "Each call becomes a Run with one or more Attempts that keep the model, token usage, cost and timing. Tool calls, approvals and generated Artifacts are stored alongside it so the call can be inspected later.")
      attempt_for(run)
      run.succeed!("finish_reason" => "stop", "message_id" => reply.id, "partial_output" => reply.content)
      settle(run)
    end

    def structured_run
      experiment = @project.experiments.create!(
        name: "Summarize with a schema",
        input_prompt: "Summarize: Solid Queue stores jobs in the database. Return a summary and a confidence.",
        schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
      )
      chat = new_chat("Structured output")
      run = new_run(chat, operation: "structured", experiment:, input: {
        "experiment" => experiment.snapshot,
        "target" => { "provider" => model.provider.to_s, "model_id" => model.id, "name" => model.name }
      })
      run.start!
      attempt = attempt_for(run, output_tokens: 22)
      output = { "summary" => "Solid Queue keeps jobs in the database.", "confidence" => 0.9 }
      run.artifacts.create!(attempt:, kind: "json", name: "Structured output", content_json: output, content_text: JSON.pretty_generate(output))
      run.succeed!("schema_validation" => "valid")
      settle(run, seconds: 1.9)
    end

    def approved_tool_run
      chat = new_chat("Tool approval")
      prompt = "Save a note that says the demo tool call was reviewed."
      run = new_run(chat, operation: "chat", input: { "prompt" => prompt, "tools" => Ai::ChatTooling.snapshot(@project), "provider_tools" => [] })
      run.start!
      chat.messages.create!(role: "user", content: prompt)
      attempt = attempt_for(run, sequence: 1, finish_reason: "tool_calls")
      now = Time.current
      invocation = run.tool_invocations.create!(
        attempt:, tool_key: "save_run_note", tool_call_id: "demo-call-1", status: :succeeded,
        tool_definition: @project.tool_definitions.find_by(key: "save_run_note"),
        arguments_json: { "note" => "The demo tool call was reviewed." },
        result_json: { "saved" => true }, started_at: now - 1.second, finished_at: now, duration_ms: 12
      )
      invocation.create_approval!(status: :approved, actor: "local_user", requested_at: now - 30.seconds, decided_at: now - 5.seconds,
        decision_note: "Approved in the demo tour.")
      run.artifacts.create!(attempt:, kind: "report", name: "Run note", content_text: "The demo tool call was reviewed.", source_tool_call_id: "demo-call-1")
      reply = chat.messages.create!(role: "assistant", content: "Saved the note after your approval.")
      attempt_for(run, sequence: 2, input_tokens: 180, output_tokens: 12)
      run.succeed!("finish_reason" => "stop", "message_id" => reply.id)
      settle(run, seconds: 31.2)
    end

    def agent_run
      definition = @project.agent_definitions.create!(
        name: "Source checker",
        provider: model.provider.to_s,
        model_id: model.id,
        instructions: "Inspect the project, search the web when asked, and answer with citations.",
        tool_keys: [ "project_snapshot" ],
        provider_tools: [ "web_search" ],
        options: { max_output_tokens: 4096 }
      )
      chat = new_chat("Agent: Source checker")
      prompt = "Find the official RubyLLM page for text-to-speech and name the method."
      run = new_run(chat, operation: "agent", input: {
        "prompt" => prompt, "agent_definition" => definition.snapshot, "tools" => [], "provider_tools" => [ "web_search" ]
      })
      run.start!
      chat.messages.create!(role: "user", content: prompt)
      first = attempt_for(run, sequence: 1, finish_reason: "tool_calls")
      now = Time.current
      run.tool_invocations.create!(
        attempt: first, tool_key: "project_snapshot", tool_call_id: "demo-agent-call-1", status: :succeeded,
        tool_definition: @project.tool_definitions.find_by(key: "project_snapshot"), arguments_json: {},
        result_json: { "project" => { "name" => @project.name, "slug" => @project.slug } },
        started_at: now - 1.second, finished_at: now, duration_ms: 8
      )
      final = attempt_for(run, sequence: 2, input_tokens: 4_600, output_tokens: 310)
      answer = chat.messages.create!(role: "assistant", content: "RubyLLM generates speech with RubyLLM.speak, documented on its Text to Speech guide.")
      citations = [ { "url" => "https://rubyllm.com/", "title" => "RubyLLM documentation" } ]
      run.artifacts.create!(attempt: final, kind: "citation_set", name: "Provider citations", content_json: citations,
        content_text: JSON.pretty_generate(citations),
        metadata_json: { "source_message_id" => answer.id, "citation_count" => citations.size, "provider_tools" => [ "web_search" ] })
      run.succeed!(
        "agent_definition" => definition.snapshot.slice("id", "name", "revision"),
        "agent_step_count" => 2,
        "source_message_id" => answer.id,
        "citation_count" => citations.size,
        "provider_tool_usage" => { "web_search_requests" => 1 }
      ) do
        report = Ai::AgentResearchReportRecorder.call(run:, message: answer)
        { "research_report_artifact_id" => report.id }
      end
      settle(run, seconds: 9.6)
    end

    def failed_run
      chat = new_chat("A failed call")
      prompt = "Summarize the release notes."
      run = new_run(chat, operation: "chat", input: { "prompt" => prompt, "tools" => [], "provider_tools" => [] })
      run.start!
      chat.messages.create!(role: "user", content: prompt)
      attempt_for(run, input_tokens: 0, output_tokens: 0, status: :failed, finish_reason: nil)
        .update!(error_class: "RubyLLM::RateLimitError", error_code: "rate_limited", error_message: "Rate limit reached (synthetic demo error).")
      run.fail!(RubyLLM::RateLimitError.new("Rate limit reached (synthetic demo error)."))
      run.update_columns(started_at: run.reload.finished_at - 0.6)
    end

    def knowledge_collection
      collection = @project.knowledge_collections.create!(name: "Rails background work", description: "Lexical search works without provider keys.")
      {
        "Solid Queue" => "Solid Queue is a database-backed Active Job backend. It runs workers, a dispatcher and recurring tasks without Redis.",
        "Turbo Streams" => "Turbo Streams deliver page changes as HTML fragments over WebSockets or in form responses.",
        "Active Storage" => "Active Storage attaches files to records and stores them on local disk or cloud services."
      }.each do |title, text|
        item = collection.knowledge_items.create!(title:, source_kind: "text", source_reference: "demo", content_text: text)
        Ai::Knowledge::Ingestor.call(item)
      end
    end

    def evaluation_dataset
      dataset = @project.evaluation_datasets.create!(
        name: "Summary checks",
        description: "Synthetic comparison: illustrative outputs, tokens, costs and timings; no provider was called. Valid schema does not guarantee an exact match or answer quality."
      )
      dataset.create_revision!([
        { "key" => "queue", "input" => { "prompt" => "Solid Queue stores jobs in the database." },
          "expected_output" => { "summary" => "Solid Queue stores jobs in the database.", "confidence" => 1 },
          "tags" => [ "rails" ],
          "rubric" => [ { "key" => "faithful", "description" => "The summary does not invent facts." } ] },
        { "key" => "turbo", "input" => { "prompt" => "Turbo updates pages without full reloads." },
          "expected_output" => { "summary" => "Turbo updates pages without full reloads.", "confidence" => 1 } }
      ])
      evaluation_comparison(dataset)
    end

    def evaluation_comparison(dataset)
      experiment = @project.experiments.find_by!(name: "Summarize with a schema")
      revision = dataset.current_revision_record
      dataset_snapshot = {
        "id" => dataset.id, "name" => dataset.name, "revision" => revision.revision,
        "cases" => revision.cases.map { |evaluation_case| evaluation_case.merge("attachments" => []) }
      }
      models = ([ model ] + RubyLLM.models.chat_models.all).uniq { |candidate| [ candidate.provider, candidate.id ] }
        .select { |candidate| candidate.supports?(:structured_output) && !candidate.id.to_s.end_with?(":batch") }.first(2)
      raise "The synthetic comparison needs two structured-output models in the bundled registry." unless models.size == 2

      targets = models.map do |candidate|
        { "provider" => candidate.provider.to_s, "model_id" => candidate.id,
          "name" => candidate.name, "capabilities" => candidate.capabilities.map(&:to_s) }
      end
      comparison = @project.evaluation_comparisons.create!(
        evaluation_dataset_revision: revision, experiment:, requested_by: REQUESTED_BY,
        dataset_snapshot_json: dataset_snapshot, experiment_snapshot_json: experiment.snapshot,
        model_targets_json: targets
      )

      models.each_with_index do |candidate, model_position|
        target = targets.fetch(model_position).merge("execution_mode" => "individual")
        execution = @project.evaluation_executions.create!(
          evaluation_comparison: comparison, evaluation_dataset_revision: revision, experiment:,
          provider: candidate.provider.to_s, model_id: candidate.id, execution_mode: :individual,
          status: :completed, case_count: revision.cases.size, requested_by: REQUESTED_BY,
          started_at: Time.current - 5.seconds, finished_at: Time.current,
          input_snapshot_json: {
            "dataset" => comparison.dataset_snapshot, "experiment" => comparison.experiment_snapshot,
            "target" => target, "judge" => nil, "demo_note" => SYNTHETIC_NOTE
          }
        )
        revision.cases.each_with_index do |evaluation_case, position|
          evaluation_case_run(execution:, evaluation_case:, position:, candidate:, target:, model_position:)
        end
      end
    end

    def evaluation_case_run(execution:, evaluation_case:, position:, candidate:, target:, model_position:)
      expected = evaluation_case.fetch("expected_output")
      actual = expected.deep_dup
      # A faithful paraphrase still fails exact JSON equality. These invented
      # examples demonstrate the metric; they are not a model benchmark.
      actual["summary"] = "Solid Queue persists background jobs in a database." if model_position == 1 && position.zero?
      schema = execution.input_snapshot.dig("experiment", "schema")
      errors = Ai::SchemaValidator.new(schema).errors_for(actual)
      raise "Synthetic evaluation output is invalid: #{errors.join('; ')}" if errors.any?

      chat = new_chat("Summary checks · #{evaluation_case.fetch('key')}", target_model: candidate)
      case_result = execution.evaluation_case_results.create!(
        evaluation_dataset_revision: execution.evaluation_dataset_revision,
        case_key: evaluation_case.fetch("key"), case_position: position,
        input_json: evaluation_case.fetch("input"), expected_output_json: expected, status: :queued
      )
      experiment_snapshot = execution.input_snapshot.fetch("experiment").deep_dup
      prompt = "#{experiment_snapshot.fetch('input_prompt')}\n\nEvaluation case input (JSON):\n#{JSON.pretty_generate(evaluation_case.fetch('input'))}"
      experiment_snapshot["input_prompt"] = prompt
      run = new_run(chat, operation: "structured", experiment: execution.experiment, input: {
        "experiment" => experiment_snapshot, "target" => target,
        "evaluation" => {
          "execution_id" => execution.id, "comparison_id" => execution.evaluation_comparison_id,
          "case_result_id" => case_result.id, "dataset_revision" => execution.evaluation_dataset_revision.revision,
          "case_key" => evaluation_case.fetch("key"), "tags" => evaluation_case.fetch("tags", []),
          "rubric" => evaluation_case.fetch("rubric", []), "attachments" => [],
          "input" => evaluation_case.fetch("input"), "expected_output" => expected
        }
      })
      run.start!
      chat.messages.create!(role: "user", content: prompt)
      chat.messages.create!(role: "assistant", content: JSON.generate(actual))
      attempt = attempt_for(run, output_tokens: 28, target_model: candidate)
      run.artifacts.create!(attempt:, kind: "json", name: "Synthetic evaluation output", content_json: actual,
        content_text: JSON.pretty_generate(actual))
      run.succeed!("schema_validation" => "valid", "structured_output" => actual, "demo_note" => SYNTHETIC_NOTE)
      settle(run, seconds: 1.9)
      passed = actual == expected
      case_result.update!(
        run:, status: :completed, transport_status: :received, schema_status: :valid, passed:,
        actual_output_json: actual, started_at: run.started_at, finished_at: run.finished_at,
        error_summary: passed ? nil : "Structured output did not exactly match the expected JSON value."
      )
    end
  end
end
