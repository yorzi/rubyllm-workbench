# In-page learning layer ("How this works")

The learning layer connects each feature to the code that implements it. You
stay on the page (Model Explorer, Chat, Experiments, Agents, Evaluations,
tool approval, Knowledge, Run inspector) and open a panel that shows a plain-language explanation, the
execution steps, version labels, allowed source excerpts, official Rails and
RubyLLM references, and the current capability boundary.

## Implementation

Topics live in a version-controlled static registry,
`app/services/learning/topic_registry.rb`:

- `model_explorer`: the RubyLLM catalog, provider configuration state,
  capability filters and what "runnable" means.
- `chat_setup`: how a Project creates a Chat and how the provider/model reach
  the first Run.
- `chat_run`: how a Rails action becomes a durable Run and Attempt and reaches
  `Ai::ChatExecutor`.
- `tool_approval`: how code-defined tools pass the allowlist, a RubyLLM tool
  call and a durable approval.
- `experiment_comparison`: frozen definitions, model selection, one Run per
  target and validated Artifacts.
- `run_inspector`: the Run/Attempt lifecycle, usage, cost, diagnostics and the
  local event timeline.
- `project_boundary`: slug routing, resource ownership, Project tool policy and
  Run snapshots.
- `knowledge_ingestion`: extraction, provenance and deterministic chunks.
- `knowledge_search`: retrieval over ready sources and optional rerank.
- `grounded_answer`: bounded lexical snapshots, native structured output,
  exact-quote citations, local refusal and asynchronous completion fencing.
- `agent_execution`: transactional launch/outbox, worker lease, continuable
  steps, approval pauses and external-outcome limits.
- `evaluation_workflow`: frozen comparisons, transport/schema/exact-match
  outcomes, independent review and safe recovery.

`Learning::Flow` provides small HTML execution maps for Agent, evaluation
and retrieval topics. They retain conditional paths, need no JS renderer and
stay readable in the narrow Turbo panel and on mobile. Detailed sequences
and state diagrams remain in [ARCHITECTURE.md](ARCHITECTURE.md).

On narrow screens, navigation is expandable and a loaded explanation scrolls
into view and receives focus. The browser regression checks this at 390px.

No model generates these explanations at runtime, and there is no file
browser. Each topic cites explicit source paths, line ranges and an anchor
string. `Learning::SourceReader` reads only from fixed top-level directories,
caps excerpt length at 80 lines, refuses paths that could expose credentials,
and requires the anchor to still appear in the range. When code moves, the
registry test fails until the reference is updated.

Page entries map to topics by lifecycle stage rather than one topic per
button: the Projects list and Project workspace share the Project boundary
topic, while Chat, Run inspector and Knowledge link separate topics for
creating, executing, inspecting, ingesting and searching.

## Content contract

Each topic explains:

1. the feature the person is using and its Rails entry point;
2. the order of the key services, jobs and RubyLLM boundaries;
3. the evidence visible in the database or inspector;
4. what the implementation explicitly does not claim;
5. official Rails and RubyLLM background reading.

Version labels come from the running process and the lockfile (Rails, RubyLLM,
application version). They say which implementation the text describes; they
are not deployment proof or a provider SLA.

## Maintenance

- When a code path changes, update the topic's references, text and tests in
  the same change.
- Add a topic by choosing a stable key first, then wire it into real pages; do
  not copy explanations per button.
- Split multi-stage features at verifiable boundaries (ingestion vs search,
  comparison vs inspection).
- Excerpts must never contain credentials, raw prompts, provider secrets,
  unredacted tool payloads or user content.
- Status wording must match [SYSTEM_GUIDE.md](SYSTEM_GUIDE.md) and
  [CAPABILITIES.md](CAPABILITIES.md).
