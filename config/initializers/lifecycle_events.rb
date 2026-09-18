Rails.application.config.after_initialize do
  Ai::LifecycleEventRecorder.subscribe!
  Ai::RubyLlmInstrumentation.subscribe!
end
