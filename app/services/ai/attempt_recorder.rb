module Ai
  class AttemptRecorder
    TOKEN_FIELDS = {
      input_tokens: :input,
      output_tokens: :output,
      cache_read_tokens: :cache_read,
      cache_write_tokens: :cache_write,
      thinking_tokens: :thinking
    }.freeze

    def initialize(run, attempt: nil, clock: Process.method(:clock_gettime), chat: nil, continuation: false)
      @run = run
      @chat = chat || @run.chat
      @attempt = attempt
      @continuation = continuation
      @clock = clock
      @started_monotonic = @clock.call(Process::CLOCK_MONOTONIC)
      @partial_output = +""
      @first_output_monotonic = nil
    end

    attr_reader :partial_output

    def start!
      @attempt ||= if @continuation
        @run.attempts.create!(
          sequence: next_sequence,
          provider: @chat.provider.to_s,
          model_id: @chat.model_id.to_s,
          status: :queued
        )
      else
        @run.attempts.order(:sequence, :id).first || @run.attempts.create!(
          sequence: next_sequence,
          provider: @chat.provider.to_s,
          model_id: @chat.model_id.to_s,
          status: :queued
        )
      end

      @run.start! unless @run.running?
      @attempt.start! unless @attempt.running?
      @attempt
    end

    def observe!(content)
      return if content.blank?

      @partial_output << content.to_s
      return if @first_output_monotonic

      @first_output_monotonic = @clock.call(Process::CLOCK_MONOTONIC)
      first_output_ms = elapsed_ms(@first_output_monotonic)
      @run.update!(time_to_first_output_ms: first_output_ms)
      @attempt.update!(time_to_first_output_ms: first_output_ms)
      Ai::LifecycleEventRecorder.emit(
        "ai.attempt.streaming",
        run_id: @run.id,
        attempt_id: @attempt.id,
        provider: @attempt.provider,
        model_id: @attempt.model_id,
        status: @attempt.status,
        time_to_first_output_ms: first_output_ms,
        event_key: "attempt:#{@attempt.id}:streaming"
      )
    end

    def succeed!(response, usage_ids_before: [], result_summary: {})
      usage_records = new_usage_records(usage_ids_before)
      if usage_records.any?
        sync_usage_records!(usage_records, fallback_status: :succeeded)
      else
        update_from_response!(response, status: :succeeded)
      end

      summary = response_summary(response).merge(result_summary).merge("partial_output" => @partial_output.presence)
      summary.delete("partial_output") if summary["partial_output"].nil?
      @run.succeed!(summary)
      @run
    end

    def waiting_for_approval!(usage_ids_before: [], result_summary: {})
      usage_records = new_usage_records(usage_ids_before)
      sync_usage_records!(usage_records, fallback_status: :succeeded) if usage_records.any?
      @run.wait_for_approval!(
        result_summary.merge("partial_output" => @partial_output.presence).compact,
        attempt_id: @attempt.id
      )
      @run
    end

    def fail!(error, usage_ids_before: [])
      usage_records = new_usage_records(usage_ids_before)
      if usage_records.any?
        sync_usage_records!(usage_records, fallback_status: :failed, error: error)
      else
        @attempt ||= start!
        @attempt.finish!(
          status: :failed,
          **error_attributes(error),
          duration_ms: elapsed_ms(@clock.call(Process::CLOCK_MONOTONIC)),
          time_to_first_output_ms: first_output_ms
        )
      end

      summary = { "partial_output" => @partial_output.presence }.compact
      @run.fail!(error, summary: summary)
      @run
    end

    private

    def new_usage_records(usage_ids_before)
      relation = @chat.ruby_llm_usages
      records = if usage_ids_before.empty?
        relation.to_a
      else
        relation.where.not(id: usage_ids_before).to_a
      end
      records.sort_by { |record| [ record.created_at || Time.at(0), record.id ] }
    end

    def sync_usage_records!(usage_records, fallback_status:, error: nil)
      usage_records.each_with_index do |usage, index|
        attempt = attempt_for(usage, index)
        attempt.assign_attributes(
          provider: usage.provider,
          model_id: usage.model,
          status: error ? :failed : normalized_status(usage.status, fallback_status),
          started_at: attempt.started_at || @run.started_at || Time.current,
          finished_at: Time.current,
          duration_ms: elapsed_ms(@clock.call(Process::CLOCK_MONOTONIC)),
          time_to_first_output_ms: first_output_ms,
          ruby_llm_usage_ids_json: Array(attempt.ruby_llm_usage_ids_json) | [ usage.id ]
        )
        attempt.assign_attributes(token_attributes(usage.tokens))
        attempt.assign_attributes(Ai::CostNormalizer.for(usage, model: model_for(usage)))
        attempt.assign_attributes(error_attributes(error)) if error
        attempt.save!
      end
    end

    def attempt_for(usage, index)
      existing = @run.attempts.find do |candidate|
        Array(candidate.ruby_llm_usage_ids_json).map(&:to_i).include?(usage.id)
      end
      return existing if existing
      return @attempt if index.zero?

      @run.attempts.create!(
        sequence: next_sequence,
        provider: usage.provider,
        model_id: usage.model,
        status: :queued
      )
    end

    def update_from_response!(response, status:)
      model = begin
        Ai::ModelCatalog.new.find!(@chat.model_id, provider: @chat.provider)
      rescue StandardError
        nil
      end
      @attempt.assign_attributes(
        status: status,
        finished_at: Time.current,
        duration_ms: elapsed_ms(@clock.call(Process::CLOCK_MONOTONIC)),
        time_to_first_output_ms: first_output_ms
      )
      @attempt.assign_attributes(token_attributes(response.tokens)) if response.respond_to?(:tokens)
      @attempt.assign_attributes(Ai::CostNormalizer.for(response, model: model))
      @attempt.save!
    end

    def model_for(usage)
      Ai::ModelCatalog.new.find!(usage.model, provider: usage.provider)
    rescue StandardError
      nil
    end

    def token_attributes(tokens)
      TOKEN_FIELDS.to_h do |attribute, reader|
        [ attribute, tokens.public_send(reader) ]
      end
    end

    def response_summary(response)
      summary = {}
      summary["finish_reason"] = response.finish_reason.to_s if response.respond_to?(:finish_reason) && response.finish_reason
      summary["message_id"] = response.id if response.respond_to?(:id) && response.id
      summary["usage_ids"] = @chat.ruby_llm_usages.chronological.pluck(:id)
      summary
    end

    def error_attributes(error)
      {
        error_class: error.class.name,
        error_code: Ai::ErrorClassifier.code(error),
        error_message: redact(error.message).to_s.truncate(2_000)
      }
    end

    def redact(message)
      Ai::ErrorText.redact(message)
    end

    def normalized_status(status, fallback)
      value = status.to_s
      return value.to_sym if %w[succeeded failed cancelled].include?(value)

      fallback
    end

    def next_sequence
      @run.attempts.maximum(:sequence).to_i + 1
    end

    def first_output_ms
      @first_output_monotonic ? elapsed_ms(@first_output_monotonic) : nil
    end

    def elapsed_ms(now)
      ((now - @started_monotonic) * 1_000).round
    end
  end
end
