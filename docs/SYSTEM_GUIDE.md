# System guide

A mental model of RubyLLM Workbench for people returning to it, or reading it
for the first time. It answers: why the system exists, what it does now, how
one operation flows, where the data lives, and what it cannot claim yet.

Updated: 2026-10-08

## In one sentence

RubyLLM Workbench is a local-first Rails workbench: inside a Project you pick a
RubyLLM capability, start a Chat, Experiment, Agent or evaluation, and the
application saves each execution as inspectable records (Run, Attempt,
Message, ToolInvocation, Approval, Artifact, LifecycleEvent) so that latency,
cost, failures, tool side effects and human decisions all leave evidence.

Its value is not "do everything automatically". It shows how a Rails
application can make every AI call durable, explainable and recoverable.

## Goals

- Compare and try provider/model capabilities behind one RubyLLM boundary.
- Keep every execution explainable after a page refresh, a failure or an
  approval pause. Long work resumes from a saved transcript and queued
  continuations.
- Turn results and tool side effects into durable Artifacts instead of values
  that exist only in one page response.
- Show what the model did, what the system recorded, and where a person had to
  decide.
- In-page "How this works" panels explain each feature, its code path and its
  evidence boundary (see [LEARNING.md](LEARNING.md)).

## Non-goals

- Not a hosted service: no accounts, teams, billing or multi-tenant isolation.
- Not an agent platform. Agents exist to demonstrate durable, approvable,
  resumable execution, not to compete with agent frameworks.
- Not a complete RAG system: Knowledge covers local text and file sources,
  provider embeddings, explainable retrieval and optional rerank. Provider file
  references and page-level provenance are not implemented.
- It never runs Ruby, shell or code uploaded through the browser.
- Local tests passing, a successful live dogfood run, or a commit existing do
  not amount to a production deployment, public availability, business
  results or long-term provider stability.

## Implementation status and evidence

Status labels describe code; evidence is recorded separately in
[CAPABILITIES.md](CAPABILITIES.md).

- **`IMPLEMENTED`**: the path exists and meets its current acceptance.
- **`PARTIAL`**: some paths work; compatibility or evidence is incomplete.
- **`PLANNED`**: not implemented.

## Capability map

| Area | What a person can do | What the system keeps | Status |
| --- | --- | --- | --- |
| Projects | Group work; toggle tools per Project | Project, slug routing, ownership of every record | `IMPLEMENTED` |
| Models | Browse the RubyLLM registry with capability filters and configuration state | Nothing (read-only) | `IMPLEMENTED` |
| Chat | Stream a conversation with a chosen provider/model | Messages, Run, Attempts with usage, cost, latency, finish reason | `IMPLEMENTED` |
| Structured Experiments | Save a schema-constrained prompt and compare models | Frozen Experiment/Execution, one child Run per model, JSON Artifacts | `IMPLEMENTED` |
| Tools and approvals | Enable code-defined tools; approve or deny side effects | ToolDefinition, ToolInvocation, Approval | `IMPLEMENTED` |
| Parallel tool calls | Opt a Project into parallel calls | Frozen `calls`/`concurrency` options, per-call records | `IMPLEMENTED` locally; live `PARTIAL` |
| Lifecycle timeline | See the local order of state changes on a Run | LifecycleEvent with deduplicated `event_key` | `IMPLEMENTED` |
| Knowledge | Ingest text or files, embed, search lexical/semantic/hybrid, rerank | KnowledgeCollection, KnowledgeItem, KnowledgeChunk, KnowledgeEmbedding, provenance Artifacts | `IMPLEMENTED`; OCR live `PARTIAL` |
| Provider web search | Opt a Chat Run into hosted search | Frozen provider tools, citation Artifacts, usage counters | `IMPLEMENTED` |
| Saved Agents | Save a revisioned Agent and launch Runs | AgentDefinition snapshot, outbox, lease, steps, report Artifact | `IMPLEMENTED` |
| Media (experimental) | Generate speech, images, video; transcribe audio | Media Artifacts in Active Storage, provider events | `PARTIAL` (video resumption open) |
| Evaluations | Compare 2-5 models on a revisioned dataset; review; optional judge | EvaluationComparison, Execution, CaseResult, Review, Judgment | `IMPLEMENTED`; Batch live `PARTIAL` |
| Export | Download a redacted reproduction or event JSON for a Run | Bounded, redacted JSON | `IMPLEMENTED` |
| Upstream gap reports (experimental) | Classify a Run as an upstream candidate and download an issue draft | Append-only report Artifacts | `PARTIAL` |

## Key concepts

Do not collapse these into one "result".

### Project

The outer boundary. It owns Chats, Experiments, Agents, tools, Knowledge,
evaluation datasets and Runs. Switching Project switches resources, history
and tool settings.

### Chat and Message

A Chat is a conversation with one provider/model. Messages are persisted with
RubyLLM's Rails integration and rebuilt from the database, never from browser
memory.

### Run

One execution a person can reason about, with a stable inspector URL:

`queued -> running -> waiting_for_approval -> succeeded | failed | cancelled`

A Run's `input_snapshot` freezes what it saw: prompt, tool schemas, approval
policy, Tool execution policy and provider tools. Later changes in Tool Lab do
not rewrite old Runs.

### Attempt

One concrete provider/model request inside a Run. Retries, fallbacks and
approval continuations add Attempts; they never overwrite a failed one, so
"failed first, succeeded on retry" stays visible.

### LifecycleEvent

A local catalog entry on a Run answering "when did this change, and which
Attempt, tool or Artifact was involved". Events arrive through
`ActiveSupport::Notifications`, use fixed names and an `event_key` for
deduplication, and store only allowlisted metadata. Prompts, tool arguments,
results and Artifact contents stay in their own records. It complements the
records; it is not distributed tracing.

### Tool execution policy

Tool Lab stores a Project default of `sequential`. Choosing `parallel` does not
bypass safety: a Run freezes `calls: many` and `concurrency: threads` only when
the model declares `parallel_tool_calls` and every enabled tool declares
`parallel_safe?`. Otherwise the Run stays sequential and records a
`fallback_reason`. "Parallel was requested" and "this Run ran in parallel" are
separate facts.

### Provider web search

Off by default. When enabled, the Run snapshots `web_search` and uses RubyLLM's
provider-tool API; search terms go to the provider's hosted service. A
successful response does not prove a search happened: check the Run's
provider tool activity (discrete calls or usage counters such as
`web_search_requests`) and its citation Artifacts.

### Experiment, Execution, Artifact

- **Experiment**: a reusable, revisioned structured prompt with a bounded JSON
  Schema.
- **Execution**: one comparison over a frozen definition, usually one child
  Run per target model.
- **Artifact**: a durable product (JSON, text, report, citations, media,
  export). It sits beside the Run/Attempt evidence and never replaces it.

### KnowledgeCollection, KnowledgeItem, KnowledgeChunk, KnowledgeEmbedding

- **KnowledgeCollection**: a Project-scoped knowledge boundary with its
  embedding state (model, dimensions, coverage).
- **KnowledgeItem**: one normalized source with checksum and ingestion status.
  File sources are extracted in a background job (local text reading, or a
  configured OCR model for PDFs and images) and leave an `ocr_document`
  provenance Artifact.
- **KnowledgeChunk**: a deterministic character window with position and
  `char_start`/`char_end`.
- **KnowledgeEmbedding**: one chunk's vector under one model, with a content
  checksum; stale vectors are skipped and models are never mixed.
- **Retrieval modes**: `lexical` (exact token coverage), `semantic` (cosine
  over provider embeddings) and `hybrid` (both components kept). Results are
  evidence snippets, not model answers. Missing prerequisites degrade to
  lexical with the reason shown.
- **Rerank**: an optional second stage that only reorders and records
  `pre_rank` and the rerank score.

### ToolDefinition, ToolInvocation, Approval

- **ToolDefinition**: an allowlisted, code-registered tool the Project may
  use: `project_snapshot` (read-only) and `save_run_note` (needs approval).
- **ToolInvocation**: one call the model actually requested, with
  secret-filtered arguments, result, duration, status and error.
- **Approval**: one human decision for a tool call, written together with
  RubyLLM's conversation decision. Approvals are part of the execution history.

### Saved Agents

An AgentDefinition is an editable, revisioned template. Launching one copies
its revision, model, instructions, tools and options into a new Run with a
dedicated Chat. `AgentRunJob` advances the Agent step by step under an
expiring execution lease with a generation counter, so duplicate or stale job
deliveries cannot write to the transcript. Work is handed to Solid Queue
through a durable outbox, and a recurring dispatcher retries deliveries and
recovers stale leases. A successful Run stores its final answer as a report
Artifact linked to its citations.

### Evaluations

An EvaluationComparison freezes one dataset revision, one Experiment snapshot
and 2-5 models. Each model has an EvaluationExecution and each case its own
Run, compared by exact JSON equality. Metrics keep provider outcomes, schema
validity, latency, token coverage and reported, recorded and estimated cost apart.
Human EvaluationCaseReview records are append-only, and the optional rubric
judge is a separate, uncalibrated Run. Expected output, tags and attachments
never reach a provider prompt.

## How one Chat Run works

1. A person submits a prompt; `Ai::RunExecutor` syncs the Project's tool
   registry and freezes the enabled tools, approval policy, Tool execution
   policy and provider tools into a new Run's `input_snapshot`.
2. The Run and its first queued Attempt are created atomically, then
   `ChatResponseJob` is enqueued on Solid Queue.
3. `Ai::ChatExecutor` claims the Run. A duplicate job for a running or
   terminal Run exits without resubmitting the prompt.
4. The executor configures tools and options from the snapshot and streams
   the response into a RubyLLM Message while the Attempt records usage,
   latency, cost and finish reason.
5. Local tool calls become ToolInvocations with secret-filtered arguments.
   Provider citations become a `citation_set` Artifact.
6. A tool that needs approval moves the Run to `waiting_for_approval`; the
   pending call survives a page refresh.
7. Approve or deny writes the Approval and RubyLLM's decision, then queues a
   continuation that resumes with `complete` (no duplicate user prompt) on a
   new Attempt.
8. With no pending calls the Run succeeds; provider or tool errors fail it
   while keeping a safe diagnostic.

The sequence diagram is in [ARCHITECTURE.md](ARCHITECTURE.md#4-runtime-chat-run-with-approval).

## The two built-in tools

| Tool | Side effect | Approval | Parallel | Notes |
| --- | --- | --- | --- | --- |
| `project_snapshot` | None | never | safe | Project name, slug, description and local record counts |
| `save_run_note` | Creates a `report` Artifact | always | sequential only | Changes local data, so it needs approval |

Tool Lab manages only these code-registered entries. It is not an online code
runner.

## How pages map to the system

- **Left rail**: Projects and global entries. Which context am I in?
- **Main canvas**: Chat, Experiments, Evaluations, Agents, Knowledge, Tool Lab
  or Runs. What am I operating?
- **Inspector**: status, usage, cost, Attempts, tools, diagnostics and the
  lifecycle timeline. What actually happened?
- **Run inspector**: a stable view of one execution, reachable from global Run
  history, with export downloads.
- **Knowledge workspace**: collections, sources, embeddings and search evidence.
  It never creates Runs and calls a provider only on an explicit embed or a
  semantic/hybrid query.
- **Runtime panel**: web liveness shown separately from background-job
  readiness (scheduler, dispatcher and maintenance worker heartbeats).

## Easy to misread

### "Succeeded" does not mean "reliable"

Success means this Run finished in this environment, with this provider,
model and input. Also read the Attempts, cost provenance, tool results,
approvals and any provider failure.

### "Passed locally" does not mean "works with a provider"

Tests, browser checks, live dogfood, commits and health checks are different
evidence. None substitutes for another, and none implies deployment, users or
business value.

### "Tool call" does not mean "Agent"

A Chat can call allowlisted tools with approval. A saved Agent is a separate,
revisioned definition whose Runs advance step by step under a lease.

### "Failed" does not mean "history lost"

Failed Runs, Attempts, tool calls and diagnostics are kept. A retry creates new
evidence instead of erasing the old.

## What to trust today

Live evidence on the current dependency pin is recorded in
[CAPABILITIES.md](CAPABILITIES.md#live-dogfood-record): chat, structured output,
tool approval, an Agent with hosted web search and citations, embeddings with
rerank, a two-model evaluation with a rubric judge, speech, transcription and
image generation all passed against OpenRouter on 2026-09-28. Video, OCR,
provider Batch and parallel tool calls have local evidence only.

This is point-in-time, local verification, not a production promise.

## Reading order when you return

1. [README](../README.md) for scope and quickstart.
2. This guide's capability map and "Easy to misread".
3. The matching diagram in [ARCHITECTURE.md](ARCHITECTURE.md).
4. The latest entry in [CHANGELOG.md](CHANGELOG.md).
5. [IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md) to find the code.
