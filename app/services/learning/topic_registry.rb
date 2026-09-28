module Learning
  class TopicRegistry
    class << self
      def all
        @all ||= build_topics.freeze
      end

      def keys
        all.map(&:key).freeze
      end

      def fetch(key)
        all.find { |topic| topic.key == key.to_s }
      end

      def fetch!(key)
        fetch(key) || raise(KeyError, "Unknown learning topic: #{key}")
      end

      # This is intentionally explicit instead of running at boot. The test suite
      # calls it so source-line drift fails loudly without making a broken code
      # reference prevent the application from starting in every environment.
      def validate!
        raise "Learning topic keys must be unique" unless keys.uniq == keys

        all.each do |topic|
          raise "Learning topic key is blank" if topic.key.blank?
          raise "Learning topic title is blank" if topic.title.blank?
          raise "Learning topic has no code references: #{topic.key}" if topic.code_references.empty?

          topic.code_references.each { |reference| SourceReader.new(reference).read }
        end

        true
      end

      private

      def build_topics
        [
          Topic.new(
            key: "model_explorer",
            title: "How Model Explorer works",
            kicker: "RubyLLM registry → capability gate → runnable selection",
            summary: "Model Explorer is a local catalog view: it lets people inspect RubyLLM models and provider capabilities before a provider call is made, while keeping browseable models distinct from models that are configured to run.",
            steps: list(
              step("1. The Rails action reads catalog filters", "ModelsController passes the query, provider, capability, and configuration-state filters to one catalog boundary, then caps the rendered result set."),
              step("2. ModelCatalog wraps RubyLLM descriptors", "The catalog starts from RubyLLM's chat-model registry and builds descriptors containing the canonical id, provider, capabilities, modalities, pricing, and context limits."),
              step("3. Configuration state is derived explicitly", "Provider configuration requirements are compared with the current RubyLLM config. A missing credential makes the entry needs configuration; it does not invent a runnable model."),
              step("4. Capability filters narrow the honest surface", "Streaming, vision, function calling, and structured output are filters over declared model metadata. They are not a promise that every provider behaves identically."),
              step("5. A selected model enters Chat setup", "The selection carries both provider and canonical model id, because the same id can be exposed by more than one provider. Chat creation resolves it again before persistence.")
            ),
            code_references: list(
              reference("app/controllers/models_controller.rb", "Catalog page action", "Passes user filters into the catalog and bounds the page.", 1, 14, "@models = model_catalog.entries"),
              reference("app/services/ai/model_catalog.rb", "Model catalog", "Filters and sorts RubyLLM model descriptors.", 26, 43, "FILTERABLE_CAPABILITIES ="),
              reference("app/services/ai/model_catalog.rb", "Provider configuration", "Derives configured versus needs-configuration state from provider requirements.", 55, 73, "def descriptor_for"),
              reference("app/controllers/chats_controller.rb", "Model selection handoff", "Resolves the provider and canonical model id before saving a Chat.", 15, 24, "def create")
            ),
            external_references: list(
              external("RubyLLM overview", "https://rubyllm.com/overview/", "RubyLLM model and provider boundary"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "RubyLLM in a Rails application"),
              external("Rails Action Controller overview", "https://guides.rubyonrails.org/action_controller_overview.html", "Rails request and filtering boundary")
            ),
            evidence: list(
              note("Model descriptor", "The canonical model id, provider, declared capabilities, pricing, and configuration state shown by the catalog."),
              note("Provider state", "The current process can distinguish configured models from models that are browseable but not runnable."),
              note("Chat selection", "The provider plus canonical model id that will be persisted if a Chat is created.")
            ),
            boundaries: list(
              "The catalog is a browse surface; listing a model does not call the provider or prove that a live request will succeed.",
              "Capability metadata is a compatibility signal, not a cross-provider quality benchmark.",
              "Provider credentials and secrets never appear in the learning panel or source snapshots."
            )
          ),
          Topic.new(
            key: "chat_setup",
            title: "How Chat setup works",
            kicker: "Project → Chat → provider/model",
            summary: "Creating a Chat establishes the durable conversation boundary. The selected provider and canonical model id are resolved through RubyLLM and stored before the first message can create a Run.",
            steps: list(
              step("1. The new action builds a Project-scoped Chat", "ChatsController creates the unsaved Chat through the current Project and loads a bounded catalog for the form."),
              step("2. The form submits a provider-qualified choice", "The selected value is split into provider and canonical model id. This avoids ambiguity when multiple providers expose the same model id."),
              step("3. RubyLLM resolves the model", "The controller asks ModelCatalog to find the model with the provider context, then assigns the resolved model to the Chat."),
              step("4. The Chat becomes the durable conversation", "After save, the user is redirected to the Chat page. RubyLLM's Active Record integration owns messages while the Workbench associates the Chat with its Project."),
              step("5. The first message creates the execution envelope", "A later message is handed to RunExecutor, which snapshots tools, execution options, versions, and the first Attempt before enqueueing provider work.")
            ),
            code_references: list(
              reference("app/controllers/chats_controller.rb", "Chat form setup", "Builds the Project-scoped Chat and catalog-backed model choices.", 4, 13, "def new"),
              reference("app/controllers/chats_controller.rb", "Chat persistence", "Resolves and saves the provider-qualified model selection.", 15, 35, "def create"),
              reference("app/models/chat.rb", "Conversation boundary", "Connects RubyLLM chat behavior to the Project and durable Runs.", 1, 10, "acts_as_chat"),
              reference("app/services/ai/run_executor.rb", "First message handoff", "Creates the durable Run and Attempt before queueing ChatResponseJob.", 14, 42, "def enqueue")
            ),
            external_references: list(
              external("Rails form helpers", "https://guides.rubyonrails.org/form_helpers.html", "Rails model-backed form boundary"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "RubyLLM persistence and Rails integration"),
              external("RubyLLM overview", "https://rubyllm.com/overview/", "RubyLLM chat boundary")
            ),
            evidence: list(
              note("Project", "The local scope that owns the Chat and its related Runs."),
              note("Chat", "The persisted provider/model conversation boundary and RubyLLM message owner."),
              note("Run snapshot", "The first message's immutable execution inputs, tool contract, versions, and Attempt identity.")
            ),
            boundaries: list(
              "Creating a Chat validates the model identity and stores the conversation; it does not prove provider availability until a Run executes.",
              "The Workbench currently uses Project as a local organizational boundary, not as a complete authentication or multi-tenant policy.",
              "The explanation describes persistence and handoff, not the provider's internal prompt construction or model behavior."
            )
          ),
          Topic.new(
            key: "chat_run",
            title: "How a Chat Run works",
            kicker: "Chat → Run → Attempt → RubyLLM",
            summary: "A prompt becomes a durable Run before provider code runs, so the Workbench can show what was requested, which tools were frozen, and how the attempt finished.",
            steps: list(
              step("1. The Rails action accepts the message", "MessagesController checks the selected model and hands the prompt plus an optional, per-Run web-search choice to Ai::RunExecutor. The page redirects back to the Chat; execution is asynchronous."),
              step("2. The application creates the evidence boundary", "RunExecutor snapshots enabled local tools, provider-tool keys, tool policy, app version, RubyLLM version, provider, model, and the first Attempt before enqueueing ChatResponseJob."),
              step("3. The job enters the ChatExecutor", "ChatResponseJob loads the Run. ChatExecutor claims it, starts the Attempt, configures local and provider tools from the frozen snapshot, and executes ask or complete inside the Run/Attempt execution context."),
              step("4. Streaming, tool records and citations are persisted", "The executor observes streamed content; ToolInvocationRecorder synchronizes local RubyLLM tools into invocation and approval records; provider search steps remain on the RubyLLM Message and citations are copied to a Run Artifact."),
              step("5. RubyLLM notifications are adapted", "The instrumentation adapter listens to RubyLLM notifications and maps a safe subset to local ai.provider.* lifecycle events. This is an adapter boundary, not provider-native tracing.")
            ),
            code_references: list(
              reference("app/controllers/messages_controller.rb", "Rails entry point", "Validates the model and enqueues the Run.", 15, 29, "Ai::RunExecutor.enqueue"),
              reference("app/services/ai/run_executor.rb", "Run creation and snapshot", "Creates the durable Run and first Attempt.", 14, 42, "def enqueue"),
              reference("app/jobs/chat_response_job.rb", "Queue handoff", "Moves the durable Run into the executor.", 1, 5, "Ai::ChatExecutor.new"),
              reference("app/services/ai/chat_executor.rb", "Chat execution", "Claims, configures, streams, and completes the Attempt.", 8, 41, "def call"),
              reference("app/services/ai/citation_set_recorder.rb", "Citation artifact", "Persists normalized provider citations against the Run and Attempt.", 1, 40, "class CitationSetRecorder"),
              reference("app/services/ai/ruby_llm_instrumentation.rb", "RubyLLM adapter", "Maps RubyLLM notifications to local lifecycle evidence.", 24, 36, "ActiveSupport::Notifications.subscribe")
            ),
            external_references: list(
              external("Rails Action Controller overview", "https://guides.rubyonrails.org/action_controller_overview.html", "Rails request/action boundary"),
              external("Rails Action View overview", "https://guides.rubyonrails.org/action_view_overview.html", "Rails rendering boundary"),
              external("RubyLLM overview", "https://rubyllm.com/overview/", "RubyLLM chat and provider boundary"),
              external("RubyLLM provider tools", "https://rubyllm.com/provider-tools/", "Provider-hosted search and citations"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "RubyLLM persistence and Rails integration"),
              external("RubyLLM instrumentation", "https://rubyllm.com/next/instrumentation/", "RubyLLM notification boundary")
            ),
            evidence: list(
              note("Run", "The durable execution envelope: status, input snapshot, versions, usage, cost, and diagnostic state."),
              note("Attempt", "One provider/model request within a Run, including timing and streamed output state."),
              note("Message", "The conversation record used by the RubyLLM Active Record integration."),
              note("LifecycleEvent", "Safe local metadata about application and adapted provider events; it is not a full trace.")
            ),
            boundaries: list(
              "The app owns the snapshot and audit records; the provider still owns model behavior and provider-specific compatibility.",
              "RubyLLM 2.0.0 is the current project target. Provider web search is opt-in; the model registry does not establish support for every model/protocol.",
              "Provider web search passed a live OpenRouter check on 2026-09-28 (docs/CAPABILITIES.md). OpenRouter reports hosted search as usage counters and citations, not tool-call blocks.",
              "The learning layer explains the path without rendering prompts, credentials, raw provider payloads, or arbitrary source files."
            )
          ),
          Topic.new(
            key: "tool_approval",
            title: "How Tool Approval works",
            kicker: "Allowlist → RubyLLM tool call → durable decision",
            summary: "A tool is code-defined and project-scoped before a model can request it. Approval is a persisted execution decision that can resume the same Run.",
            steps: list(
              step("1. The registry defines the allowed tool surface", "ToolRegistry contains the code-defined tool classes, descriptions, schemas, approval policy, and parallel-safety metadata. Browser input cannot add Ruby."),
              step("2. A new Run freezes the tool contract", "RunExecutor snapshots enabled tool keys, schemas, approval policy, and execution options so later registry changes do not silently rewrite this Run."),
              step("3. ChatTooling configures RubyLLM", "The executor reads the Run snapshot, resolves the project definitions, attaches the RubyLLM tools, and applies the frozen tool options."),
              step("4. Invocation and approval records are synchronized", "ToolInvocationRecorder observes tool calls, sanitizes arguments/results, labels remote calls, and creates or updates ToolInvocation and Approval records."),
              step("5. A decision resumes the conversation", "ApprovalService calls RubyLLM approve or deny, records the human decision and lifecycle event, then enqueues the same Run for continuation.")
            ),
            code_references: list(
              reference("app/services/ai/tool_registry.rb", "Tool registry", "Defines the allowlisted Ruby tool entries and snapshots.", 33, 80, "DEFINITIONS ="),
              reference("app/services/ai/chat_tooling.rb", "RubyLLM configuration", "Attaches snapshot tools and tool options to the chat.", 13, 19, "def configure"),
              reference("app/services/ai/tool_invocation_recorder.rb", "Invocation recorder", "Persists tool calls, sanitizes payloads, and syncs approvals.", 10, 24, "def attach"),
              reference("app/tools/ai/tools/project_snapshot.rb", "A code-defined tool", "Shows the RubyLLM::Tool boundary and read-only execution.", 3, 31, "class ProjectSnapshot"),
              reference("app/services/ai/approval_service.rb", "Approval continuation", "Applies the decision and re-enqueues the Run.", 15, 48, "def decide!")
            ),
            external_references: list(
              external("RubyLLM tools", "https://rubyllm.com/tools/", "RubyLLM tool definition and execution model"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "Persistence around the Rails conversation"),
              external("Turbo Frames handbook", "https://turbo.hotwired.dev/handbook/frames", "The local inspector frame used by this page")
            ),
            evidence: list(
              note("ToolDefinition", "What the Project allows, including name, schema, approval policy, and parallel-safety metadata."),
              note("ToolInvocation", "What the model actually requested and what the application observed as the result."),
              note("Approval", "A durable pending, approved, or denied human decision tied to one invocation."),
              note("LifecycleEvent", "The local timeline entries for request, approval, completion, and failure transitions.")
            ),
            boundaries: list(
              "The browser can enable registered definitions but cannot upload or execute Ruby.",
              "Local tools and provider-hosted tools are different trust boundaries; remote calls are labelled rather than treated as local code.",
              "Approval records a human decision; it does not make a tool safe, correct, or equivalent across providers."
            )
          ),
          Topic.new(
            key: "experiment_comparison",
            title: "How Experiment comparison works",
            kicker: "Frozen definition → model targets → independent Runs",
            summary: "An Experiment stores a structured prompt and a supported schema. Each execution snapshots that definition, resolves at least two configured interactive models, and creates one independent Run per target so results remain comparable and inspectable.",
            steps: list(
              step("1. The definition is parsed at the Rails boundary", "The Experiment form accepts a bounded JSON Schema subset. SchemaDefinition rejects unsupported keys and invalid types before the definition is saved."),
              step("2. The revision becomes the comparison contract", "An Experiment snapshot contains the prompt, schema, generation options, status, and revision. Updating definition fields increments the revision."),
              step("3. The execution selects compatible targets", "The controller accepts provider-qualified model selections. ExperimentExecutor verifies that each target is configured, interactive, and marked as supporting structured output."),
              step("4. Each target receives its own Run", "Inside one Project transaction, the executor creates an ExperimentExecution, a Chat, a queued Run, a first Attempt, and a target snapshot for every resolved model."),
              step("5. StructuredResponseJob validates the result", "The job configures RubyLLM structured output, parses the response as JSON, validates it against the frozen schema, stores a JSON Artifact, and refreshes the parent execution status.")
            ),
            code_references: list(
              reference("app/controllers/experiments_controller.rb", "Definition action", "Parses and saves the schema-backed Experiment definition.", 14, 33, "def create"),
              reference("app/services/ai/schema_definition.rb", "Schema boundary", "Normalizes and validates the supported JSON Schema subset.", 31, 43, "def parse"),
              reference("app/controllers/experiment_executions_controller.rb", "Target selection", "Requires at least two selected models before queueing an execution.", 5, 16, "def create"),
              reference("app/services/ai/experiment_executor.rb", "Comparison materialization", "Snapshots the definition and creates one durable Run per target.", 14, 67, "def enqueue"),
              reference("app/jobs/structured_response_job.rb", "Structured queue handoff", "Moves each child Run into structured execution.", 1, 5, "def perform"),
              reference("app/services/ai/structured_executor.rb", "Structured execution", "Configures RubyLLM, validates JSON, and persists the Artifact/result.", 9, 52, "def call"),
              reference("app/services/ai/schema_validator.rb", "Result validation", "Checks returned values against the saved schema.", 7, 9, "def errors_for")
            ),
            external_references: list(
              external("Rails Active Job basics", "https://guides.rubyonrails.org/active_job_basics.html", "Queued execution boundary"),
              external("RubyLLM overview", "https://rubyllm.com/overview/", "RubyLLM structured model boundary"),
              external("Understanding JSON Schema", "https://json-schema.org/understanding-json-schema/", "Schema concepts behind the supported subset")
            ),
            evidence: list(
              note("Experiment", "The reusable definition, supported schema, generation options, and revision."),
              note("ExperimentExecution", "The comparison-level snapshot, target count, status, and completion state."),
              note("Run and Attempt", "One independent execution record per selected provider/model target."),
              note("Artifact", "The parsed JSON output and the schema-validation metadata for a successful target.")
            ),
            boundaries: list(
              "A valid JSON response proves schema conformance for this run; it does not prove that the answer is factually correct or that one model is generally better.",
              "Target compatibility is currently based on declared catalog capabilities and local configuration; cross-provider behavior still needs separate validation.",
              "This is a local comparison ledger, not a statistical benchmark or a production evaluation report."
            )
          ),
          Topic.new(
            key: "run_inspector",
            title: "How the Run Inspector works",
            kicker: "Run → Attempt → lifecycle/usage/cost",
            summary: "The Run Inspector is a durable evidence view, not a live provider trace. It combines the Run state machine with per-attempt timing, usage, cost status, diagnostics, artifacts, tools, and a safe lifecycle timeline.",
            steps: list(
              step("1. The controller loads one durable envelope", "RunsController loads the Run with its Project, Chat, Attempts, Artifacts, Experiment context, and lifecycle events, then synchronizes observed tool invocations."),
              step("2. Run owns the lifecycle state", "A Run moves through queued, running, waiting for approval, and terminal states. Transitions record local lifecycle events and keep the result summary durable."),
              step("3. Attempt measures one provider request", "AttemptRecorder starts or continues an Attempt, captures time to first output, streamed partial output, token usage, duration, provider/model identity, and normalized cost."),
              step("4. Events are safe and deduplicated", "LifecycleEventRecorder accepts a fixed event catalog, whitelists payload keys, derives an event key, and ignores duplicate inserts instead of creating an unbounded trace."),
              step("5. The page presents evidence with uncertainty", "The inspector shows reported, estimated, or unknown cost, diagnostics, structured Artifacts, tool records, input snapshots, and lifecycle events without implying provider-native tracing.")
            ),
            code_references: list(
              reference("app/controllers/runs_controller.rb", "Inspector action", "Loads the bounded evidence graph and synchronizes tool records.", 25, 33, "def show"),
              reference("app/models/run.rb", "Run state and metrics", "Defines associations, status transitions, token totals, and cost status.", 1, 74, "class Run"),
              reference("app/models/run.rb", "Run lifecycle", "Starts and claims queued executions under a row lock; approval, success, failure and cancellation follow the same pattern.", 76, 114, "def terminal?"),
              reference("app/services/ai/attempt_recorder.rb", "Attempt recorder", "Captures streaming timing, usage, cost, and terminal state.", 24, 79, "def start!"),
              reference("app/services/ai/lifecycle_event_recorder.rb", "Lifecycle event boundary", "Validates events, whitelists payloads, and deduplicates persistence.", 28, 94, "def emit"),
              reference("app/views/runs/show.html.erb", "Inspector presentation", "Renders metrics, Attempts, lifecycle events, tools, snapshots, and results.", 37, 92, "Run metrics")
            ),
            external_references: list(
              external("Rails Active Job basics", "https://guides.rubyonrails.org/active_job_basics.html", "Asynchronous Run execution"),
              external("RubyLLM instrumentation", "https://rubyllm.com/next/instrumentation/", "RubyLLM notification boundary"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "Rails persistence around conversations")
            ),
            evidence: list(
              note("Run", "The durable operation envelope, snapshot, status, versions, summary, and diagnostic state."),
              note("Attempt", "A provider/model request with timing, tokens, status, and cost provenance."),
              note("LifecycleEvent", "A safe local timeline record with a bounded payload and deduplication key."),
              note("Artifact and ToolInvocation", "Structured output and tool evidence attached to the same Run.")
            ),
            boundaries: list(
              "Local lifecycle events are an application audit timeline and an adapter view of RubyLLM notifications, not provider-native distributed tracing.",
              "Cost can be reported, estimated, or unknown; the page does not turn an estimate into an invoice.",
              "A completed local Run proves what this application persisted, not deployment health, provider SLA, or business impact."
            )
          ),
          Topic.new(
            key: "project_boundary",
            title: "How Project boundaries work",
            kicker: "Projects → slug route → scoped workbench resources",
            summary: "A Project is the durable local starting point for Workbench activity. The Projects page lists and creates records, a missing slug is derived from the name, and the resulting slug identifies the workspace routes. Chats, experiments, Knowledge collections, Runs, and tool definitions then stay associated with that Project so related evidence can be inspected together.",
            steps: list(
              step("1. The Projects action prepares the index and form", "ProjectsController loads the ordered Project list and builds an unsaved Project for the model-backed creation form. Model browsing remains available before a Project or provider key exists."),
              step("2. Rails validates and saves the submitted boundary", "The controller permits only name, slug, and description. Project validates the name and slug, derives a blank slug from the name, and redirects to the new workspace after a successful save."),
              step("3. The slug becomes the human-facing route identity", "Project#to_param returns the slug, and nested Rails resources resolve the Project before loading a Chat, Tool Lab, Knowledge collection, or Experiment."),
              step("4. Associations define the owned surface", "Project declares its chats, experiments, executions, knowledge collections, runs, tool definitions, and tool invocations. Dependent behavior makes the ownership model explicit."),
              step("5. Nested controllers keep reads in scope", "Project pages load recent Chats and Runs through the current Project, while nested controllers find child records through that same association rather than accepting a global child id."),
              step("6. Tool execution policy is frozen per Run", "The Project stores the requested sequential or parallel mode. RunExecutor snapshots the effective policy and enabled tool definitions so later settings changes do not rewrite history."),
              step("7. The workspace and inspector reconnect the graph", "Project, Chat, Run, Experiment, and Knowledge pages link back to the same slug and durable records, making ownership visible as each feature is used.")
            ),
            code_references: list(
              reference("app/controllers/projects_controller.rb", "Project index", "Loads the ordered list and unsaved model for the creation form.", 2, 5, "@projects = Project.order(:name)"),
              reference("app/views/projects/index.html.erb", "Project creation form", "Uses Rails model-backed form helpers for the Project fields.", 46, 74, "form_with model: @project"),
              reference("app/controllers/projects_controller.rb", "Project creation", "Permits the form contract, persists the Project, and redirects to its workspace.", 7, 15, "def create"),
              reference("app/models/project.rb", "Slug validation and routing", "Validates slug format and uniqueness, derives a missing slug, and uses it in routes.", 12, 20, "before_validation :derive_slug"),
              reference("app/models/project.rb", "Slug derivation", "Converts the Project name into the default slug before validation.", 54, 56, "name.to_s.parameterize"),
              reference("config/routes.rb", "Nested resource boundary", "Defines Project-owned Chats, tools, Knowledge, Experiments, and Runs.", 6, 22, "resources :projects"),
              reference("app/controllers/projects_controller.rb", "Project page action", "Loads the Project and recent scoped Chats/Runs.", 18, 22, "def show"),
              reference("app/models/project.rb", "Project associations", "Declares the local ownership graph and dependent behavior.", 1, 10, "has_many :chats"),
              reference("app/models/project.rb", "Tool policy storage", "Validates and persists the Project-level tool execution mode.", 22, 42, "def tool_settings"),
              reference("app/services/ai/run_executor.rb", "Run snapshot boundary", "Copies project tool definitions and effective options into a Run.", 14, 30, "def enqueue")
            ),
            external_references: list(
              external("Rails association basics", "https://guides.rubyonrails.org/association_basics.html", "Rails ownership and association boundary"),
              external("Rails Action Controller overview", "https://guides.rubyonrails.org/action_controller_overview.html", "Nested request boundary"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "Conversation persistence inside the Project boundary")
            ),
            evidence: list(
              note("Project", "The durable local scope identified by a slug and primary key."),
              note("Associations", "The explicit graph of chats, runs, experiments, knowledge, and tools owned by the Project."),
              note("Run snapshot", "The effective tool definitions and execution mode frozen at execution time.")
            ),
            boundaries: list(
              "Project is an application organization boundary, not a complete authentication, authorization, or tenant-isolation system.",
              "A nested route scopes record lookup in the application; it does not by itself establish a production security policy.",
              "Deleting a Project follows model-dependent cleanup rules and should not be interpreted as an archival or compliance policy."
            )
          ),
          Topic.new(
            key: "knowledge_ingestion",
            title: "How Knowledge ingestion works",
            kicker: "Text/file source → extraction → provenance → chunks",
            summary: "Knowledge ingestion turns a text or attached file into durable source evidence. It preserves checksums, extractor metadata, provenance Artifacts, deterministic character offsets, and explicit failure states before search can use the chunks.",
            steps: list(
              step("1. The Rails action branches by source type", "KnowledgeItemsController ingests pasted text synchronously and attaches uploaded files through Active Storage before queueing extraction."),
              step("2. The extractor applies bounded capabilities", "Local text-like files are decoded in the app. OCR-capable files require a configured RubyLLM OCR model, a supported type, and the fixed size limit; unsupported input fails explicitly."),
              step("3. DocumentIngestor records provenance", "File extraction updates the source, stores extractor/provider/model/page/byte/checksum metadata, and creates an ocr_document Artifact containing the extracted text."),
              step("4. Ingestor creates deterministic chunks", "The existing ingestion path normalizes text, computes a SHA-256 checksum, deletes stale chunks transactionally, and creates bounded windows with character offsets."),
              step("5. Search can now consume ready evidence", "Only a source with ready ingestion state contributes chunks to retrieval; the later Knowledge Search topic explains ranking and optional rerank separately.")
            ),
            code_references: list(
              reference("app/controllers/knowledge_items_controller.rb", "Source entry", "Branches text and file creation and queues file extraction.", 5, 35, "def create"),
              reference("app/jobs/document_extraction_job.rb", "Extraction job", "Loads the source and invokes the document ingestor in the background.", 1, 10, "def perform"),
              reference("app/services/ai/knowledge/extractor.rb", "Extraction capability gate", "Chooses local extraction or RubyLLM OCR after type and size checks.", 37, 49, "def call"),
              reference("app/services/ai/knowledge/extractor.rb", "OCR boundary", "Calls the configured OCR model and retains provider/model/page metadata.", 71, 103, "def extract_with_ocr"),
              reference("app/services/ai/knowledge/document_ingestor.rb", "File provenance", "Persists extraction metadata and the provenance Artifact before chunking.", 23, 61, "def call"),
              reference("app/services/ai/knowledge/ingestor.rb", "Text ingestion", "Checksums source text and replaces chunks transactionally.", 16, 44, "def call"),
              reference("app/services/ai/knowledge/chunker.rb", "Deterministic chunking", "Creates bounded windows with character offsets and overlap.", 19, 42, "def call")
            ),
            external_references: list(
              external("Rails Active Storage overview", "https://guides.rubyonrails.org/active_storage_overview.html", "Rails file attachment boundary"),
              external("Rails Active Job basics", "https://guides.rubyonrails.org/active_job_basics.html", "Background extraction boundary"),
              external("RubyLLM overview", "https://rubyllm.com/overview/", "Provider-backed OCR boundary")
            ),
            evidence: list(
              note("KnowledgeItem", "Source text, checksum, ingestion/extraction status, and attachment metadata."),
              note("Artifact", "The extraction provenance record containing extractor, provider/model, page count, and checksums."),
              note("KnowledgeChunk", "A deterministic searchable window with source identity and character offsets.")
            ),
            boundaries: list(
              "Current OCR is capability-gated and has no live provider evidence yet, so it supports no broad claims about document fidelity.",
              "Provider file-reference lifecycle, remote URL fetching, and page-level chunk provenance are not silently implied by this local path.",
              "A ready chunk is indexed evidence; it is not an LLM-generated summary or a citation guarantee."
            )
          ),
          Topic.new(
            key: "knowledge_search",
            title: "How Knowledge Search works",
            kicker: "Source → Chunk → Evidence → optional rerank",
            summary: "Knowledge search is a separate, inspectable evidence flow. It stores source provenance and score components; it does not silently turn retrieved text into an LLM answer.",
            steps: list(
              step("1. A source enters through a bounded Rails action", "Text sources are ingested synchronously. Uploaded files are attached through Active Storage and handed to DocumentExtractionJob for extraction."),
              step("2. Extraction and chunking preserve provenance", "DocumentIngestor records extractor metadata and a provenance Artifact, then Ingestor normalizes text, computes a checksum, and creates deterministic character-window chunks."),
              step("3. Search resolves the requested mode", "Search chooses lexical, semantic, or hybrid retrieval. Semantic modes require configured embeddings and fresh vectors; otherwise the outcome records an explicit lexical degradation."),
              step("4. Retrieval returns inspectable evidence", "Retriever returns chunks with score, matched terms, lexical score, cosine similarity, source, and character offsets. These are evidence fields, not an answer."),
              step("5. Compatible rerank is optional", "When a compatible rerank model is configured, the second stage changes ordering and records rerank score and pre-rank; unavailable rerank leaves original evidence intact.")
            ),
            code_references: list(
              reference("app/controllers/knowledge_items_controller.rb", "Source entry point", "Branches text ingestion and file upload into the appropriate path.", 5, 35, "def create"),
              reference("app/jobs/document_extraction_job.rb", "Background extraction", "Hands an attached file to the document ingestor.", 1, 10, "Ai::Knowledge::DocumentIngestor.call"),
              reference("app/services/ai/knowledge/document_ingestor.rb", "Provenance extraction", "Stores extraction metadata and the provenance Artifact.", 23, 61, "def call"),
              reference("app/services/ai/knowledge/ingestor.rb", "Deterministic ingestion", "Checksums the text and replaces its chunks transactionally.", 16, 44, "def call"),
              reference("app/services/ai/knowledge/chunker.rb", "Chunker", "Creates bounded character windows and offsets.", 19, 42, "def call"),
              reference("app/services/ai/knowledge/search.rb", "Search orchestration", "Resolves retrieval and optional rerank outcomes.", 52, 84, "def call"),
              reference("app/services/ai/knowledge/retriever.rb", "Evidence ranking", "Produces lexical, semantic, and hybrid evidence results.", 25, 43, "def search")
            ),
            external_references: list(
              external("Rails Active Storage overview", "https://guides.rubyonrails.org/active_storage_overview.html", "Rails file attachment boundary"),
              external("RubyLLM overview", "https://rubyllm.com/overview/", "RubyLLM provider-backed model boundary"),
              external("RubyLLM Rails integration", "https://rubyllm.com/rails/", "RubyLLM inside a Rails application")
            ),
            evidence: list(
              note("KnowledgeItem", "The normalized source record, checksum, ingestion status, and file/extraction metadata."),
              note("KnowledgeChunk", "A deterministic searchable window with source identity and character offsets."),
              note("KnowledgeEmbedding", "A provider/model-specific vector tied to the chunk checksum."),
              note("Artifact", "The extracted document provenance record, including extractor, model, page count, and checksums.")
            ),
            boundaries: list(
              "Current retrieval is SQLite-bounded and explicit about semantic/hybrid degradation; it is not a claim of universal provider RAG quality.",
              "Provider file references, live OCR evidence, page-level provenance, and remote URL fetching are outside this topic's implemented path.",
              "Search evidence is not an LLM answer, citation guarantee, production deployment result, or business outcome."
            )
          )
        ].freeze
      end

      def list(*items)
        items.freeze
      end

      def step(title, body)
        Step.new(title:, body:)
      end

      def note(label, body)
        Note.new(label:, body:)
      end

      def reference(path, label, role, start_line, end_line, anchor)
        CodeReference.new(path:, label:, role:, start_line:, end_line:, anchor:)
      end

      def external(label, url, role)
        ExternalReference.new(label:, url:, role:)
      end
    end
  end
end
