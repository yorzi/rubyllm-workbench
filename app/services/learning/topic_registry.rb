module Learning
  CodeReference = Data.define(:path, :label, :role, :start_line, :end_line, :anchor)
  ExternalReference = Data.define(:label, :url, :role)
  Note = Data.define(:label, :body)
  Step = Data.define(:title, :body)

  Topic = Data.define(
    :key,
    :title,
    :kicker,
    :summary,
    :steps,
    :code_references,
    :external_references,
    :evidence,
    :boundaries
  )

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
            key: "chat_run",
            title: "How a Chat Run works",
            kicker: "Chat → Run → Attempt → RubyLLM",
            summary: "A prompt becomes a durable Run before provider code runs, so the Workbench can show what was requested, which tools were frozen, and how the attempt finished.",
            steps: list(
              step("1. The Rails action accepts the message", "MessagesController checks the selected model and hands the bounded prompt to Ai::RunExecutor. The page then redirects back to the Chat; execution is asynchronous."),
              step("2. The application creates the evidence boundary", "RunExecutor snapshots enabled tools, tool policy, app version, RubyLLM version, provider, model, and the first Attempt before enqueueing ChatResponseJob."),
              step("3. The job enters the ChatExecutor", "ChatResponseJob loads the Run. ChatExecutor claims it, starts the Attempt, configures the RubyLLM chat, and executes ask or complete inside the Run/Attempt execution context."),
              step("4. Streaming and tool records are persisted", "The executor observes streamed content and ToolInvocationRecorder synchronizes RubyLLM tool calls into local invocation, approval, result, and lifecycle records."),
              step("5. RubyLLM notifications are adapted", "The instrumentation adapter listens to RubyLLM notifications and maps a safe subset to local ai.provider.* lifecycle events. This is an adapter boundary, not provider-native tracing.")
            ),
            code_references: list(
              reference("app/controllers/messages_controller.rb", "Rails entry point", "Validates the model and enqueues the Run.", 5, 22, "Ai::RunExecutor.enqueue"),
              reference("app/services/ai/run_executor.rb", "Run creation and snapshot", "Creates the durable Run and first Attempt.", 14, 42, "def enqueue"),
              reference("app/jobs/chat_response_job.rb", "Queue handoff", "Moves the durable Run into the executor.", 1, 5, "Ai::ChatExecutor.new"),
              reference("app/services/ai/chat_executor.rb", "Chat execution", "Claims, configures, streams, and completes the Attempt.", 8, 41, "def call"),
              reference("app/services/ai/ruby_llm_instrumentation.rb", "RubyLLM adapter", "Maps RubyLLM notifications to local lifecycle evidence.", 24, 36, "ActiveSupport::Notifications.subscribe")
            ),
            external_references: list(
              external("Rails Action Controller overview", "https://guides.rubyonrails.org/action_controller_overview.html", "Rails request/action boundary"),
              external("Rails Action View overview", "https://guides.rubyonrails.org/action_view_overview.html", "Rails rendering boundary"),
              external("RubyLLM overview", "https://rubyllm.com/overview/", "RubyLLM chat and provider boundary"),
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
              "RubyLLM 2.0.0.rc4 is the current project target. This page does not claim that every provider exposes identical behavior.",
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
              "Provider file references, real OCR dogfood, page-level provenance, and remote URL fetching are outside this topic's implemented path.",
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
