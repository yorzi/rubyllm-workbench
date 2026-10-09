# Operations

How to run the workbench locally, verify it, and interpret what you see. It
never stores provider secrets, and it does not present local success as a
deployment or business result.

Updated: 2026-10-09

## Prerequisites

- Ruby `4.0.2`, Node.js `24.21.0` (see `.ruby-version` and `.nvmrc`)
- Rails `8.1.4`, RubyLLM `2.1.0`, SQLite, Tailwind, Vite, Hotwire, Solid Queue
- Optional: the native `libvips` library, needed only for Active Storage image
  variants

```sh
# macOS (Homebrew)
brew install vips
# Debian / Ubuntu
sudo apt-get install libvips
```

`bin/setup` checks whether Ruby can load libvips and prints a hint if it is
missing. It never installs system packages, and Rails boots without libvips.

## Run it locally

```sh
nvm install && nvm use
bin/setup --skip-server     # bundle install, npm ci, db:prepare
bin/dev                     # Rails, Vite, Tailwind and Solid Queue
```

`Procfile.dev` binds Rails and Vite to `127.0.0.1`. For a single web process,
bind loopback explicitly:

```sh
bin/rails server -b 127.0.0.1 -p 3100
```

Keep local servers on `127.0.0.1` or `::1`, and stop every server, watcher and
worker you started when you are done.

### Demo tour without provider keys

```sh
bin/rails workbench:demo          # build the synthetic "Demo tour" project
bin/rails workbench:demo:remove   # delete it
```

The tour holds finished, clearly labelled synthetic records: a streamed chat,
a structured output Run, an approved tool call, an Agent Run with citations
and a research report, a failed Run, a Knowledge collection (lexical search
works without keys) and an evaluation dataset. No provider is called.

## Provider configuration

Read [AI_USAGE_GUIDE.md](AI_USAGE_GUIDE.md) for the shared Codex/Claude Code
configuration and testing policy. It uses the existing Rails Minitest suite;
model and budget variables marked as proposals do not configure the app.

Workbench reads provider settings only through RubyLLM's configuration, from
environment variables first and then encrypted Rails credentials:

```sh
# Create a local file for Foreman, then edit it locally.
cp .env.example .env
```

`bin/dev` loads `.env` through Foreman. `bin/rails`, `bin/dogfood` and other
standalone commands do not load it; use encrypted credentials or a securely
prepared process environment for those commands. Blank example keys leave
providers unconfigured.

Credentials files are local to each installation and are not part of the
repository. Create your own with `bin/rails credentials:edit` if you prefer
them over environment variables; keys such as `openrouter_api_key` map to the
RubyLLM options in `config/initializers/ruby_llm.rb`. Without a master key the
credentials fallback is ignored, so environment-only setups still boot.

A safe first check:

1. Open the Model Explorer and confirm the provider shows as configured.
2. Choose an explicit provider and model in a Project Chat.
3. Send a small prompt to a free or cheap model.
4. Read the Run inspector: provider, Attempts, usage, cost provenance,
   latency, diagnostics.

Never put tokens in shell history, command-line arguments, logs, screenshots
or commits, and never print a decrypted credentials file.

## Verification

Run the cheap, deterministic checks first:

WebMock blocks external Ruby HTTP before test boot; loopback is allowed for
local test services. Ordinary tests stay offline even when a provider key is
configured. Only the explicit live harness opens `https://openrouter.ai:443`.
`RUN_LIVE_AI=1` alone does not open the ordinary test process.

```sh
bin/vite build --mode=test              # build once before parallel tests
bin/rails test                          # PARALLEL_WORKERS=1 for a single process
CI=1 bin/rails test:system              # Selenium; built assets, binds 127.0.0.1
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
npm audit --audit-level=high
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

If the environment cannot start parallel test workers, `PARALLEL_WORKERS=1
bin/rails test` runs the suite in one process. CI runs all of the above plus a
Docker image build on every push to `main`.

For the browser suite, `CI=1` makes Vite serve the built test assets rather
than probing for a development server. The tests wait for Turbo before
clicking interactive controls.

If you previously precompiled production assets in this checkout, run
`bin/rails assets:clobber` before testing or developing. Propshaft otherwise
continues to resolve the old production manifest, including outdated CSS.

## Live provider dogfood

The live suite in `test/live/provider_dogfood_test.rb` is opt-in and skipped by
default. It needs a configured provider (OpenRouter by default):

```sh
bin/dogfood           # eight free-model flow checks; manual items are reported separately
# Only with deliberate fee-bearing acceptance and explicit model selection:
bin/dogfood --paid
```

`bin/dogfood` runs the scenarios serially, prints a Markdown summary table and
appends one JSON line per scenario to `tmp/dogfood/<timestamp>.jsonl` (model
ids, transient Run ids, statuses, costs and safe diagnostic reasons; no prompt
or answer text). Override models with `DOGFOOD_*_MODEL` variables. Free mode
requires explicit OpenRouter `:free` IDs in both the current public catalog
and RubyLLM registry, with known zero catalog prices. Chat requests disable
the web plugin and add a zero price ceiling; one-shot embedding/rerank calls
also receive that ceiling. No model fallback is configured. Transport retries
are disabled, requests time out after 60 seconds, outputs are capped at 2,048
tokens, and the process stops allowing calls after 24 POST requests. These
test-only limits do not alter the interactive workbench.

The eight automated checks cover streaming, structured output, tool approval
and continuation, embeddings/semantic/hybrid/rerank, two-model comparison
with all intended judgments, a saved Agent using a local tool, free TTS and
the Rails source grounded-answer case study. Assertions
check integration and durable records, without rating answer/retrieval quality.
Missing models and fee-bearing capabilities stay visible as manual skips.
The harness also requires `RUN_LIVE_AI=1` and `AI_TEST_PROFILE=free` (or
`integration` with separate paid authorization). `bin/dogfood` sets them in
its subprocess. All enable flags require the exact value `1`. Integration
also rejects client fallback lists and configures no provider fallback; it
does not impose a zero-price ceiling on authorized paid calls.

Free TTS uses the explicit `fish-audio/s2.1-pro-free:free` model and speech
catalog, checks zero prices, limits text to 120 characters and permits MP3
without provider extras or a custom context. Speech does not inherit chat's
routing/price parameters; the catalog check is a client gate, not a provider
invoice or guarantee against later pricing changes. Voice identifiers are
model-specific; the accepted Fish request omitted voice and used its default.

```sh
bin/dogfood --include test_openrouter_free_speech
RUN_LIVE_AI=1 AI_TEST_PROFILE=free RAILS_ENV=test \
  bundle exec ruby script/diagnostics/openrouter_free_tts.rb
```

Each command uses one short synthesis POST. The raw probe independently
checks HTTP MIME and MP3 bytes and saves an ignored local audio/report file;
the RubyLLM scenario verifies the Speech object, Run, attachment, hash and
playback controls. Neither evaluates voice quality. Missing usage/cost remains
unknown. RubyLLM's MIME is format-derived, distinct from raw HTTP MIME.

Local TTS remains pending the owner's API details and adapter; the OpenRouter
acceptance is independent and does not certify that future local service.
Hosted web search, transcription and image generation remain
manual unless deliberately enabled. Transcription also requires a short local
`DOGFOOD_TRANSCRIPTION_FILE`. The harness does not start a TTS service.

Reports include profile, capabilities, duration and HTTP status/error metadata;
request IDs not exposed by RubyLLM remain unknown. They never retain request
headers, bodies or raw responses. Runs use the test database and roll back.
Cost/tokens in the report cover Run
Attempts; embedding/query/rerank usage is still unowned and is labelled
unknown, never inferred as zero or summed from per-chunk copies of batch
usage. A zero known subtotal is not a complete invoice. Free model availability
and account-enforced plugins remain external constraints; review the
[OpenRouter plugin settings](https://openrouter.ai/docs/guides/features/plugins/overview)
if the account forces plugins that requests cannot disable. Record results in
[CAPABILITIES.md](CAPABILITIES.md) after each intentional run.

## Remaining manual acceptance

Keep the model/voice, date, terminal Run state, linked Artifacts and fee
coverage with the result. Acceptance concerns the workflow; answer, retrieval,
voice and image quality are outside this exercise.

| Item | Next action | Flow acceptance |
| --- | --- | --- |
| Full grounded-answer case group | Use an available explicit free model with `bin/dogfood --include test_grounded_answer_case_study`. Current untrusted-source failures remain visible; no automatic retry is scheduled. | Each scheduled answer/refusal satisfies the snapshot schema and citation rules and leaves correct durable state. Expected facts and semantic quality remain manual. |
| Full two-model comparison | When free capacity is available, run `bin/dogfood --include test_evaluation_comparison_with_judge`; keep both explicit free IDs. | Both case outputs received/schema-valid and both intended judge Runs complete in the same invocation. A partial run stays failed. |
| Local TTS | Owner supplies loopback endpoint, API protocol, model and voice; implement the adapter before acceptance. | Existing Speech Run → audio Artifact → Active Storage attachment → playback; failure/cancellation/recovery preserve correct state. No cloud fallback. |
| Hosted web search | Deliberately choose model and fee budget, then run only its scenario with `--paid --include test_agent_with_hosted_web_search`. | Local tool completes, hosted usage is observed, citations/report are stored; do not infer search use from answer text. |
| Transcription | Provide a short local audio file through `DOGFOOD_TRANSCRIPTION_FILE` and an explicit supported model; intentionally enable only its paid scenario. | Source-audio and nonblank transcript Artifacts persist in a successful Run. Do not rate transcription accuracy. |
| Image | Deliberately select supported model/budget and run only `test_image_generation` with `--paid`. | Successful Run with attached image Artifact and a valid image MIME type. |
| OCR / Batch / parallel tools | Choose a supporting provider and explicit scope/budget before a small walkthrough. | OCR provenance, complete Batch reconciliation, or the selected parallel policy respectively; there is no current 2.1 live acceptance claim. |
| Video | Implement durable job restoration and ledger attribution first. | Submission/polling alone is insufficient to claim recoverable video execution. |

No background service is needed for the live Rails integration tests. Any
service started for local TTS acceptance must bind loopback and be stopped
when the task finishes; the harness does not stop an owner-managed service.

## Upgrading RubyLLM

1. Read the release's upgrade guide, back up persistent data, update the gem
   conservatively and review the lockfile. Schema changes need the framework
   generator and a committed migration; see [RELEASING.md](RELEASING.md).
2. Run the full suite, especially `test/services/ai/ruby_llm_internals_test.rb`,
   Batch workflow and native streaming evidence regressions. Remove a patch in
   [CAPABILITIES.md](CAPABILITIES.md#rubyllm-workarounds) that the release
   fixes. Both 2.0 patches are removed on the current 2.1 pin.
3. Intentionally run `bin/dogfood` using current free models, then update the
   matrix. Put fee-bearing or unavailable capabilities on the manual list;
   historical live evidence does not certify an upgrade.

## Docker

The Dockerfile installs Node.js, runs `npm ci` and precompiles assets. The
image is still a single-user app without accounts or tenant isolation, so the
example publishes the port on loopback only:

```sh
docker build -t rubyllm_workbench .
docker volume create rubyllm_workbench_storage
docker run --rm -p 127.0.0.1:8080:80 \
  --mount source=rubyllm_workbench_storage,target=/rails/storage \
  -e SOLID_QUEUE_IN_PUMA=1 --env-file .env.production \
  --name rubyllm_workbench rubyllm_workbench
```

SQLite databases, queue state and uploads live under `/rails/storage`; the
named volume keeps them across container replacement. Back it up before
upgrades. `SOLID_QUEUE_IN_PUMA=1` runs the Solid Queue supervisor inside Puma
for this single-container example; in a multi-container setup, run `bin/jobs`
separately against the same storage and queue database.

`.env.production` stays on your machine and must contain a runtime
`SECRET_KEY_BASE` (generate one with `bin/rails secret`) plus any provider keys.
A deployment reachable by others needs authentication, TLS and host checks in
front of it; the image provides none of these.

## Evaluation datasets

Create a dataset from a Project's Evaluations page as a JSON array of cases,
each with a unique `key`, an `input` and an `expected_output`, and optionally
`tags` and a `rubric`. Limits: 64 KB per case, 100 cases and 1 MB per
revision. Editing creates a new immutable revision; existing executions keep
theirs.

A comparison takes one runnable structured Experiment and 2-5 configured
structured-output models. Requests = models x cases, each with its own Run.
`expected_output` is never sent to the provider. Comparison uses exact JSON
equality; it does not measure semantic quality.

"Resume unstarted cases" re-queues only cases whose Run and Attempts never
started, so work that may have reached a provider is never replayed. A
recurring job fails cases stuck running for more than 30 minutes with
`worker_interrupted`.

## Run exports

The Run inspector offers two downloads:

- **Reproduction JSON**: frozen input and result, versions, Attempts with
  usage, cost and errors, redacted tool calls and events, text Artifacts, and
  for Chat Runs the frozen prior context plus the messages this Run wrote.
  Schema v2 caps the file at 512 KiB, total text at 100,000 characters and
  chat history at the latest 100 messages, and lists omissions in
  `truncation.omitted`.
- **Events JSON**: the latest 100 lifecycle events for the Run with related
  record IDs, redacted and bounded the same way.

Redaction covers sensitive keys, URL credentials, signed-URL signatures,
common API key and bearer token shapes, and local home paths. It cannot
recognize every personal detail or custom secret format, so review an export
before sharing it. Binary attachments are never included.

## Tool Lab execution mode

The default mode is `sequential`. Choosing `parallel` requests RubyLLM's
`calls: :many` and `concurrency: :threads` for new Chat Runs only when the
model declares `parallel_tool_calls` and every enabled tool declares
`parallel_safe?`; otherwise the Run freezes `calls: :one` and records a
`fallback_reason` in its input snapshot. To investigate parallel behavior,
check the input snapshot, the individual ToolInvocations, and each call's
request/completed events.

## Knowledge workspace

1. Create a collection in a Project.
2. Paste text with a title (and optional source reference), then ingest it.
   Text is normalized, checksummed and split into 800-character windows with
   120-character overlap.
3. Search with `lexical` to see scores, matched terms, sources and
   `char_start`/`char_end`.
4. Optionally embed the collection with a configured embedding model, then
   search `semantic` or `hybrid`.
5. Optionally upload a file. Text formats (txt, md, csv, json, yaml, tsv, log,
   up to 10 MB) are extracted locally; PDFs and images need a configured OCR
   model. Extraction runs in the background and leaves an `ocr_document`
   provenance Artifact.
6. Optionally rerank with a configured rerank model. Results show
   `rank N (was M)` and the rerank score; retrieval evidence is unchanged.

Retrieval calls a provider for explicit embedding, semantic/hybrid queries or
reranking. Missing prerequisites degrade to lexical with the reason shown.
**Answer with sources** creates a separate `grounded_answer` Run using lexical
retrieval and one selected structured-output model. It refuses locally when
no evidence matches. See [the case-study walkthrough](GROUNDED_ANSWERS.md) for
the import command, frozen inputs, citation limits and focused acceptance.

### Optional sqlite-vector adapter

The default `sqlite_application_cosine` adapter needs nothing extra. To let the
external sqlite-vector extension scan instead, provide the binary yourself (it
is never committed or downloaded automatically):

```sh
SQLITE_VECTOR_PATH=/path/to/vector.dylib \
KNOWLEDGE_VECTOR_ADAPTER=sqlite_vector_extension \
bin/rails server -b 127.0.0.1 -p 3100
```

If the binary is missing or fails to load, the app falls back to the default
adapter and shows why. Both perform exact cosine scans.

## Media Runs (experimental)

From a Chat choose **Image**, **Video** or **Transcribe**, or **Generate audio
Artifact** under a saved assistant reply. Only models whose registry entry
declares the capability appear, and unconfigured providers cannot be
submitted.

- **Image**: prompt up to 8,000 characters; PNG, JPEG, WebP, GIF or AVIF output
  is stored as an `image` Artifact with MIME type, size and SHA-256.
- **Video**: RubyLLM `animate` submits and polls inside the worker, so the
  browser never waits. The provider job ID is recorded in the Run timeline
  (redacted from exports). The app cannot restore a video job yet. RubyLLM 2.1
  has video-job accounting, but this worker does not link it to its Attempt,
  so Workbench's video cost remains unknown.
- **Transcription**: FLAC, M4A, MP3, MP4, MPEG, OGG, WAV or WebM up to 25 MB.
  The upload becomes an `audio` input Artifact; the transcript is a text
  Artifact.
- **Speech**: converts a saved assistant reply. Choose a speech model and,
  when the provider requires one, a voice identifier. The audio Artifact has a
  player and download link.

Uploaded and generated bytes are stored in Active Storage before the Run
depends on them. Every minute the recurring scheduler fails media Runs stuck
for 30 minutes (`worker_not_started` if never claimed, `worker_interrupted` if
running); neither is replayed automatically. A daily job purges unattached
blobs older than 24 hours.

## Observability boundaries

The `LifecycleEvent` catalog records Run, Attempt, Agent, Tool, Approval,
Artifact and provider (`ai.provider.*`) events with allowlisted metadata only,
deduplicated by `event_key`. Event persistence failures never block execution.
This is not provider-native tracing, distributed tracing, cost monitoring or a
dashboard, and Runs created before the catalog existed are not backfilled.

The Runtime panel shows background-job readiness separately from web
availability: in Solid Queue mode it reads process heartbeats, checks for a
scheduler running `dispatch_agent_run_deliveries`, a dispatcher and a worker
covering the `maintenance` queue, and counts due Agent outbox deliveries. A
ready state does not prove a provider is reachable.

## Reading the Run inspector

1. **Status**: succeeded, failed, cancelled, or waiting for approval.
2. **Operation**: `chat`, `structured`, `grounded_answer`, `agent`, `speech`, `image`, `video` or
   `transcription`.
3. **Attempts**: retries, the provider/model that ran, usage, cost provenance
   (reported, recorded, estimated, unknown) and finish reason.
4. **Lifecycle events**: the local order of state changes, first output, tools,
   approvals and Artifacts.
5. **Tools and provider tool activity**: calls, redacted arguments, results,
   approvals and hosted-tool usage counters.
6. **Input snapshot**: the prompt, tools, schema and execution policy this Run
   froze.
7. **Result or diagnostic**.

A succeeded Run can still carry an unknown cost, and a failed Run is valuable
evidence. Do not read only the badge.

`recorded` preserves a RubyLLM usage-ledger total calculated at request time.
The serialized row does not retain whether it was provider-reported or
estimated. Workbench keeps that amount rather than repricing it with current
registry metadata or calling it a provider invoice. Earlier Attempts are not
backfilled. A total with unknown-cost Attempts is a known subtotal.

## Troubleshooting

| Symptom | Check first | Do not conclude |
| --- | --- | --- |
| Model shows as unconfigured | Provider environment variable or credentials | That it will run anyway or fall back silently |
| Run failed | Run diagnostic, Attempt error, provider/model, finish reason | That history should be rewritten |
| Run waiting for approval | Pending approvals on the Chat | That waiting means success |
| Model fails with "No endpoints found" | Whether the provider still serves that registry model | That Workbench is broken; the registry can be stale |
| Knowledge search finds nothing | Source status, query tokens, embedding coverage, extraction status | That lexical is semantic search |
| Rerank did not apply | The "Rerank was not applied" reason | That rerank scores prove correctness |
| No `ai.provider.*` events on a Run | Whether this process ran the Run | That no provider was called |
| Agent failed with "no final answer" | The Agent's max output tokens and the finish reason | That the provider returned an answer |
| Live test failed | Network, provider availability, capability, credentials | That the code is permanently wrong |

## Security boundaries

- Local tools come only from the Ruby registry allowlist; the browser can
  toggle them but cannot upload or run Ruby.
- Tool arguments and results are filtered for keys, tokens, secrets, passwords
  and authorization headers before display.
- LifecycleEvent payloads use a fixed allowlist; never add prompts, raw
  arguments, results or file contents to events for debugging.
- Provider-hosted tools run on the provider, outside Workbench's allowlist.
  Approving a remote call lets the provider execute it.
- Knowledge accepts pasted text and uploads through the app's own entry
  points; URL fetching and provider file references do not exist.
- The sqlite-vector binary is external executable code. Obtain it from the
  official release only, and never commit or silently download it.
- Any long-running process you start needs a recorded PID, port and stop
  command, and must be stopped when the task ends.

## Checklist after a change

```text
[ ] Focused tests, then the full suite, Zeitwerk, RuboCop and security scans
[ ] Key pages checked on desktop and at 390px width
[ ] Run/Attempt/ToolInvocation/Approval/Knowledge evidence boundaries intact
[ ] Docs, diagrams and changelog updated in the same change
[ ] No credentials, tokens or private data in the staged diff
[ ] One clear topic per commit
```
