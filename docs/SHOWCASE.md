# Showcase guide

Updated: 2026-10-09 · Rails 8.1.4 · RubyLLM 2.1.0

This project demonstrates how AI work becomes reliable Rails application
state. Its strongest evidence is the implementation of snapshots, approvals,
request accounting and failure recovery, rather than the number of model APIs
in the navigation. Use this guide to inspect those decisions in ten minutes.

## Start without an API key

For a viewer, follow [DEMO.md](DEMO.md). For the editable local workbench,
follow the [quickstart](../README.md#quickstart), run
`bin/rails workbench:demo`, and open the **Demo tour** Project. The tour has
nine Runs and a two-model/two-case synthetic comparison. Every tour Run
is labelled synthetic. These records demonstrate the interface and data
relationships; they are not provider responses or performance measurements.

| Minutes | Visit | Inspect | Design question |
| --- | --- | --- | --- |
| 0–2 | Project → Chat → its Run | Messages, frozen input, Attempts, first output, finish reason | Can the browser disconnect without losing the result? |
| 2–4 | The approved-tool Run | ToolInvocation, Approval, decision and linked Artifact | What does approving a side effect authorize? |
| 4–6 | Agents → How this works → Agent Run | Execution map, outbox, lease generation, report and citations | What happens after a duplicate delivery, cancellation or worker crash? |
| 6–8 | Knowledge → lexical search for `database jobs` | Source chunks, offsets, checksum, matched terms | What evidence supports a retrieval result, and when does semantic search fall back? |
| 8–10 | Evaluations → How this works; failed Run → export | Revision, transport/schema outcomes, exact match, independent review; diagnostics and redacted reproduction | Does a valid JSON response establish quality? What can safely be shared? |

For recovery, run the deterministic tests linked below. The tour contains
finished records; it does not simulate a worker crash or perform an approval
in real time. A live walkthrough requires an explicitly configured provider
and an intentional call. Keep [capability evidence](CAPABILITIES.md) beside
any recording or presentation.

## Skills with inspectable evidence

| Competency | Implementation to read | Verification to inspect | Current limit |
| --- | --- | --- | --- |
| Provider-neutral configuration and model selection | `Ai::ModelCatalog`, `config/initializers/ruby_llm.rb` | `test/services/ai/model_catalog_test.rb` | Registry capability is an admission hint; account/model availability is checked by the provider. |
| Persisted conversations and streaming | `Chat`, `Message`, `Ai::ChatExecutor`, `Ai::ChatContextSnapshot` | `test/services/ai/chat_executor_test.rb`, `test/integration/workbench_flow_test.rb` | Local tests use doubles; live evidence is versioned separately. |
| Structured output beyond parsing JSON | `Ai::SchemaDefinition`, `Ai::SchemaValidator`, `Ai::StructuredExecutor` | `test/services/ai/structured_executor_test.rb` | The app supports a bounded schema subset; validity does not establish meaning. |
| Tools, approvals and safe concurrency | `Ai::ChatTooling`, `Ai::ToolExecutionPolicy`, `Ai::ApprovalService` | `test/integration/tool_approval_flow_test.rb`, `test/services/ai/tool_execution_policy_test.rb` | Registered tools only; parallel calls have local evidence. |
| Rails transactions, outbox and locking | `Ai::AgentRunExecutor`, `AgentRunDelivery`, `Run::AgentExecutionLease` | `test/integration/agent_run_worker_replay_test.rb`, `test/integration/agent_run_cancellation_race_test.rb` | Local fencing does not guarantee exactly-once provider side effects. |
| Active Job continuations and recovery | `AgentRunJob`, `Ai::AgentLeaseHeartbeat`, recovery jobs | `test/jobs/agent_run_job_test.rb`, `test/jobs/evaluation_case_recovery_job_test.rb` | SQLite concurrency and large-scale throughput are unmeasured. |
| Retrieval provenance and vector compatibility | `Ai::Knowledge::{Chunker,Embedder,Retriever,Search,VectorStore,Reranker}` | `test/integration/knowledge_flow_test.rb`, Knowledge service tests | Original MIT case corpus exists; retrieval quality remains unmeasured. |
| Grounded answers and asynchronous request boundaries | `Ai::Knowledge::{EvidenceSnapshot,GroundedAnswer,GroundedAnswerExecutor,GroundedResponse}` | `test/integration/grounded_answer_flow_test.rb`, grounded-answer service/system tests | Bounded lexical/semantic/hybrid/reranked workflow with owned usage; quotes prove provenance, not semantic correctness. [Walkthrough](GROUNDED_ANSWERS.md). |
| Honest evaluation methodology | `EvaluationDatasetRevision`, `Ai::EvaluationExecutor`, `Ai::EvaluationCaseOutcome`, `Ai::EvaluationMetrics` | `test/integration/evaluation_flow_test.rb`, evaluation metrics tests | Exact match, human review and uncalibrated model review are distinct; native saved-answer Evaluation assertions/reviewer are integrated; supported typed Judge is locally verified and live remains manual. |
| Batch uncertainty and reconciliation | `EvaluationBatchSubmissionJob`, `EvaluationBatchRefreshJob`, `Ai::EvaluationBatchResults` | `test/jobs/evaluation_batch_workflow_test.rb` | Requires a complete submitted-chat manifest; no live Batch acceptance yet. |
| Accounting and observability | `Ai::AttemptRecorder`, `Ai::CostNormalizer`, `Ai::RubyLlmInstrumentation` | Recorder, cost and instrumentation service tests | Persisted ledger costs lack original reported/estimated provenance; OpenTelemetry export is planned. |
| Active Storage lifecycle and upload boundaries | `Ai::MediaBlobStorage`, attachment validator, purge/recovery jobs | `test/integration/media_run_flow_test.rb`, attachment boundary tests | Video recovery and ledger attribution are incomplete; format checks are not a malware scanner. |
| Hotwire and source-anchored explanations | Turbo views, Stimulus form state, `Learning::TopicRegistry`, `Learning::Flow`, `Learning::SourceReader` | `test/integration/learning_explanation_flow_test.rb`, `test/system/learning_tour_test.rb` | Static, reviewed explanation maps; source drift fails the tests. |
| Public demonstration boundaries | `Workbench::DemoMode`, `Workbench::DemoGate`, `bin/demo`, request record scopes | `test/integration/read_only_demo_test.rb`, `test/lib/demo_mode_test.rb`, `test/system/read_only_demo_test.rb` | Locally verified; external hosting/TLS/host checks are pending. |
| Reproducible delivery and open source | Lockfiles, `bin/setup`, Dockerfile, CI, MIT license, contribution and security guides | [Verification snapshot](CAPABILITIES.md#verification-snapshot) | Local checks do not certify the current remote CI, Docker runtime or public deployment. |

An evaluator can follow [IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md) for
the full source map, and [ARCHITECTURE.md](ARCHITECTURE.md) for sequence and
state diagrams. Each implementation above is available in this checkout.

## Architecture choices worth discussing

- **Run vs Message.** RubyLLM persists the conversation; Run represents an
  application execution. Attempts retain retries and approval continuations.
- **Snapshot vs template.** Editing a prompt, tool or Agent changes future
  work. Previous execution evidence remains tied to its original revision.
- **Outbox vs enqueue after save.** The Agent launch commits execution intent
  with the Run. Duplicate delivery is expected; a lease and generation decide
  which worker may write.
- **Recovery vs resubmission.** Local progress can resume; work that may have
  reached a provider needs an explicit unknown-outcome policy.
- **Retrieval vs answer.** Scores and sources are inspectable evidence, but
  neither a reranker score nor a citation proves a generated claim.
- **Cost amount vs provenance.** `recorded` preserves the ledger total without
  inventing a provider invoice or repricing historical requests.

## Online presentation

The recommended first public surface is a **read-only synthetic demo**, with
no provider credentials, no mutation or upload endpoints, and no semantic or
rerank provider calls hidden in GET requests. This mode is implemented and
locally verified; see [DEMO.md](DEMO.md) for preparation and boundaries. The
full workbench belongs on a trusted local installation or behind authenticated
access. A public repository and a publicly writable model playground have
different acceptance requirements.

Release success means a new developer can install it, complete the tour,
explain the execution boundaries, run a regression, and identify the remaining
limits from the documentation. Downloads, stars and portfolio outcomes have
not been measured.

## Optional real source-answer extension

Follow [the source-case walkthrough](GROUNDED_ANSWERS.md): import the MIT cases,
prepare embeddings, choose hybrid retrieval/rerank and an explicit free answer
model, then evaluate that saved answer. Its five-POST free-provider acceptance
is in [CAPABILITIES.md](CAPABILITIES.md); it is independent from synthetic tour
records. Native assertions require no model call. Reviewers and typed Judges
use separate APIs and their measured outcomes do not certify truth.
