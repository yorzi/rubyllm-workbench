# Architecture

These diagrams are a hand-maintained view of the current implementation. They
are not a generated ERD or a promise about future design; code, migrations and
tests remain the source of truth.

Updated: 2026-09-28

## How to read the diagrams

- Start with L0 for the system boundary, then L1 for code responsibilities,
  then the data, sequence or state diagram for your question.
- A `Run` is one execution a person can reason about; an `Attempt` is one
  provider/model request inside it.
- `ToolDefinition` is what is allowed, `ToolInvocation` is what was actually
  requested, and `Approval` is what a person decided.
- `LifecycleEvent` indexes those changes over time. It does not replace the
  records and is not provider tracing.
- `ToolExecutionPolicy` binds a Project's sequential/parallel intent to
  RubyLLM's `calls` and `concurrency` options on each new Run, and falls back
  explicitly when capability or safety conditions are not met.
- Status labels: `IMPLEMENTED` exists and is tested; `PARTIAL` exists with
  incomplete evidence; `PLANNED` does not exist yet.

## 1. L0: system context

```mermaid
flowchart LR
    Human["Person / local developer"] --> UI["Rails HTML + Turbo UI"]
    UI --> App["Rails Workbench"]
    App --> DB[("SQLite\nrecords, knowledge chunks, lifecycle events")]
    App --> Queue["Solid Queue\nChat, Agent, media and evaluation jobs\n+ stale-work recovery"]
    Queue --> RubyLLM["RubyLLM boundary"]
    App --> RubyLLM
    RubyLLM --> Providers["Configured providers\nOpenRouter, OpenAI, Anthropic, ..."]
    App --> Blobs["Active Storage\nlocal disk"]
```

Every provider operation crosses the RubyLLM boundary; Workbench never calls a
provider SDK or HTTP API directly. Evidence lands in SQLite and Active Storage.
Remote deployment, accounts and public access are outside this picture.

## 2. L1: how the components connect

```mermaid
flowchart TD
    subgraph UI["Pages"]
        ChatUI["Project Chat"]
        MediaUI["Speech / image / video / transcription"]
        ExperimentUI["Experiments"]
        ToolUI["Tool Lab"]
        KnowledgeUI["Knowledge workspace"]
        AgentUI["Agent definitions"]
        EvaluationUI["Evaluation datasets"]
        RunUI["Run history + inspector"]
    end

    RunExecutor["Ai::RunExecutor"]
    ChatJob["ChatResponseJob"]
    ChatExecutor["Ai::ChatExecutor"]
    ExperimentExecutor["Ai::ExperimentExecutor"]
    StructuredJob["StructuredResponseJob"]
    StructuredExecutor["Ai::StructuredExecutor"]
    AgentRunExecutor["Ai::AgentRunExecutor"]
    AgentJob["AgentRunJob\nActiveJob::Continuable"]
    Heartbeat["Ai::AgentLeaseHeartbeat"]
    AgentReport["Ai::AgentResearchReportRecorder"]
    MediaRuns["Speech/Image/Video/TranscriptionRunJob\n+ recovery jobs"]
    EvaluationExecutor["Ai::EvaluationExecutor"]
    EvaluationJobs["EvaluationCaseJob, judge and Batch jobs\n+ recovery"]
    Exporter["Ai::RunReproductionExporter"]
    Tooling["ToolRegistry + ChatTooling\n+ ToolExecutionPolicy"]
    Audit["ToolInvocationRecorder + ApprovalService"]
    Evidence["CitationSetRecorder + ProviderToolActivity"]
    KnowledgeServices["Ai::Knowledge::Ingestor, Chunker,\nEmbedder, Knowledge::Retriever, Search,\nVectorStore, Reranker"]
    Events["LifecycleEventRecorder"]
    ProviderEvents["Ai::RubyLlmInstrumentation\n*.ruby_llm adapter"]
    Internals["Ai::RubyLlmInternals\n+ lib/ruby_llm_workarounds"]
    Records["Records: Project, Chat, Run, Attempt, Artifact,\ntools, Knowledge, Evaluation, LifecycleEvent"]
    RubyLLM["RubyLLM: Chat, Agent, embed, rerank,\nspeak, paint, animate, transcribe"]

    ChatUI --> RunExecutor --> ChatJob --> ChatExecutor
    ExperimentUI --> ExperimentExecutor --> StructuredJob --> StructuredExecutor
    AgentUI --> AgentRunExecutor --> AgentJob
    AgentJob --> Heartbeat
    AgentJob --> AgentReport
    MediaUI --> MediaRuns
    EvaluationUI --> EvaluationExecutor --> EvaluationJobs --> StructuredExecutor
    KnowledgeUI --> KnowledgeServices
    ToolUI --> Tooling
    Tooling --> ChatExecutor
    Tooling --> AgentJob
    RunUI --> Exporter
    ChatExecutor --> Audit
    AgentJob --> Audit
    ChatExecutor --> Evidence
    AgentJob --> Evidence
    ChatExecutor --> RubyLLM
    AgentJob --> RubyLLM
    StructuredExecutor --> RubyLLM
    MediaRuns --> RubyLLM
    KnowledgeServices --> RubyLLM
    AgentJob --> Internals
    Internals -.-> RubyLLM
    RubyLLM -. "instrumentation" .-> ProviderEvents
    Audit --> Records
    Evidence --> Records
    AgentReport --> Records
    MediaRuns --> Records
    EvaluationJobs --> Records
    KnowledgeServices --> Records
    Exporter --> Records
    Events --> Records
    ProviderEvents --> Records
    ChatExecutor --> Events
    AgentJob --> Events
    StructuredExecutor --> Events
```

Responsibilities in short:

1. Controllers accept page intent. Executors (`RunExecutor`,
   `AgentRunExecutor`, `ExperimentExecutor`, `EvaluationExecutor`, media
   executors) create a snapshotted Run and enqueue work.
2. Jobs perform the work: `ChatExecutor` for chats, `AgentRunJob` for Agents
   (rebuilt from the Run snapshot on every resume), `StructuredExecutor` for
   schema-validated output.
3. `ToolRegistry` and `ChatTooling` expose only code-registered tools; the
   recorder and `ApprovalService` turn calls and decisions into records.
4. `CitationSetRecorder` and `ProviderToolActivity` capture provider-hosted
   evidence: citations, discrete server tool calls and usage-only counters.
5. `Ai::RubyLlmInternals` lists every private RubyLLM seam Workbench uses, and
   `lib/ruby_llm_workarounds` holds temporary, self-disabling upstream fixes.

## 3. L2: persistence

Messages are RubyLLM's persisted records; do not confuse them with Runs.

```mermaid
erDiagram
    PROJECT ||--o{ CHAT : owns
    PROJECT ||--o{ EXPERIMENT : defines
    PROJECT ||--o{ AGENT_DEFINITION : defines
    PROJECT ||--o{ TOOL_DEFINITION : enables
    PROJECT ||--o{ KNOWLEDGE_COLLECTION : owns
    PROJECT ||--o{ EVALUATION_DATASET : owns
    PROJECT ||--o{ EVALUATION_COMPARISON : owns
    PROJECT ||--o{ RUN : contains
    CHAT ||--o{ MESSAGE : persists
    CHAT ||--o{ RUN : starts
    EXPERIMENT ||--o{ EXPERIMENT_EXECUTION : runs
    EXPERIMENT_EXECUTION ||--o{ RUN : groups
    EVALUATION_DATASET ||--o{ EVALUATION_DATASET_REVISION : versions
    EVALUATION_DATASET_REVISION ||--o{ EVALUATION_COMPARISON : evaluated_by
    EVALUATION_COMPARISON ||--|{ EVALUATION_EXECUTION : compares_models
    EVALUATION_EXECUTION ||--o{ EVALUATION_CASE_RESULT : measures
    EVALUATION_CASE_RESULT }o--o| RUN : links
    EVALUATION_CASE_RESULT ||--o{ EVALUATION_CASE_REVIEW : reviewed_by
    EVALUATION_CASE_RESULT ||--o| EVALUATION_CASE_JUDGMENT : judged_by
    RUN ||--o{ ATTEMPT : retries
    RUN ||--o{ ARTIFACT : produces
    RUN ||--o{ TOOL_INVOCATION : audits
    RUN ||--o{ LIFECYCLE_EVENT : explains
    RUN ||--o{ AGENT_RUN_DELIVERY : dispatches
    ATTEMPT ||--o{ ARTIFACT : may_attach
    TOOL_DEFINITION ||--o{ TOOL_INVOCATION : describes
    TOOL_INVOCATION ||--o| APPROVAL : requests
    KNOWLEDGE_COLLECTION ||--o{ KNOWLEDGE_ITEM : contains
    KNOWLEDGE_ITEM ||--o{ KNOWLEDGE_CHUNK : splits
    KNOWLEDGE_CHUNK ||--o{ KNOWLEDGE_EMBEDDING : embeds

    RUN {
        string operation
        string status
        json input_snapshot_json
        json result_summary_json
        string agent_execution_token
        integer agent_execution_generation
    }
    ATTEMPT {
        integer sequence
        string provider
        string model_id
        string status
        integer input_tokens
        integer output_tokens
        decimal reported_cost
        decimal estimated_cost
        string finish_reason
    }
    ARTIFACT {
        string kind
        json content_json
        text content_text
        json metadata_json
    }
    LIFECYCLE_EVENT {
        string name
        string event_key
        string source
        datetime occurred_at
        json payload_json
    }
    TOOL_INVOCATION {
        string tool_call_id
        string tool_key
        string status
        boolean remote
        json arguments_json
        json result_json
        string error_code
    }
    APPROVAL {
        string status
        string actor
        datetime requested_at
        datetime decided_at
    }
    AGENT_DEFINITION {
        integer revision
        string provider
        string model_id
        json tool_keys_json
        json provider_tools_json
    }
    KNOWLEDGE_CHUNK {
        integer position
        integer char_start
        integer char_end
    }
    KNOWLEDGE_EMBEDDING {
        string model_id
        integer dimensions
        binary vector
        string content_checksum
    }
    EVALUATION_CASE_RESULT {
        string case_key
        string status
        boolean passed
        string transport_status
        string schema_status
    }
```

Remember when reading it:

- `input_snapshot_json` is historical evidence. Later tool toggles, schema
  edits or model choices never rewrite it.
- LifecycleEvent stores only allowlisted IDs, statuses, provider/model,
  durations and error categories. `event_key` deduplication makes recording
  idempotent; Runs from before the catalog existed are not backfilled.
- AgentDefinition is an editable template. A Run copies its revision into the
  snapshot and has no foreign key to it, so deleting a template never changes
  old Runs.
- An Artifact is owned by a Run (execution evidence) or a KnowledgeItem
  (document provenance).
- KnowledgeEmbedding is unique per (chunk, model). Retrieval compares vectors
  only within one model, and skips vectors whose checksum no longer matches
  the chunk. The opt-in `sqlite_vector_extension` adapter keeps derived
  per-dimension tables (`knowledge_vector_index_<dimension>`) that can be
  rebuilt and are not in `db/schema.rb`.

## 4. Runtime: Chat Run with approval

The continuation reuses the persisted RubyLLM conversation and never appends
the original prompt again.

```mermaid
sequenceDiagram
    autonumber
    actor Human
    participant UI as Chat UI
    participant RE as Ai::RunExecutor
    participant DB as SQLite / RubyLLM records
    participant Q as ChatResponseJob
    participant CE as Ai::ChatExecutor
    participant LLM as RubyLLM + provider
    participant Audit as Recorder / ApprovalService
    participant Events as LifecycleEventRecorder

    Human->>UI: Submit prompt
    UI->>RE: enqueue(chat, project, prompt)
    RE->>DB: Create queued Run + Attempt atomically
    RE->>DB: Freeze prompt, tools, approval policy, tool options
    RE->>Events: ai.run.created
    RE->>Q: perform_later(run_id)
    Q->>CE: call(run_id)
    CE->>DB: Claim Run, start Attempt
    CE->>Events: ai.run.started + ai.attempt.started
    CE->>LLM: Configure tools/options from snapshot, ask(prompt)
    LLM-->>CE: Streamed chunks / tool call
    CE->>DB: Save Message, usage, Attempt metrics
    CE->>Events: ai.attempt.streaming (first output)

    alt Tool needs approval
        CE->>Audit: Record ToolInvocation + Approval
        Audit->>DB: Pending approval, Run = waiting_for_approval
        Audit->>Events: ai.tool.requested + ai.approval.requested
        DB-->>UI: Show pending call
        Human->>UI: Approve or deny
        UI->>Audit: Record decision
        Audit->>DB: Update Approval and ToolInvocation
        Audit->>LLM: Record RubyLLM conversation decision
        Audit->>Events: ai.approval.decided
        Audit->>Q: Enqueue continuation
        Q->>CE: call(run_id)
        CE->>DB: Claim waiting Run, new Attempt, no new user prompt
        CE->>Events: ai.run.resumed + ai.attempt.started
        CE->>LLM: complete()
        LLM-->>CE: Tool result / final answer
        CE->>DB: Run = succeeded or failed
        CE->>Events: ai.attempt.* + ai.run.*
    else No approval needed
        CE->>Audit: Record each ToolInvocation (per call when parallel)
        Audit->>Events: ai.tool.requested / completed per call
        CE->>LLM: Continue conversation
        LLM-->>CE: Final answer
        CE->>DB: Run = succeeded
        CE->>Events: ai.attempt.succeeded + ai.run.succeeded
    end
```

Safety boundary: Tool Lab manages a Project-scoped allowlist. Browser input
cannot upload Ruby or turn shell/code into a tool, and displayed arguments and
results filter obvious secret fields. If event persistence fails, the main
execution continues; the records remain the source of truth.

## 4.1 Runtime: parallel tool-call policy

Parallel calls are an explicit application opt-in, never assumed from the
provider.

```mermaid
flowchart TD
    Setting["Project Tool Lab\nsequential / parallel"] --> Policy["Ai::ToolExecutionPolicy"]
    Model["RubyLLM model capabilities"] --> Policy
    Tools["Enabled ToolDefinition\nparallel_safe?"] --> Policy
    Policy --> Decision{"All conditions met?"}
    Decision -- "yes" --> Parallel["effective parallel\ncalls: many\nconcurrency: threads"]
    Decision -- "no" --> Fallback["effective sequential\ncalls: one\n+ fallback_reason"]
    Parallel --> Snapshot["Run input_snapshot"]
    Fallback --> Snapshot
    Snapshot --> ChatTooling["Ai::ChatTooling\nwith_tool_options"]
    ChatTooling --> RubyLLM["RubyLLM conversation loop"]
    RubyLLM --> Recorder["ToolInvocationRecorder\nmutex-protected callbacks"]
    Recorder --> Inspector["Run inspector\nseparate calls + events"]
```

`project_snapshot` is parallel-safe; `save_run_note` writes an Artifact and is
sequential-only. There is local evidence for the policy, but no live provider
has been observed returning parallel calls.

## 4.2 Runtime: Knowledge retrieval

Knowledge is a separate product flow, not a Chat Run.

```mermaid
flowchart TD
    Human["Person"] --> CollectionUI["Knowledge workspace"]
    CollectionUI --> Item["KnowledgeItem\nnormalized text + checksum"]
    Item --> Ingestor["Ai::Knowledge::Ingestor"]
    Ingestor --> Chunker["Ai::Knowledge::Chunker\n800 chars / 120 overlap"]
    Chunker --> Chunks[("KnowledgeChunk\nposition + char offsets")]
    CollectionUI --> Embed["Embed / re-embed / clear"]
    Embed --> Catalog["EmbeddingCatalog\ncapability + configuration gate"]
    Catalog --> Embedder["Ai::Knowledge::Embedder\nbatch + per-chunk fallback"]
    Chunks --> Embedder
    Embedder --> RubyLLM["RubyLLM.embed"]
    Embedder --> Vectors[("KnowledgeEmbedding\nunique per chunk + model\nFloat32 vector + checksum")]
    CollectionUI --> Query["Query + mode"]
    Query --> Search["Ai::Knowledge::Search\nmode resolution + degradation"]
    Search --> Retriever["Ai::Knowledge::Retriever\nlexical / semantic / hybrid"]
    Chunks --> Retriever
    Vectors --> Retriever
    Retriever --> Adapter["Ai::Knowledge::VectorStore\napplication cosine (default)\nsqlite-vector extension (opt-in)"]
    Retriever --> Evidence["score, cosine, lexical,\nmatched terms, source chunk"]
    Evidence --> Reranker["Ai::Knowledge::Reranker\nRubyLLM.rerank (optional)"]
    Reranker --> Final["rerank score + pre/post rank\nretrieval evidence unchanged"]
```

Degradation is explicit: semantic and hybrid need a selected embedding model,
a configured provider, stored vectors and a query embedding. When any is
missing, `Search` returns lexical evidence and the page states the requested
mode and the reason. File sources go through `DocumentExtractionJob` (local
reading or provider OCR) and leave an `ocr_document` provenance Artifact before
chunking.

## 4.3 Runtime: saved Agent Run

```mermaid
sequenceDiagram
    autonumber
    actor Human
    participant UI as Agent definition page
    participant Launcher as Ai::AgentRunExecutor
    participant DB as SQLite / RubyLLM records
    participant Outbox as AgentRunDelivery
    participant Dispatcher as Recurring dispatcher
    participant Job as AgentRunJob
    participant Agent as RubyLLM Agent
    participant Provider as Provider

    Human->>UI: Enter a task
    UI->>Launcher: Launch current revision
    Launcher->>DB: Create dedicated Chat, Run, Attempt, frozen snapshot
    Launcher->>Outbox: Persist execute intent (same transaction)
    Dispatcher->>Outbox: Claim due delivery
    Dispatcher->>Job: Enqueue AgentRunJob
    Job->>DB: Claim lease (token + generation), start heartbeat
    Job->>DB: Rebuild Agent from snapshot, persist prompt once
    loop Each Agent step
        Job->>Agent: step
        Agent->>Provider: Request (when generating)
        Provider-->>Agent: Message / tool call / citations
        Job->>DB: Attempt, tool records, citations, usage, step event (lease-fenced)
        opt Approval required
            Job->>DB: Run = waiting_for_approval
            Human->>DB: Approve or deny
            DB->>Outbox: Approval continuation (same transaction)
        end
    end
    opt Final answer present
        Job->>DB: Report Artifact + Run succeeded (one transaction)
    end
    opt Empty final answer
        Job->>DB: Run failed with finish reason
    end
```

Guarantees and limits:

- `AgentRunJob` uses Rails `ActiveJob::Continuable` and checkpoints between
  steps; every resume rebuilds the Agent from the snapshot and transcript.
- A random owner token, an increasing generation and a 5-minute lease stop two
  live owners from writing the same Run. `Ai::AgentLeaseHeartbeat` renews the
  lease every 15 seconds during long provider calls.
- Transcript writes, usage rows (through `Ai::RubyLlmInternals`), streamed
  output and local tool writes are checked against the lease inside the Run's
  row lock. A stale job cannot move `waiting_for_approval` back to `running`.
- Delivery is at least once across two databases: the outbox (primary) and
  Solid Queue. Duplicates are fenced by the lease. A provider request already
  accepted cannot be undone, so a crash can repeat a request and its cost.
- The recurring scheduler must run for dispatch and recovery to drain. The
  Runtime panel shows scheduler, dispatcher and maintenance worker heartbeats
  and due outbox deliveries.

## 5. Runtime: Run states

```mermaid
stateDiagram-v2
    [*] --> queued: create Run
    state "waiting_for_approval" as WaitingForApproval
    queued --> running: worker claims
    running --> WaitingForApproval: tool needs a decision
    WaitingForApproval --> running: approve/deny + continuation
    running --> succeeded: finished, no pending approvals
    running --> failed: provider, tool or validation failure
    queued --> failed: job could not start
    queued --> cancelled: cancel
    running --> cancelled: cancel
    WaitingForApproval --> cancelled: cancel
    succeeded --> [*]
    failed --> [*]
    cancelled --> [*]
```

Approvals move `pending -> approved | denied | expired`. ToolInvocations can go
`requested -> running -> succeeded | failed`, or become `denied` or
`cancelled`. Cancelling or failing a Run closes pending approvals; an approved
remote call without a saved provider result is marked
`remote_tool_outcome_unknown` and blocks further use of that Chat. The Run's
badge alone does not tell you whether a tool really ran.

## 6. Runtime: the LifecycleEvent catalog

```mermaid
flowchart LR
    Transition["Run / Attempt / Artifact\nstate changes"] --> Notify["ActiveSupport::Notifications"]
    Tooling["Tool / Approval recorders"] --> Notify
    Notify --> Filter["LifecycleEventRecorder\nfixed names + payload allowlist"]
    Filter --> Dedupe["event_key deduplication"]
    Dedupe --> Catalog[("LifecycleEvent")]
    Catalog --> Inspector["Run inspector timeline"]
    RubyLLM["*.ruby_llm notifications"] --> Adapter["Ai::RubyLlmInstrumentation\n+ ExecutionContext"]
    Adapter --> Catalog
```

Application events are grouped as Run (`created`, `started`, `resumed`,
`waiting_for_approval`, `succeeded`, `failed`, `cancelled`), Agent (`step`),
Attempt (`started`, `streaming`, `succeeded`, `failed`, `cancelled`), Tool
(`requested`, `completed`, `cancelled`), Approval (`requested`, `decided`,
`expired`) and Artifact (`created`). RubyLLM notifications carry RubyLLM's own
chat object rather than application records, so `Ai::ExecutionContext`
publishes the current Run and Attempt and the adapter writes
`ai.provider.*` events (`source = ruby_llm`). Knowledge embedding and rerank
calls have no Run and are not cataloged. The catalog supports the inspector
timeline; it is not provider-native tracing, an event bus or a cost dashboard.

## 7. Milestones

```mermaid
flowchart LR
    M0["M0 Foundation\nIMPLEMENTED"] --> M1["M1 Chat + Runs\nIMPLEMENTED"]
    M1 --> M2["M2 Structured compare\nIMPLEMENTED"]
    M2 --> M3["M3 Tools + approval\nIMPLEMENTED"]
    M3 --> M3P["M3 Parallel calls\nAPP PATH IMPLEMENTED"]
    M3P --> M4["M4 Knowledge\nIMPLEMENTED\n(OCR live evidence PARTIAL)"]
    M4 --> M5["M5 Search + saved Agents\nIMPLEMENTED"]
    M5 --> M6["M6 Media\nPARTIAL (experimental)"]
    M6 --> M7["M7 Evaluations\nIMPLEMENTED\n(Batch live evidence PARTIAL)"]
    M7 --> M8["M8 Export + upstream reports\nIMPLEMENTED / PARTIAL"]
```

`APP PATH IMPLEMENTED` means the Project opt-in, capability and safety gates,
Run snapshot and multi-call audit exist and pass deterministic tests, while
live parallel returns remain unverified. Evidence per operation is in
[CAPABILITIES.md](CAPABILITIES.md).

## Keeping these diagrams honest

Check this page in the same change whenever you alter an entity or migration,
a state transition, a job, the provider boundary, tool approval, Artifact
production or a page entry point:

1. Compare with the code and tests; mark verified paths `IMPLEMENTED` or
   `PARTIAL`, and anything not built `PLANNED`.
2. Never draw a future node as a current dependency.
3. Record the change in [CHANGELOG.md](CHANGELOG.md).

When a diagram and the code disagree, fix the diagram.
