module Ai
  class ExperimentExecutor
    def self.enqueue(experiment:, targets:, requested_by: "local_user", model_catalog: Ai::ModelCatalog.new)
      new(experiment:, targets:, requested_by:, model_catalog:).enqueue
    end

    def initialize(experiment:, targets:, requested_by:, model_catalog:)
      @experiment = experiment
      @targets = normalize_targets(targets)
      @requested_by = requested_by
      @model_catalog = model_catalog
    end

    def enqueue
      raise ArgumentError, "Choose at least two models." if @targets.size < 2
      raise ArgumentError, "Experiment must be runnable." unless @experiment.runnable?

      resolved_targets = resolve_targets!
      execution = nil
      runs = []

      @experiment.project.transaction do
        snapshot = @experiment.snapshot
        execution = @experiment.experiment_executions.create!(
          project: @experiment.project,
          status: :queued,
          target_count: resolved_targets.size,
          requested_by: @requested_by,
          input_snapshot_json: {
            "experiment" => snapshot,
            "targets" => resolved_targets.map { |target| target.fetch(:snapshot) }
          }
        )

        resolved_targets.each do |target|
          chat = @experiment.project.chats.create!(
            title: "#{@experiment.name} · #{target.fetch(:model).name}",
            model_id: target.fetch(:model).id,
            provider: target.fetch(:model).provider
          )
          run = chat.runs.create!(
            project: @experiment.project,
            experiment: @experiment,
            experiment_execution: execution,
            operation: "structured",
            status: :queued,
            requested_by: @requested_by,
            input_snapshot_json: {
              "experiment_execution_id" => execution.id,
              "experiment" => snapshot,
              "target" => target.fetch(:snapshot)
            },
            app_version: ENV.fetch("APP_VERSION", "local"),
            ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
          )
          run.attempts.create!(
            sequence: 1,
            provider: chat.provider,
            model_id: chat.model_id,
            status: :queued
          )
          runs << run
        end
      end

      runs.each { |run| StructuredResponseJob.perform_later(run.id) }
      execution
    end

    private

    def normalize_targets(targets)
      Array(targets).filter_map do |target|
        value = target.respond_to?(:to_h) ? target.to_h : {}
        provider = value[:provider] || value["provider"]
        model_id = value[:model_id] || value["model_id"]
        next if provider.blank? || model_id.blank?

        { provider: provider.to_s, model_id: model_id.to_s }
      end.uniq
    end

    def resolve_targets!
      @targets.map do |target|
        entry = @model_catalog.entries.find do |candidate|
          candidate.provider == target.fetch(:provider) && candidate.id == target.fetch(:model_id)
        end
        unless entry&.configured && entry.interactive? && entry.supports?(:structured_output)
          raise ArgumentError, "#{target.fetch(:provider)} / #{target.fetch(:model_id)} is not a configured structured-output model."
        end

        model = @model_catalog.find!(target.fetch(:model_id), provider: target.fetch(:provider))
        {
          model: model,
          snapshot: {
            "provider" => model.provider,
            "model_id" => model.id,
            "name" => model.name,
            "capabilities" => model.capabilities.map(&:to_s)
          }
        }
      end
    end
  end
end
