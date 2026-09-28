# RubyLLM Workbench

RubyLLM Workbench is a local-first Rails reference application for building and
inspecting AI workflows with RubyLLM. It brings model selection, project-scoped
chats, structured experiments, approved tools, local knowledge retrieval, and
durable execution records into one application. Each Run offers a sanitized
event JSON download for timeline analysis, alongside its reproduction bundle.

This is a single-user developer workbench. It is not a hosted service and does
not provide accounts, teams, billing, or multi-tenant isolation.

Start with:

- [Current system guide](docs/SYSTEM_GUIDE.md)
- [Capability matrix](docs/CAPABILITIES.md)
- [Architecture and runtime diagrams](docs/ARCHITECTURE.md)
- [Local setup and evidence boundaries](docs/OPERATIONS.md)
- [Implementation map](IMPLEMENTATION_MAP.md)
- [Roadmap](TODO.md)
- [Documentation index](docs/README.md)
- [Contribution guide](CONTRIBUTING.md)
- [Security reporting](SECURITY.md)

The repository is self-contained. Code, migrations, existing tests, and the
current implementation documents are the source of truth for behavior. The
roadmap describes planned work; `IMPLEMENTED`, `PARTIAL`, and `PLANNED` labels
are kept distinct from verification evidence.
The repository does not yet include a `LICENSE`; the project owner still needs
to choose the redistribution terms.

The reference value is in the Rails application layer: how provider calls become
durable, inspectable Runs with Attempts, approvals, Artifacts and recovery paths.
It complements RubyLLM's API guides with a working application; it is not a
replacement AI framework or a hosted product.

## Current implementation

The implemented application includes Projects, a RubyLLM model explorer,
persisted Chats and Messages, streaming execution, structured Experiments,
allowlisted tools with durable approval, Run/Attempt/ToolInvocation records,
searchable Run history, and a local lifecycle timeline. Its Project-scoped
Knowledge workspace supports text and file sources, checksummed chunks,
provider embeddings, lexical/semantic/hybrid evidence search, optional reranking,
and extraction provenance.

Provider compatibility remains partial. In particular, parallel tool-call
compatibility, OCR dogfooding, page-level provenance, and broader cross-provider
embedding coverage still need evidence. M5 now includes per-Run provider search
and citations plus saved, revisioned Agent definitions and dedicated queued
Agent Runs with approval and cancellation paths. The new Agent execution path
has an expiring database execution lease that fences transcript, usage, and
current local tool writes by owner token/generation. Approval continuations
identify the decided tool call, saved local tool contracts are checked before
resuming, and the built-in note Artifact is idempotent by tool-call id. Each
successful Agent Run also stores its final answer as a report Artifact linked
to the final Attempt and citation Artifacts. Focused automated tests cover
frozen snapshots, outbox dispatch and retries,
recovery scans, lease-generation fencing, terminal and late-response
cancellation, pending-approval expiration on Run cancellation, and M5.6 failed-Run
cleanup. Pending local and remote approvals are closed; approved remote calls
without a saved provider result are marked outcome-unknown and block further
use of that Chat. Focused provider-free coverage: 19 runs, 199 assertions.
The Agent path also covers RubyLLM 2.0
Responses/MCP provider-hosted approval cards and protocol responses, approved
and denied Agent continuation through the durable outbox, step/citation timeline
records, deterministic two-step `AgentRunJob` success, approved/denied local
tool continuation, and recovery from an expired lease with an interrupted blank
response. All outbox continuations carry the newly claimed generation forward,
while stale duplicate deliveries are rejected. A local
Solid Queue worker kill/restart drill verified replay of a committed
`save_run_note` without creating a duplicate Artifact. A provider-free threaded
cancellation test also blocks at RubyLLM completion, cancels the Run concurrently,
and verifies that no late assistant response is persisted. A request-level
integration flow covers Agent definition creation and launch, a two-step fake
Agent, frozen revision, and citation display after Run reload. A manual browser
check used an isolated Rails test database at 390px and desktop widths. It
covered a synthetic successful report with citation links and step timeline, a
pending approval and its denied/queued state, and a cancelled Run with expired
approval and cancelled tool details. The Run and Chat pages had no document-level
horizontal overflow at 390px; the Attempt table retains its own contained
horizontal scroll. The browser used the test queue adapter, so no Run worker or
provider call occurred. A Selenium system test exercises the native cancel
confirmation: dismissing it leaves the Run and Attempt running; accepting it
cancels both. Request integration also covers the cancellation endpoint. Live
provider behavior remains open, so M5 is partial. Initial
and resumed Agent work is durably recorded in the
primary database, then dispatched to Solid Queue with retry and stale-lease
recovery. Queue insertion and delivery acknowledgement are at-least-once across
separate databases, so duplicate jobs are possible and fenced by the Run lease.
The recurring Solid Queue scheduler must run for pending deliveries and crash
recovery to drain. The Runtime inspector distinguishes a responding web process
from background-job readiness; in Solid Queue mode it checks recent recurring
Agent dispatcher, queue dispatcher and maintenance-worker heartbeats, and shows
due Agent outbox deliveries. M6 provides asynchronous speech, image, video, and
audio transcription Runs with inspectable Artifacts and usage/cost status. Rejected
enqueue and stale queued recovery are covered for all four operations. A worker
interrupted after claiming a Run is failed without automatic replay because provider
acceptance may be uncertain. Late image and video responses are fenced after stale
recovery. Chat actions are clearly disabled when the model catalog has no compatible
media operation. Video cost remains unknown where RubyLLM does not expose normalized usage.
The video submission event stores a provider job reference in the
Run timeline for support; reproduction exports redact it. RubyLLM 2.0.0 has no
public API for restoring a VideoJob from that ID, so durable video resumption remains
open. Live provider acceptance also remains open. Fake-provider integration
coverage exercises speech, image generation, video generation and transcription
through saved Artifacts and the Run inspector; it does not establish live provider
compatibility. Deterministic M6 checks also cover queue rejection, stale queued
recovery, and provider failures racing with cancellation or recovery. Generated
media and transcription source bytes are stored before the Run
can depend on them; a recurring maintenance job purges unattached blobs older than
24 hours.
M7 adds revisioned evaluation datasets with per-case Run evidence and exact
JSON comparison. A comparison freezes one dataset revision and Experiment snapshot
for 2–5 configured structured-output models, creates an independent Execution and
Run per model/case, and shows a side-by-side result summary linked to the raw Runs.
Individual and provider Batch submissions remain available; each Batch still
targets one configured model advertising both structured output and batch
capability, and refreshed results map into their original case Runs using RubyLLM's
submission-order contract. Per-model summaries include observed response and schema
rates with known-outcome denominators, app-observed latency, token coverage and
reported/estimated cost by currency; provider Batch wait time is excluded from
latency. Provider-free tests cover shared snapshot freezing,
comparison summaries, queue-admission checks,
retryable individual case re-enqueue, local-store reconciliation, late records,
positional refresh and per-case Artifacts. If an individual case job is rejected
it stays queued with the enqueue error visible and can be retried; if the
provider-batch submission job is rejected before submission starts, the local
execution and cases are closed as failed. `submission_unknown` is reserved for a
request that may have reached the provider.
An uncertain submission stays open for local
store reconciliation and is never replayed automatically; an operator can close
the local Runs as failed after acknowledging that this cannot cancel remote work.
Expected output stays local and is excluded from provider prompts; comparison
results use exact JSON equality and do not claim semantic quality. An optional
rubric judge makes a separate provider request for each successful case with a
rubric, stores its ratings and cost separately, and does not change exact-match
results, human reviews or provider metrics. Selecting it sends the case input,
generated output and rubric to the judge provider; expected output, tags and
attachments are excluded. The judge remains an uncalibrated model assessment,
not an authoritative quality score.

M8 adds an explicit, redacted per-Run reproduction JSON download and append-only
upstream candidate reports. URL userinfo, signed URL signatures and session-token
query values, and common credential patterns are redacted while useful host/path
context is retained. A Markdown issue draft includes the sanitized reproduction
JSON. Export schema v2 caps the formatted bundle at 512 KiB, bounds text, nested
structures, record counts and Chat history, and reports omissions in `truncation`;
if the cap is exceeded, it returns a compact Run summary. Markdown drafts have a
768 KiB cap. Chat exports include the frozen prior message context and messages
persisted during that Run, including tool protocol fields needed to inspect
approval turns.
The worker checks that the Chat still matches the queued context before it makes a
provider request, and the workbench allows only one active Run per Chat. Attachment
payloads remain excluded, and provider state or nondeterministic output cannot be
replayed exactly. Provider-free tests cover candidate validation, append-only
storage, evidence capture, text redaction and draft download. Focused Chat tests
also cover frozen context, drift rejection, queue failure, concurrent submissions,
approval continuation and export boundaries. Representative Run review,
classification and external submission remain manual.
M7 and M8 remain partial local slices. See
[TODO.md](TODO.md) for current scope and evidence.

M7 evaluation cases may carry up to 12 unique tags (up to 40 characters each)
and an optional rubric of up to eight short criteria. Tags stay local. The rubric
is excluded from generation prompts unless an optional judge is selected, in
which case the rubric, case input and generated output are sent to that provider;
expected output and attachments remain excluded. Completed outputs can receive
append-only, self-reported human reviews with a short
rationale and one rating per rubric criterion. Per-case rating counts are
descriptive; they do not alter exact-JSON results or provider metrics and are not
combined into a quality score. Cases can also keep up to five
revision-owned attachments per case, with at most 50 files per dataset revision
(10 MB each; 50 MB total per revision), in an allowlist of text, JSON, CSV,
PDF, JPEG and PNG types. Adding or removing a file creates a new revision;
earlier revisions retain their files, and project deletion purges them. Files are
local review material and are excluded from individual and Batch provider prompts.
The 50 MB bound is per revision; repeated uploads can grow retained dataset/project
storage because there is no lifetime aggregate cap. The multipart-reported MIME
chooses the format check; if it is missing or `application/octet-stream`, the
filename extension only chooses which check to apply. Before writing a new
revision, Workbench checks PDF headers, JPEG/PNG signatures, JSON parsing, CSV
syntax, and UTF-8 text without binary control bytes. This confirms basic format
consistency; it does not fully decode PDFs/images or scan for malicious or
polyglot content.
Application size and part checks run after multipart parsing, so a network
deployment must also impose request-body and part-count limits at its ingress.
Automated judge ratings and
human reviews are descriptive aids; neither establishes a universal quality
score.
Reviewer labels are not authenticated identities, and the metrics report execution
evidence without assigning a universal model-quality score.

## Local setup

The app targets Ruby 4.0.2, Rails 8.1.4, RubyLLM 2.0.0, SQLite, Tailwind,
Vite, Hotwire, Solid Queue, and Node.js 24.21.0 for frontend assets.

```sh
nvm install
nvm use
bundle install
npm ci
bin/rails db:prepare
bin/dev
```

The `bin/setup` script checks the pinned Node.js version, installs Ruby and npm
dependencies, and prepares the database. `bin/dev` binds both Rails and Vite to
`127.0.0.1` by default.

The bundle includes the Active Storage image-variant processor. Install the
native `libvips` library if you use image variants:

```sh
# macOS with Homebrew
brew install vips

# Debian or Ubuntu
sudo apt-get install libvips
```

`bin/setup` checks whether Ruby can load `libvips` and prints a non-fatal hint if
it is missing. It does not install system packages; missing `libvips` does not
prevent Rails from booting, but image-variant processing will be unavailable.

For a one-off local server, bind it to loopback explicitly:

```sh
bin/rails server -b 127.0.0.1 -p 3100
```

The Model Explorer and project pages can be opened without provider keys.
Running a chat requires the selected provider to be configured through the
environment or Rails credentials. Never commit or print plaintext credentials.

## Verification

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop --cache false
bin/rails assets:precompile
```

Paid-provider checks are opt-in. The application keeps provider configuration
visible and reports unavailable providers instead of attempting a hidden
fallback.
