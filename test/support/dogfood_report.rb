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

  module TestHelpers
    def before_setup
      @dogfood_runs = []
      @dogfood_notes = []
      @dogfood_requested_models = []
      @dogfood_untracked_cost_operations = []
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
        unknown_cost_attempts = attempts.count { |attempt| attempt.cost.nil? }
        DogfoodReport.append(
          scenario: name.delete_prefix("test_"),
          result: dogfood_result,
          failure: skipped? ? nil : failure&.class&.name,
          skip_reason: @dogfood_skip_reason,
          requested_models: @dogfood_requested_models.uniq,
          models: (@dogfood_requested_models + observed_models).uniq,
          run_ids: runs.map(&:id),
          run_statuses: runs.map(&:status).tally,
          http_post_requests: @live_policy&.request_count,
          input_tokens: attempts.empty? ? nil : attempts.sum { |attempt| attempt.input_tokens.to_i },
          output_tokens: attempts.empty? ? nil : attempts.sum { |attempt| attempt.output_tokens.to_i },
          token_coverage: "run_attempts_only",
          reported_cost: sum_known_cost(attempts.filter_map(&:reported_cost)),
          recorded_cost: sum_known_cost(attempts.filter_map(&:recorded_cost)),
          estimated_cost: sum_known_cost(attempts.filter_map(&:estimated_cost)),
          known_cost: sum_known_cost(attempts.filter_map(&:cost)),
          unknown_cost_attempts: unknown_cost_attempts,
          untracked_cost_operations: @dogfood_untracked_cost_operations.uniq,
          cost_complete: unknown_cost_attempts.zero? && @dogfood_untracked_cost_operations.empty?,
          notes: @dogfood_notes,
          ruby_llm: Gem.loaded_specs.fetch("ruby_llm").version.to_s,
          at: Time.current.utc.iso8601
        )
      end
    ensure
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
