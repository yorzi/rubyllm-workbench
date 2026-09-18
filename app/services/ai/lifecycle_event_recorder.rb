module Ai
  class LifecycleEventRecorder
    EVENT_PATTERN = /\Aai\.(?:run|attempt|tool|approval|artifact)\./
    PAYLOAD_KEYS = %w[
      run_id attempt_id artifact_id tool_invocation_id approval_id
      project_id operation status provider provider_class model_id tool_key
      tool_call_id tool_name streaming remote decision actor kind error_class
      error_code failure_kind duration_ms input_tokens output_tokens
      total_cost finish_reason time_to_first_output_ms schema_name
      schema_validation pending_tool_count
    ].freeze

    class << self
      def subscribe!
        return @subscription if @subscription

        @subscription = ActiveSupport::Notifications.subscribe(EVENT_PATTERN) do |name, started_at, finished_at, notification_id, payload|
          new.record(
            name: name,
            started_at: started_at,
            finished_at: finished_at,
            notification_id: notification_id,
            payload: payload
          )
        end
      end

      # Accepts the payload either as a positional hash or as bare keywords,
      # because callers in this codebase use both forms.
      def emit(name, payload = nil, source: "application", **kwargs)
        event_name = name.to_s
        unless LifecycleEvent::EVENT_NAMES.include?(event_name)
          raise ArgumentError, "Unknown AI lifecycle event: #{event_name}"
        end

        attributes = (payload.is_a?(Hash) ? payload : {}).merge(kwargs)
        ActiveSupport::Notifications.instrument(event_name, attributes.merge(source: source.to_s))
      end

      # Writes an event that did not originate from our own `ai.*` instrument
      # calls, such as one mapped from a RubyLLM notification. The catalog
      # validation and payload whitelist are identical either way.
      def persist(name, payload: {}, started_at: nil, finished_at: nil, notification_id: nil, source: "application")
        event_name = name.to_s
        unless LifecycleEvent::EVENT_NAMES.include?(event_name)
          raise ArgumentError, "Unknown AI lifecycle event: #{event_name}"
        end

        new.record_with(
          name: event_name,
          started_at: started_at,
          finished_at: finished_at,
          notification_id: notification_id,
          payload: payload.merge(source: source.to_s)
        )
      end
    end

    def record(name:, started_at:, finished_at:, notification_id:, payload:)
      record_with(name: name, started_at: started_at, finished_at: finished_at, notification_id: notification_id, payload: payload)
    end

    def record_with(name:, started_at:, finished_at:, notification_id:, payload:)
      event_name = name.to_s
      return unless LifecycleEvent::EVENT_NAMES.include?(event_name)
      return unless LifecycleEvent.table_exists?

      raw_payload = payload.to_h.stringify_keys
      source = raw_payload.delete("source").to_s.presence || "application"
      run_id = integer_id(raw_payload["run_id"])
      return unless run_id

      key = raw_payload["event_key"].to_s.presence || derived_event_key(event_name, raw_payload, notification_id)
      return unless key

      LifecycleEvent.create!(
        run_id: run_id,
        attempt_id: integer_id(raw_payload["attempt_id"]),
        artifact_id: integer_id(raw_payload["artifact_id"]),
        tool_invocation_id: integer_id(raw_payload["tool_invocation_id"]),
        approval_id: integer_id(raw_payload["approval_id"]),
        name: event_name,
        event_key: key,
        source: source,
        occurred_at: Time.current,
        duration_ms: duration_ms(started_at, finished_at),
        payload_json: normalized_payload(raw_payload)
      )
    rescue ActiveRecord::RecordNotUnique
      LifecycleEvent.find_by(event_key: key)
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn("AI lifecycle event persistence failed: #{error.class}")
      nil
    end

    private

    def derived_event_key(event_name, payload, notification_id)
      identity = %w[artifact_id approval_id tool_invocation_id attempt_id run_id].filter_map do |key|
        value = payload[key].to_s.presence
        value && "#{key}=#{value}"
      end
      identity = [ "notification=#{notification_id}" ] if identity.empty? && notification_id.to_s.present?
      return if identity.empty?

      "#{event_name}:#{identity.join(':')}"
    end

    def normalized_payload(payload)
      payload.slice(*PAYLOAD_KEYS).each_with_object({}) do |(key, value), normalized|
        next if value.nil?

        normalized[key] = normalize_value(value)
      end
    end

    def normalize_value(value)
      case value
      when String, Symbol
        value.to_s.truncate(500)
      when Numeric, TrueClass, FalseClass
        value
      else
        value.to_s.truncate(500)
      end
    end

    def integer_id(value)
      return if value.blank?

      Integer(value.to_s, 10)
    rescue ArgumentError, TypeError
      nil
    end

    def duration_ms(started_at, finished_at)
      return unless started_at.respond_to?(:to_f) && finished_at.respond_to?(:to_f)

      elapsed = (finished_at.to_f - started_at.to_f) * 1_000
      elapsed.round if elapsed >= 0
    end
  end
end
