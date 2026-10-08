# Records one JSON line per live dogfood scenario so `bin/dogfood` can print a
# summary and the result can be copied into docs/CAPABILITIES.md. Lines contain
# model identifiers, Run ids, token counts and cost only, never prompts,
# responses or credentials.
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
      super
    end

    def after_teardown
      runs = Run.where(id: @dogfood_runs.map(&:id)).includes(:attempts).to_a
      attempts = runs.flat_map(&:attempts)
      DogfoodReport.append(
        scenario: name.delete_prefix("test_"),
        result: dogfood_result,
        failure: failure&.message.to_s.lines.first.to_s.strip.truncate(300).presence,
        models: attempts.map { |attempt| "#{attempt.provider}/#{attempt.model_id}" }.uniq,
        run_ids: runs.map(&:id),
        input_tokens: attempts.sum { |attempt| attempt.input_tokens.to_i },
        output_tokens: attempts.sum { |attempt| attempt.output_tokens.to_i },
        reported_cost: attempts.filter_map(&:reported_cost).sum.to_f.round(6),
        recorded_cost: attempts.filter_map(&:recorded_cost).sum.to_f.round(6),
        estimated_cost: attempts.filter_map(&:estimated_cost).sum.to_f.round(6),
        notes: @dogfood_notes,
        ruby_llm: Gem.loaded_specs.fetch("ruby_llm").version.to_s,
        at: Time.current.utc.iso8601
      ) if ENV["LIVE_DOGFOOD"].present?
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

    def note(text)
      @dogfood_notes << text.to_s.truncate(200)
    end
  end
end
