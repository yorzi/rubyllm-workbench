# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :prompt, :content, :input_snapshot,
  # Free-text inputs can contain private sources or credentials. Keep model,
  # provider and execution identifiers available for request diagnostics.
  /\Aq\z/i, :question, :rationale, :note, :description, :cases_json, :schema_json,
  :expected_behavior, :observed_behavior, :reproduction_steps
]
