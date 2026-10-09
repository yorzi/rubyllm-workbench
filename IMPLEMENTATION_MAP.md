# Implementation map

Where each capability lives in the code. Behavior is explained in
[docs/SYSTEM_GUIDE.md](docs/SYSTEM_GUIDE.md), the runtime paths in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and evidence in
[docs/CAPABILITIES.md](docs/CAPABILITIES.md).

Updated: 2026-10-08

## Shape

`Project -> Chat / Experiment / Agent / Knowledge / Evaluation -> Run + Attempt + evidence records -> inspectors and exports`

Every provider operation goes through RubyLLM. Chat, Agent, evaluation and
media executions become Runs/Attempts with linked evidence. Knowledge
ingestion, embeddings, retrieval and rerank use their own source/chunk/vector
records; those operations do not create Runs.

## Execution core

| Concern | Code |
| --- | --- |
| Run lifecycle and state transitions | `app/models/run.rb` |
| Agent execution lease (claim, renew, fence) | `app/models/run/agent_execution_lease.rb` |
| Closing tool calls and approvals on cancel/fail | `app/models/run/tool_approval_closure.rb` |
| Attempt usage, cost, timing, finish reason | `app/models/attempt.rb`, `app/services/ai/attempt_recorder.rb`, `app/services/ai/cost_normalizer.rb` |
| Error classification and redaction | `app/services/ai/error_classifier.rb`, `app/services/ai/error_text.rb` |
| Lifecycle events | `app/models/lifecycle_event.rb`, `app/services/ai/lifecycle_event_recorder.rb` |
| RubyLLM instrumentation adapter | `app/services/ai/ruby_llm_instrumentation.rb`, `Ai::ExecutionContext` |
| Private RubyLLM seams (listed, contract-tested) | `app/services/ai/ruby_llm_internals.rb` |
| Batch submitted-chat manifest check (public API) | `app/services/ai/evaluation_batch_results.rb` |
| Background-job readiness | `app/services/ai/queue_readiness.rb` |

## Chat, tools and approvals

| Concern | Code |
| --- | --- |
| Submit a Chat message | `MessagesController`, `Ai::RunExecutor`, `ChatResponseJob` |
| Execute and stream | `Ai::ChatExecutor`, `Ai::ChatContextSnapshot` (frozen context, drift check) |
| Tool registry and Project settings | `Ai::ToolRegistry`, `Ai::ChatTooling`, `ToolDefinitionsController`, `app/tools/ai/tools/` |
| Parallel-call policy | `Ai::ToolExecutionPolicy` |
| Tool call audit and approvals | `Ai::ToolInvocationRecorder`, `Ai::ApprovalService`, `ApprovalsController`, `Ai::ToolErrorFinalizer`, `Ai::ToolPayloadSanitizer` |
| Provider web search evidence | `Ai::CitationSetRecorder`, `Ai::ProviderToolActivity` |

## Structured Experiments

`ExperimentsController`, `ExperimentExecutionsController`,
`Ai::ExperimentExecutor`, `StructuredResponseJob`, `Ai::StructuredExecutor`,
`Ai::SchemaDefinition`, `Ai::SchemaValidator`.

## Saved Agents

| Concern | Code |
| --- | --- |
| Definitions and revisions | `AgentDefinition`, `AgentDefinitionsController`, `Ai::AgentModelEligibility` |
| Launch and outbox | `AgentRunsController`, `Ai::AgentRunExecutor`, `AgentRunDelivery`, `AgentRunDeliveryDispatcherJob` |
| Step execution and recovery | `AgentRunJob`, `Ai::AgentLeaseHeartbeat`, `Ai::TransientDatabaseError` |
| Final report | `Ai::AgentResearchReportRecorder` |

## Knowledge

`KnowledgeCollectionsController`, `KnowledgeItemsController`,
`KnowledgeEmbeddingsController`, `DocumentExtractionJob`, and
`app/services/ai/knowledge/`: `Ingestor`, `DocumentIngestor`, `Extractor`,
`Chunker`, `Embedder`, `EmbeddingCatalog`, `Retriever`, `Search`,
`VectorStore`, `Reranker`, `RerankCatalog`, `OcrCatalog`.

Source answers: `KnowledgeAnswersController`, `Ai::Knowledge::{ProviderCall,
EvidenceSnapshot,GroundedAnswer,GroundedAnswerExecutor,GroundedResponse}`,
`GroundedAnswerJob`, `GroundedAnswerRecoveryJob`.

Native saved-answer evaluation: `NativeEvaluationsController`,
`Ai::Knowledge::{NativeEvaluation,NativeEvaluationExecutor,GroundedAnswerEvaluation,
GroundedAnswerReviewer,GroundedAnswerJudge}`, `Ai::JudgmentCatalog`,
`NativeEvaluationJob`, `NativeEvaluationRecoveryJob`. The native owner ledger
links to individual Attempts; the original answer is not replayed.

## Media (experimental)

| Operation | Code |
| --- | --- |
| Speech | `SpeechRunsController`, `Ai::SpeechRunExecutor`, `Ai::SpeechCatalog`, `SpeechRunJob`, `SpeechRunRecoveryJob` |
| Image | `ImageRunsController`, `Ai::ImageRunExecutor`, `ImageRunJob` |
| Video | `VideoRunsController`, `Ai::VideoRunExecutor`, `VideoRunJob` |
| Transcription | `TranscriptionRunsController`, `Ai::TranscriptionRunExecutor`, `TranscriptionRunJob` |
| Shared | `Ai::MediaCatalog`, `Ai::MediaBlobStorage`, `MediaRunRecoveryJob`, `PurgeStaleUnattachedBlobsJob` |

## Evaluations

| Concern | Code |
| --- | --- |
| Datasets, revisions, attachments | `EvaluationDataset`, `EvaluationDatasetRevision`, `EvaluationDatasetCaseAttachment`, `EvaluationDatasetsController`, `EvaluationCaseAttachmentsController`, `Ai::EvaluationCaseAttachmentContentValidator` |
| Comparisons and executions | `EvaluationComparison`, `EvaluationExecution`, `EvaluationCaseResult`, `EvaluationExecutionsController`, `Ai::EvaluationExecutor`, `Ai::EvaluationJobEnqueuer`, `EvaluationCaseJob`, `EvaluationCaseRecoveryJob` |
| Outcomes and metrics | `Ai::EvaluationCaseOutcome`, `Ai::EvaluationMetrics` |
| Human reviews | `EvaluationCaseReview`, `EvaluationCaseReviewsController` |
| Rubric judge (experimental) | `EvaluationCaseJudgment`, `Ai::EvaluationRubricJudge`, `Ai::EvaluationCaseJudgeEnqueuer`, `EvaluationCaseJudgeJob`, `EvaluationCaseJudgmentRecoveryJob` |
| Provider Batch | `EvaluationBatchSubmissionJob`, `EvaluationBatchRefreshJob`, `EvaluationBatchRecoveryJob`, `Ai::EvaluationBatchResultProcessor`, `Ai::EvaluationBatchResults` |

## Export and upstream reports

`RunsController#reproduction` and `#events`, `Ai::RunReproductionExporter`,
`Ai::UpstreamCandidateRecorder`, `Ai::UpstreamIssueDraft`.

## Pages and learning layer

- Shell, Runtime panel and inspector: `app/views/shared/`.
- Run history and inspector: `RunsController`, `app/views/runs/`.
- Model explorer: `ModelsController`, `Ai::ModelCatalog`.
- "How this works" panels: `LearningTopicsController`,
  `app/services/learning/` (see [docs/LEARNING.md](docs/LEARNING.md)).

## Tooling

| Purpose | Code |
| --- | --- |
| Demo tour without provider keys | `lib/workbench/demo_tour.rb`, `lib/tasks/workbench.rake` |
| Live provider dogfood | `test/live/provider_dogfood_test.rb`, `test/support/dogfood_report.rb`, `bin/dogfood` |
| Upstream reproductions (no network) | `script/diagnostics/` |
| Recurring jobs | `config/recurring.yml` |
| RubyLLM configuration | `config/initializers/ruby_llm.rb` |
