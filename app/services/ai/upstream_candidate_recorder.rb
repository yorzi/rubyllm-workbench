module Ai
  class UpstreamCandidateRecorder
    CATEGORIES = %w[app_bug ruby_llm_gap provider_limitation unconfirmed].freeze
    MAX_TITLE_LENGTH = 200
    MAX_REFERENCE_LENGTH = 500

    def self.call(run:, attributes:)
      new(run:, attributes:).call
    end

    def initialize(run:, attributes:)
      @run = run
      @attributes = attributes.to_h.stringify_keys
    end

    def call
      category = @attributes["category"].to_s
      raise ArgumentError, "Choose a valid candidate category." unless CATEGORIES.include?(category)

      candidate = {
        "format_version" => 1,
        "report_type" => "upstream_candidate",
        "created_at" => Time.current.utc.iso8601(6),
        "category" => category,
        "title" => required_text("title", max_length: MAX_TITLE_LENGTH, single_line: true),
        "expected_behavior" => required_text("expected_behavior"),
        "observed_behavior" => required_text("observed_behavior"),
        "reproduction_steps" => required_text("reproduction_steps"),
        "regression_test_reference" => optional_text("regression_test_reference", max_length: MAX_REFERENCE_LENGTH),
        "evidence" => evidence,
        "reproduction" => Ai::RunReproductionExporter.call(@run)
      }

      @run.artifacts.create!(
        kind: "report",
        name: "Upstream candidate: #{candidate.fetch('title')}",
        content_json: candidate,
        content_text: JSON.pretty_generate(candidate),
        metadata_json: {
          "report_type" => "upstream_candidate",
          "category" => category,
          "append_only" => true
        }
      )
    end

    private

    def required_text(key, max_length: Ai::RunReproductionExporter::MAX_STRING_LENGTH, single_line: false)
      value = Ai::RunReproductionExporter.sanitize_text(@attributes[key])
      value = value.gsub(/\s+/, " ") if single_line
      value = value.strip
      raise ArgumentError, "#{key.humanize} is required." if value.blank?
      raise ArgumentError, "#{key.humanize} is too long." if value.length > max_length

      value
    end

    def optional_text(key, max_length:)
      value = Ai::RunReproductionExporter.sanitize_text(@attributes[key]).strip
      raise ArgumentError, "#{key.humanize} is too long." if value.length > max_length

      value.presence
    end

    def evidence
      attempt = @run.attempts.order(:sequence, :id).last
      {
        "run_id" => @run.id,
        "provider" => Ai::RunReproductionExporter.sanitize_text(attempt&.provider || @run.chat.provider),
        "model_id" => Ai::RunReproductionExporter.sanitize_text(attempt&.model_id || @run.chat.model_id),
        "app_version" => Ai::RunReproductionExporter.sanitize_text(@run.app_version),
        "ruby_llm_version" => Ai::RunReproductionExporter.sanitize_text(@run.ruby_llm_version)
      }
    end
  end
end
