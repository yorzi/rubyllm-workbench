require "uri"

module Ai
  class RunReproductionExporter
    FORMAT_VERSION = 2
    MAX_EXPORT_BYTES = 512 * 1024
    MAX_STRING_LENGTH = 20_000
    MAX_TOTAL_TEXT_CHARACTERS = 100_000
    MAX_VALUE_NODES = 5_000
    MAX_NESTING_DEPTH = 8
    MAX_NESTED_COLLECTION_ITEMS = 50
    MAX_TOP_LEVEL_ITEMS = 100
    MAX_CHAT_MESSAGES = 100
    MAX_ARTIFACT_SCAN_ITEMS = 1_000
    OMITTED_VALUE = "[OMITTED: export complexity limit]".freeze
    TEXT_ARTIFACT_KINDS = %w[text json citation_set transcript ocr_document report export].freeze
    SENSITIVE_KEY = /\Akey\z|\Aprovider_job_id\z|(?:\A|_)(?:token|secret|password|authorization|credential|cookie)(?:\z|_)|(?:\A|_)(?:api|private|access|refresh|client)_?key(?:\z|_)/i
    OMIT_KEY = /(?:blob|binary|base64|file_data|audio_data|image_data|raw_data)/i
    URL_USERINFO_PATTERN = %r{([A-Za-z][A-Za-z0-9+.-]*://)[^/\s?#@]*@}
    URL_QUERY_PARAMETER_PATTERN = /([?&])([^=&#\s"'<>]+)=([^&#\s"'<>]*)/
    SIGNED_URL_QUERY_KEYS = %w[sig signature x-amz-signature x-goog-signature].freeze
    ASSIGNMENT_SECRET_PATTERN = /(["']?)([A-Z0-9_-]*(?:API[_-]?KEY|ACCESS[_-]?KEY(?:[_-]?ID)?|AWS[_-]?SECRET[_-]?ACCESS[_-]?KEY|PRIVATE[_-]?KEY|TOKEN|SECRET|PASSWORD|AUTHORIZATION|CREDENTIAL|COOKIE))\1(\s*[:=]\s*)(["']?)([^\s"',;}&?#]+)(\4)?/i
    SECRET_PATTERNS = [
      Ai::ErrorText::SECRET_PATTERN,
      /\bBearer\s+[A-Za-z0-9._~+\/-]+=*/i,
      /\b(?:AKIA|ASIA|AIDA|AROA|AGPA|ANPA|ANVA|ASCA)[A-Z0-9]{16}\b/,
      %r{data:[^\s,;]+;base64,[A-Za-z0-9+/=_-]+}i,
      /(?<![A-Za-z0-9+\/_-])[A-Za-z0-9+\/_-]{256,}={0,2}(?![A-Za-z0-9+\/_-])/,
      %r{(?:file://)?(?:/Users/[^\s"'<>]+|/home/[^\s"'<>]+|/root/[^\s"'<>]+|/tmp/[^\s"'<>]+|/private/var/[^\s"'<>]+|/var/tmp/[^\s"'<>]+|/var/folders/[^\s"'<>]+|[A-Z]:\\Users\\[^\s"'<>]+)}i
    ].freeze

    def self.sanitize_text(value)
      text = value.to_s.gsub(URL_USERINFO_PATTERN) { "#{Regexp.last_match(1)}REDACTED@" }
      text = text.gsub(URL_QUERY_PARAMETER_PATTERN) do
        match = Regexp.last_match(0)
        separator = Regexp.last_match(1)
        key = Regexp.last_match(2)
        normalized_key = URI.decode_www_form_component(key).downcase

        if SIGNED_URL_QUERY_KEYS.include?(normalized_key)
          "#{separator}#{key}=[REDACTED]"
        else
          match
        end
      rescue ArgumentError
        match
      end
      text = text.gsub(ASSIGNMENT_SECRET_PATTERN) do
        matched = Regexp.last_match
        "#{matched[1]}#{matched[2]}#{matched[1]}#{matched[3]}#{matched[4]}[REDACTED]#{matched[6]}"
      end
      SECRET_PATTERNS.each { |pattern| text = text.gsub(pattern, "[REDACTED]") }
      text.truncate(MAX_STRING_LENGTH)
    end

    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run
    end

    def call
      reset_budgets

      run = run_document
      attempts = limited_records(
        "attempts",
        @run.attempts,
        newest_order: { sequence: :desc, id: :desc }
      ).map { |attempt| attempt_document(attempt) }
      tools = limited_records(
        "tools",
        @run.tool_invocations.includes(:approval),
        newest_order: { created_at: :desc, id: :desc }
      ).map { |invocation| tool_document(invocation) }
      events = limited_records(
        "events",
        @run.lifecycle_events,
        newest_order: { occurred_at: :desc, id: :desc }
      ).map { |event| event_document(event) }
      chat_context = chat_context_document
      artifacts = exportable_artifacts.map { |artifact| artifact_document(artifact) }
      document = {
        "format_version" => FORMAT_VERSION,
        "generated_at" => Time.current.utc.iso8601(6),
        "run" => run,
        "chat_context" => chat_context,
        "attempts" => attempts,
        "tools" => tools,
        "events" => events,
        "artifacts" => artifacts
      }.compact

      document["truncation"] = truncation_document
      return document if JSON.pretty_generate(document).bytesize <= MAX_EXPORT_BYTES

      @omissions["full_export_exceeded_maximum_bytes"] = 1
      minimum_export_document
    end

    # A smaller export for timeline analysis, without loading Chat messages,
    # snapshots, tools or Artifacts. It shares the reproduction redaction limits.
    def events
      reset_budgets
      high_watermark = @run.lifecycle_events.maximum(:id)
      scope = @run.lifecycle_events.where("id <= ?", high_watermark || 0)
      records = limited_records("events", scope, newest_order: { occurred_at: :desc, id: :desc })
      document = {
        "format_version" => FORMAT_VERSION,
        "export_type" => "lifecycle_events",
        "generated_at" => Time.current.utc.iso8601(6),
        "run" => { "id" => @run.id, "operation" => @run.operation, "status" => @run.status },
        "event_high_watermark" => high_watermark,
        "events" => records.map { |event| event_document(event) },
        "truncation" => truncation_document
      }
      return document if JSON.pretty_generate(document).bytesize <= MAX_EXPORT_BYTES

      @omissions["full_export_exceeded_maximum_bytes"] = 1
      minimum_export_document.merge("export_type" => "lifecycle_events", "event_high_watermark" => high_watermark, "events" => [])
    end

    private

    def reset_budgets
      @omissions = Hash.new(0)
      @remaining_text_characters = MAX_TOTAL_TEXT_CHARACTERS
      @remaining_value_nodes = MAX_VALUE_NODES
    end

    def run_document
      {
        "id" => @run.id,
        "operation" => safe_text(@run.operation),
        "status" => safe_text(@run.status),
        "requested_by" => safe_value(@run.requested_by),
        "app_version" => safe_value(@run.app_version),
        "ruby_llm_version" => safe_value(@run.ruby_llm_version),
        "created_at" => timestamp(@run.created_at),
        "started_at" => timestamp(@run.started_at),
        "finished_at" => timestamp(@run.finished_at),
        "input_snapshot" => safe_value(exportable_input_snapshot),
        "result_summary" => safe_value(@run.result_summary),
        "error_summary" => safe_text(@run.error_summary)
      }
    end

    def exportable_input_snapshot
      @run.input_snapshot.except("conversation_context", "conversation_message_high_watermark")
    end

    def chat_context_document
      snapshot = @run.input_snapshot
      frozen_context = snapshot["conversation_context"]
      high_watermark = Integer(snapshot["conversation_message_high_watermark"], exception: false)
      return unless @run.operation == "chat" && frozen_context.is_a?(Hash) && high_watermark

      end_id = @run.result_summary["conversation_message_end_id"]
      end_id = @run.chat.messages.maximum(:id) || high_watermark if end_id.nil?
      provider_request_made = @run.result_summary["provider_request_made"]
      prior_messages = Array(frozen_context["messages"])
      omitted_prior_message_count = [ prior_messages.length - MAX_CHAT_MESSAGES, 0 ].max
      record_omission("chat_context.prior_messages", omitted_prior_message_count)
      prior_messages = prior_messages.last(MAX_CHAT_MESSAGES).map { |message| safe_value(message) }

      run_message_scope = @run.chat.messages
        .where("messages.id > ? AND messages.id <= ?", high_watermark, end_id)
      run_message_count = provider_request_made == false ? 0 : run_message_scope.count
      omitted_run_message_count = [ run_message_count - MAX_CHAT_MESSAGES, 0 ].max
      record_omission("chat_context.run_messages", omitted_run_message_count)
      run_messages = if provider_request_made == false
        []
      else
        run_message_scope
          .reorder(id: :desc)
          .limit(MAX_CHAT_MESSAGES)
          .to_a
          .reverse
          .map { |message| Ai::ChatContextSnapshot.message_document(message.to_llm) }
      end
      omitted_attachments = frozen_context["attachment_payloads_omitted"] ||
        provider_request_made != false && run_message_scope.joins(:attachments_attachments).exists?
      run_context_capture = if provider_request_made == false
        "no_provider_request"
      elsif @run.terminal?
        "frozen_at_completion"
      else
        "current_run_state"
      end

      {
        "format_version" => safe_value(frozen_context["format_version"]),
        "prior_messages" => prior_messages,
        "omitted_prior_message_count" => omitted_prior_message_count,
        "run_messages" => run_messages.map { |message| safe_value(message) },
        "omitted_run_message_count" => omitted_run_message_count,
        "prior_context_capture" => "frozen_before_prompt",
        "run_context_capture" => run_context_capture,
        "provider_request_made" => provider_request_made,
        "attachment_payloads_included" => false,
        "attachment_payloads_omitted" => !!omitted_attachments
      }
    end

    def attempt_document(attempt)
      {
        "sequence" => attempt.sequence,
        "provider" => safe_value(attempt.provider),
        "model_id" => safe_value(attempt.model_id),
        "status" => safe_text(attempt.status),
        "finish_reason" => safe_value(attempt.finish_reason),
        "usage" => {
          "input_tokens" => attempt.input_tokens,
          "output_tokens" => attempt.output_tokens,
          "cache_read_tokens" => attempt.cache_read_tokens,
          "cache_write_tokens" => attempt.cache_write_tokens,
          "thinking_tokens" => attempt.thinking_tokens
        },
        "cost" => {
          "status" => safe_text(attempt.cost_status),
          "reported" => decimal(attempt.reported_cost),
          "estimated" => decimal(attempt.estimated_cost),
          "currency" => safe_value(attempt.currency)
        },
        "duration_ms" => attempt.duration_ms,
        "error" => {
          "class" => safe_value(attempt.error_class),
          "code" => safe_value(attempt.error_code),
          "message" => safe_text(attempt.error_message)
        },
        "metadata" => safe_value(attempt.metadata_json || {})
      }
    end

    def tool_document(invocation)
      {
        "tool_key" => safe_value(invocation.tool_key),
        "tool_call_id" => safe_value(invocation.tool_call_id),
        "status" => safe_text(invocation.status),
        "remote" => invocation.remote?,
        "arguments" => safe_value(invocation.arguments),
        "result" => safe_value(invocation.result),
        "error" => safe_text(invocation.error_message),
        "duration_ms" => invocation.duration_ms,
        "approval" => invocation.approval && {
          "status" => safe_text(invocation.approval.status),
          "decision_note" => safe_text(invocation.approval.decision_note)
        }
      }
    end

    def event_document(event)
      {
        "id" => event.id,
        "attempt_id" => event.attempt_id,
        "artifact_id" => event.artifact_id,
        "tool_invocation_id" => event.tool_invocation_id,
        "approval_id" => event.approval_id,
        "name" => safe_text(event.name),
        "source" => safe_value(event.source),
        "occurred_at" => timestamp(event.occurred_at),
        "duration_ms" => event.duration_ms,
        "payload" => safe_value(event.payload)
      }
    end

    def artifact_document(artifact)
      document = {
        "kind" => safe_text(artifact.kind),
        "name" => safe_value(artifact.name),
        "created_at" => timestamp(artifact.created_at),
        "metadata" => safe_value(artifact.metadata_json || {}),
        "binary_content_included" => false
      }

      if TEXT_ARTIFACT_KINDS.include?(artifact.kind)
        document["content_json"] = safe_value(artifact.content_json) unless artifact.content_json.nil?
        document["content_text"] = safe_text(artifact.content_text) if artifact.content_text.present?
      end

      if artifact.audio_file.attached?
        document["binary"] = {
          "included" => false,
          "content_type" => safe_value(artifact.audio_file.content_type),
          "byte_size" => artifact.audio_file.byte_size
        }
      elsif artifact.media_file.attached?
        document["binary"] = {
          "included" => false,
          "content_type" => safe_value(artifact.media_file.content_type),
          "byte_size" => artifact.media_file.byte_size
        }
      end

      document
    end

    def upstream_candidate_artifact?(artifact)
      return false unless artifact.kind == "report"

      (artifact.metadata_json || {})["report_type"] == "upstream_candidate" ||
        (artifact.content_json || {})["report_type"] == "upstream_candidate"
    end

    def safe_value(value, depth: 0)
      unless consume_value_node
        record_omission("nested_values", 1)
        return OMITTED_VALUE
      end

      case value
      when Hash
        safe_hash(value, depth:)
      when Array
        safe_array(value, depth:)
      when String
        safe_text(value)
      else
        value
      end
    end

    def safe_hash(value, depth:)
      if depth >= MAX_NESTING_DEPTH
        record_omission("maximum_depth_values", value.length)
        return OMITTED_VALUE
      end

      output = {}
      processed = 0
      value.each do |key, nested|
        break if processed >= MAX_NESTED_COLLECTION_ITEMS || @remaining_value_nodes <= 0

        safe_key = safe_text(key.to_s)
        normalized_key = key.to_s.underscore
        output[safe_key] = if normalized_key.match?(SENSITIVE_KEY)
          "[REDACTED]"
        elsif normalized_key.match?(OMIT_KEY)
          record_omission("binary_or_raw_values_omitted", 1)
          "[OMITTED]"
        else
          safe_value(nested, depth: depth + 1)
        end
        processed += 1
      end

      record_omission("nested_hash_entries", value.length - processed)
      output
    end

    def safe_array(value, depth:)
      if depth >= MAX_NESTING_DEPTH
        record_omission("maximum_depth_values", value.length)
        return OMITTED_VALUE
      end

      output = []
      value.each do |nested|
        break if output.length >= MAX_NESTED_COLLECTION_ITEMS || @remaining_value_nodes <= 0

        output << safe_value(nested, depth: depth + 1)
      end

      record_omission("nested_array_items", value.length - output.length)
      output
    end

    def consume_value_node
      return false if @remaining_value_nodes <= 0

      @remaining_value_nodes -= 1
      true
    end

    def limited_records(name, relation, newest_order:)
      total = relation.count
      records = relation.reorder(newest_order).limit(MAX_TOP_LEVEL_ITEMS).to_a
      records.reverse!
      record_omission(name, total - records.length)
      records
    end

    def exportable_artifacts
      relation = @run.artifacts.reorder(created_at: :desc, id: :desc)
      records = []
      excluded_candidate_count = 0
      offset = 0
      total = relation.count
      scan_limit = [ total, MAX_ARTIFACT_SCAN_ITEMS ].min

      while offset < scan_limit && records.length < MAX_TOP_LEVEL_ITEMS
        batch_size = [ MAX_TOP_LEVEL_ITEMS, scan_limit - offset ].min
        batch = relation.offset(offset).limit(batch_size).to_a
        break if batch.empty?

        batch.each do |artifact|
          if upstream_candidate_artifact?(artifact)
            excluded_candidate_count += 1
            next
          end

          records << artifact if records.length < MAX_TOP_LEVEL_ITEMS
        end
        offset += batch.length
      end

      record_omission("upstream_candidate_reports_excluded", excluded_candidate_count)
      record_omission(
        "artifact_records_not_scanned_or_not_exported",
        total - records.length - excluded_candidate_count
      )
      records.reverse
    end

    def record_omission(name, count)
      @omissions[name] += count.to_i if count.to_i.positive?
    end

    def truncation_document
      {
        "limits" => {
          "maximum_export_bytes" => MAX_EXPORT_BYTES,
          "maximum_total_text_characters" => MAX_TOTAL_TEXT_CHARACTERS,
          "maximum_string_characters" => MAX_STRING_LENGTH,
          "maximum_value_nodes" => MAX_VALUE_NODES,
          "maximum_nesting_depth" => MAX_NESTING_DEPTH,
          "maximum_nested_collection_items" => MAX_NESTED_COLLECTION_ITEMS,
          "maximum_top_level_items" => MAX_TOP_LEVEL_ITEMS,
          "maximum_chat_messages_per_section" => MAX_CHAT_MESSAGES,
          "maximum_artifact_records_scanned" => MAX_ARTIFACT_SCAN_ITEMS
        },
        "omitted" => @omissions.sort.to_h
      }
    end

    def minimum_export_document
      {
        "format_version" => FORMAT_VERSION,
        "run" => {
          "id" => @run.id,
          "operation" => safe_text(@run.operation),
          "status" => safe_text(@run.status)
        },
        "truncation" => {
          "limits" => { "maximum_export_bytes" => MAX_EXPORT_BYTES },
          "omitted" => @omissions.sort.to_h
        }
      }
    end

    def bound_text(value)
      original_length = value.to_s.length
      text = self.class.sanitize_text(value)
      if original_length > MAX_STRING_LENGTH
        record_omission("per_string_values", 1)
      end

      if @remaining_text_characters <= 0
        record_omission("text_values", 1)
        return ""
      end

      if text.length <= @remaining_text_characters
        @remaining_text_characters -= text.length
        return text
      end

      marker = "[TRUNCATED: export text budget]"
      if @remaining_text_characters < marker.length
        record_omission("text_characters", text.length)
        @remaining_text_characters = 0
        return ""
      end

      prefix_length = [ @remaining_text_characters - marker.length, 0 ].max
      bounded = text.slice(0, prefix_length).to_s + marker
      record_omission("text_characters", text.length - prefix_length)
      @remaining_text_characters = [ @remaining_text_characters - bounded.length, 0 ].max
      bounded
    end

    def safe_text(value)
      bound_text(value)
    end

    def timestamp(value)
      value&.utc&.iso8601(6)
    end

    def decimal(value)
      value&.to_s("F")
    end
  end
end
