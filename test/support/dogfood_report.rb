# Records one JSON line per live dogfood scenario so `bin/dogfood` can print a
# summary and the result can be copied into docs/CAPABILITIES.md. Lines contain
# model identifiers, transient test Run ids, statuses, token counts and cost
# coverage only, never prompts, responses or credentials.
module DogfoodReport
  def self.path
    Pathname(ENV.fetch("DOGFOOD_REPORT", Rails.root.join("tmp/dogfood/report.jsonl").to_s))
  end

  def self.append(entry)
    path.dirname.mkpath
    File.open(path, "a") { |file| file.puts(entry.to_json) }
  end

  def self.token_total(values)
    return if values.empty? || values.any?(&:nil?)
    values.sum
  end

  def self.http_evidence(payload, duration_ms:)
    error_class = payload[:exception_object]&.class&.name || Array(payload[:exception]).first
    {
      provider: payload[:provider], method: payload[:method].to_s,
      http_status: payload[:status], duration_ms: duration_ms.round(2),
      # RubyLLM 2.1 request notifications expose status, but no response headers.
      request_id: nil, error_class: error_class
    }
  end

  module TestHelpers
    def before_setup
      @dogfood_runs = []
      @dogfood_collection_ids = []
      @dogfood_notes = []
      @dogfood_requested_models = []
      @dogfood_untracked_cost_operations = []
      @dogfood_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @dogfood_http_requests = []
      @dogfood_subscription = ActiveSupport::Notifications.subscribe("request.ruby_llm") do |*, started, finished, _id, payload|
        @dogfood_http_requests << DogfoodReport.http_evidence(payload, duration_ms: (finished - started) * 1_000)
      end
      super
    end

    def after_teardown
      if ENV["LIVE_DOGFOOD"] == "1"
        # Collect before transactional fixture teardown, including requests
        # that failed before the scenario could explicitly track their Run.
        run_ids = @dogfood_runs.compact.map(&:id)
        run_ids |= @project.runs.pluck(:id) if @project&.persisted?
        runs = Run.where(id: run_ids).includes(:attempts).to_a
        attempts = runs.flat_map(&:attempts)
        observed_models = attempts.map { |attempt| "#{attempt.provider}/#{attempt.model_id}" }.uniq
        owned_usages = RubyLLM::ActiveRecord::Usage.where(owner_type: "KnowledgeCollection", owner_id: @dogfood_collection_ids)
          .or(RubyLLM::ActiveRecord::Usage.where(owner_type: "Attempt", owner_id: attempts.map(&:id))).chronological.to_a
        mirrored_ids = attempts.flat_map(&:ruby_llm_usage_ids_json).map(&:to_i)
        additional_usages = owned_usages.reject { |usage| mirrored_ids.include?(usage.id) }
        additional_costs = additional_usages.map { |usage| Ai::CostNormalizer.for(usage) }
        unknown_cost_attempts = attempts.count { |attempt| attempt.cost.nil? }
        unknown_owned_usages = additional_costs.count { |cost| cost[:cost_status] == "unknown" }
        DogfoodReport.append(
          scenario: name.delete_prefix("test_"),
          profile: ENV.fetch("AI_TEST_PROFILE", "mock"),
          capabilities: runs.map(&:operation).uniq | owned_usages.map(&:operation).uniq | @dogfood_untracked_cost_operations,
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @dogfood_started_at) * 1_000).round(2),
          result: dogfood_result,
          failure: skipped? ? nil : failure&.class&.name,
          skip_reason: @dogfood_skip_reason,
          requested_models: @dogfood_requested_models.uniq,
          models: (@dogfood_requested_models + observed_models).uniq,
          run_ids: runs.map(&:id),
          run_statuses: runs.map(&:status).tally,
          http_post_requests: @live_policy&.request_count,
          http_requests: @dogfood_http_requests,
          input_tokens: DogfoodReport.token_total(attempts.map(&:input_tokens) + additional_usages.map(&:input_tokens)),
          output_tokens: DogfoodReport.token_total(attempts.map(&:output_tokens) + additional_usages.map(&:output_tokens)),
          token_coverage: "run_attempts_and_unmirrored_owned_usages",
          owned_provider_usages: owned_usages.map { |usage| { id: usage.id, operation: usage.operation, owner_type: usage.owner_type, owner_id: usage.owner_id, provider: usage.provider, model: usage.model, status: usage.status, input_tokens: usage.input_tokens, output_tokens: usage.output_tokens, native_recorded_cost: usage.total_cost&.to_f, normalized_cost: Ai::CostNormalizer.for(usage) } },
          reported_cost: sum_known_cost(attempts.filter_map(&:reported_cost) + additional_costs.filter_map { |cost| cost[:reported_cost] }),
          recorded_cost: sum_known_cost(attempts.filter_map(&:recorded_cost) + additional_costs.filter_map { |cost| cost[:recorded_cost] }),
          estimated_cost: sum_known_cost(attempts.filter_map(&:estimated_cost) + additional_costs.filter_map { |cost| cost[:estimated_cost] }),
          known_cost: sum_known_cost(attempts.filter_map(&:cost) + additional_costs.filter_map { |cost| cost[:reported_cost] || cost[:recorded_cost] || cost[:estimated_cost] }),
          unknown_cost_attempts: unknown_cost_attempts,
          unknown_owned_usages: unknown_owned_usages,
          untracked_cost_operations: @dogfood_untracked_cost_operations.uniq,
          cost_complete: unknown_cost_attempts.zero? && unknown_owned_usages.zero? && @dogfood_untracked_cost_operations.empty?,
          notes: @dogfood_notes,
          ruby_llm: Gem.loaded_specs.fetch("ruby_llm").version.to_s,
          at: Time.current.utc.iso8601
        )
      end
    ensure
      ActiveSupport::Notifications.unsubscribe(@dogfood_subscription) if @dogfood_subscription
      super
    end

    private

    def dogfood_result
      return "skip" if skipped?
      passed? ? "pass" : "fail"
    end

    def track_run(run)
      @dogfood_runs << run
      run
    end

    def track_collection(collection)
      @dogfood_collection_ids << collection.id
      collection
    end

    def request_model(reference)
      @dogfood_requested_models << reference.to_s
    end

    def untracked_cost_operations(*operations)
      @dogfood_untracked_cost_operations.concat(operations.map(&:to_s))
    end

    def sum_known_cost(values)
      values.empty? ? nil : values.sum.to_f.round(6)
    end

    def note(text)
      @dogfood_notes << Ai::ErrorText.safe(text.to_s, limit: 200)
    end
  end
end
