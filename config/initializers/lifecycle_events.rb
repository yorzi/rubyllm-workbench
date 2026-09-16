Rails.application.config.after_initialize do
  Ai::LifecycleEventRecorder.subscribe!
end
