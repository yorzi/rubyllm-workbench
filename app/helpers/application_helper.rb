module ApplicationHelper
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
end
