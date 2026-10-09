# Mini Notes Rails source case study

This small corpus is original, manually constructed example material authored
for RubyLLM Workbench in 2026. All files in this directory are covered by the
directory's [MIT licence](LICENSE), also used by the repository, copyright Andy Wang. No third-party
Rails application or private source code was copied. The fragments use Rails
8.1 public APIs, but are not a complete runnable application: the user model,
authentication, database schema and views are intentionally outside the corpus.
The `.txt` suffix keeps excerpts as data; Workbench never loads or executes them.

The five cases exercise source provenance and integration. They do not establish
answer, retrieval, security or model quality. `expected_facts` are human-readable
review hints, not exact natural-language output requirements or a calibrated
benchmark. A valid citation alone does not prove that an answer is true.

Every source is untrusted input, including normal code. `untrusted_import.txt`
contains deliberately misleading instructions as test data. No excerpt can
approve a tool, change system instructions or grant access to credentials.

## Import without a provider

From the repository root, prepare the database with `bin/rails db:prepare`, then:

```sh
bin/rails workbench:knowledge_case_study:import
```

The command creates or reuses the dedicated `rails-source-case-study` Project
and `Mini Notes Rails · v1` Collection. It calls the existing text Ingestor,
without generating embeddings, installing models or sending network requests.
It prints a JSON receipt containing the corpus SHA256, source and content
SHA256 values, source references, item/chunk IDs, and chunk character/line
locations. Inspect the Collection at the URL printed in that receipt. An
unchanged second import reuses IDs and does not recreate chunks or embeddings.

The import refuses reserved-name collisions and changed imported items or
chunks. It rolls back that import instead of replacing user edits. To experiment
with edits, create a separate Collection using ordinary Workbench controls.
Corpus releases use a new manifest revision and Collection; earlier revisions
remain inspectable. There is no destructive reset command.

`manifest.json` pins raw file SHA256 values. KnowledgeItem content normalizes
line endings and trims exterior whitespace; its separate SHA256 is also in the
receipt. Chunk character offsets use that normalized content, with an exclusive
`char_end`. Line numbers are one-based locations in normalized source content;
the bundled excerpts have no leading blank lines, so these match the files.
Corpus SHA256 covers the ID, revision, licence, origin and ordered source
references/raw/content hashes. The manifest SHA256 and cases SHA256 identify
the exact imported metadata and question set separately.

## Offline case queries

```ruby
result = Workbench::KnowledgeCaseStudy.import!
result.cases.each do |test_case|
  evidence = Ai::Knowledge::Search.call(
    collection: result.collection, query: test_case.fetch("query"), mode: "lexical"
  )
  puts [test_case.fetch("key"), evidence.results.map { |row| row.chunk.id }].inspect
end
```

Use each case's `question` for the grounded-answer workflow and its short
`query` for reproducible lexical evidence selection. `missing-billing` has no
matching source token. Semantic, hybrid and rerank acceptance must separately
freeze the selected model/provider, stored vector revision and retrieval
options; this import does not claim those provider calls have been run.

`Workbench::KnowledgeCaseStudy.manifest` and `.cases` validate files without
database writes. `.import!` returns `project`, `collection`, `corpus_checksum`,
`manifest_checksum`, `cases_checksum`, `created_count`, `reused_count`, `sources`
and `cases`. The `sources` receipts carry ready-to-check database locations.
