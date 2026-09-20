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
    when "succeeded" then "bg-emerald-50 text-success"
    when "failed" then "bg-rose-50 text-rose-700"
    when "running", "queued", "waiting_for_approval" then "bg-amber-50 text-warning"
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
    when "ai.provider.chat", "ai.provider.tool", "ai.provider.embedding", "ai.provider.rerank"
      summary = [ payload["operation"], payload["provider"], payload["model_id"] ].compact.join(" / ")
      details = []
      details << "#{payload["input_tokens"]} in / #{payload["output_tokens"]} out" if payload["input_tokens"] || payload["output_tokens"]
      details << payload["finish_reason"] if payload["finish_reason"].present?
      details << payload["status"] if payload["status"].present?
      [ summary.presence, details.join(" · ").presence ].compact.join(" — ")
    else
      payload["status"].presence || "Recorded in the local event catalog"
    end
  end
end
