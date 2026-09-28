require "uri"

module ApplicationHelper
  def citation_value(citation, key)
    return if citation.nil?
    return citation.public_send(key) if citation.respond_to?(key)
    return unless citation.respond_to?(:[])

    citation[key.to_s] || citation[key.to_sym]
  end

  def citation_link_url(citation)
    url = citation_value(citation, :url).to_s
    parsed = URI.parse(url)
    parsed.to_s if parsed.is_a?(URI::HTTP) && parsed.host.present? && parsed.userinfo.blank?
  rescue URI::InvalidURIError
    nil
  end

  def format_duration(milliseconds)
    return "—" if milliseconds.blank?

    milliseconds.to_f < 1_000 ? "#{milliseconds.to_i} ms" : "#{format('%.2f', milliseconds.to_f / 1_000)} s"
  end

  def format_tokens(value)
    value.nil? ? "—" : number_with_delimiter(value)
  end

  def format_cost(value, status: "unknown")
    return "Unknown" if status.to_s == "unknown" || value.nil?

    "#{status.to_s.capitalize}: $#{format('%.6f', value.to_f)}"
  end

  def format_evaluation_metric_rate(rate)
    rate.nil? ? "Unknown" : number_to_percentage(rate * 100, precision: 1)
  end

  def format_evaluation_metric_tokens(total, sample_count:, attempts_count:)
    return "No token usage reported (0/#{attempts_count} Attempts)" if total.nil?

    "#{number_with_delimiter(total)} tokens (#{sample_count}/#{attempts_count} Attempts)"
  end

  def format_evaluation_cost_totals(totals)
    return "—" if totals.blank?

    totals.sort.map do |currency, amount|
      formatted_amount = format("%.6f", amount.to_f)
      currency == "USD" ? "$#{formatted_amount} USD" : "#{currency} #{formatted_amount}"
    end.join(" · ")
  end

  def format_evaluation_latency(metrics, execution_mode:)
    if execution_mode.to_s == "provider_batch"
      return "Not comparable: Attempt duration includes Batch wait and refresh time."
    end
    return "No known provider request duration samples." if metrics.latency_sample_count.zero?

    median = "#{metrics.latency_median_ms} ms median"
    p95 = metrics.latency_p95_ms ? "#{metrics.latency_p95_ms} ms p95" : "p95 shown at n≥#{Ai::EvaluationMetrics::LATENCY_P95_MINIMUM_SAMPLES}"
    "#{median} · #{p95} · n=#{metrics.latency_sample_count} · app-observed"
  end

  def queue_readiness
    @queue_readiness ||= Ai::QueueReadiness.call
  end

  def speech_models_available?
    return @speech_models_available if instance_variable_defined?(:@speech_models_available)

    @speech_models_available = Ai::SpeechCatalog.entries.any?
  end

  def run_status_label(run)
    return "Continuation queued" if run.agent_continuation_queued?

    run.status.tr("_", " ").capitalize
  end

  def capability_label(capability)
    capability.to_s.tr("_", " ").capitalize
  end

  def model_price(model, kind)
    value = model.price(kind)
    value ? "$#{format('%.4f', value)} / 1M" : "—"
  rescue ArgumentError, NoMethodError
    "—"
  end

  def status_classes(status)
    case status.to_s
    when "succeeded", "ready" then "bg-emerald-50 text-success"
    when "failed", "submission_unknown", "unavailable", "unknown" then "bg-rose-50 text-rose-700"
    when "running", "queued", "preparing", "submitting", "waiting_for_approval", "needs_attention" then "bg-amber-50 text-warning"
    else "bg-slate-100 text-muted"
    end
  end

  def lifecycle_event_summary(event)
    payload = event.payload
    case event.name
    when "ai.attempt.started", "ai.attempt.succeeded", "ai.attempt.failed", "ai.attempt.cancelled"
      [ payload["provider"], payload["model_id"] ].compact.join(" / ").presence || "Attempt ##{event.attempt_id}"
    when "ai.agent.step"
      [ "Step #{payload['step_number']}", payload["step_status"], "Agent revision #{payload['agent_revision']}" ].compact.join(" · ")
    when "ai.attempt.streaming"
      "First output at #{format_duration(payload["time_to_first_output_ms"])}"
    when "ai.tool.requested", "ai.tool.completed"
      [ payload["tool_key"], payload["status"]&.to_s&.tr("_", " ") ].compact.join(" · ").presence || "Tool invocation"
    when "ai.approval.requested", "ai.approval.decided"
      payload["decision"].presence || "Approval review"
    when "ai.artifact.created"
      [ payload["kind"], payload["name"] ].compact.join(" · ").presence || "Artifact"
    when "ai.run.failed"
      [ payload["failure_kind"], payload["error_class"] ].compact.join(" · ").presence || "Run failed"
    when "ai.run.cancelled"
      "Run cancelled"
    when "ai.provider.chat", "ai.provider.tool", "ai.provider.embedding", "ai.provider.rerank",
         "ai.provider.speech", "ai.provider.image", "ai.provider.transcription", "ai.provider.video"
      summary = [ payload["operation"], payload["provider"], payload["model_id"] ].compact.join(" / ")
      details = []
      details << "Provider job reference #{payload['provider_job_id']}" if payload["provider_job_id"].present?
      details << "#{payload["input_tokens"]} in / #{payload["output_tokens"]} out" if payload["input_tokens"] || payload["output_tokens"]
      details << payload["finish_reason"] if payload["finish_reason"].present?
      details << payload["status"] if payload["status"].present?
      [ summary.presence, details.join(" · ").presence ].compact.join(" — ")
    else
      payload["status"].presence || "Recorded in the local event catalog"
    end
  end
end
