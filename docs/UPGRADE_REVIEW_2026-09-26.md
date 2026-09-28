# Rails / RubyLLM upgrade review — 2026-09-26

## Versions

RubyGems' live latest-version endpoints returned RubyLLM **2.0.0** and Rails
**8.1.4** on this date. RubyLLM was already pinned to that stable version.
Rails and all framework components were upgraded from 8.1.3.1 to 8.1.4;
the conservative dependency update also added the missing CSV gem (3.3.6).

- [RubyLLM official version endpoint](https://rubygems.org/api/v1/versions/ruby_llm/latest.json)
- [Rails official version endpoint](https://rubygems.org/api/v1/versions/rails/latest.json)
- [Rails 8.1.4 release notes](https://github.com/rails/rails/releases/tag/v8.1.4)

## Reproduced defects and corrections

### Workbench attachment validation

The initial full suite failed because the content validator requires `csv`,
which is no longer bundled with Ruby 4. Declaring the dependency fixes the
attachment path. Additional tests cover valid/malformed CSV and JSON, binary
text rejection, a false PNG declaration, and stream-position restoration.

### Workbench reproduction export

The Chat messages association already orders its records. Appending
`order(id: :desc)` retained that earlier order, so reversing the selected rows
exported messages backwards and could select the wrong end of long histories.
`reorder(id: :desc)` now explicitly selects the newest bounded records, then
reverses them into chronological order. Existing multi-turn and approval
continuation regressions now pass.

### RubyLLM 2.0.0 Batch index validation — upstream candidate

The installed, unmodified gem accepts invalid normalized result indices before
delivering records. A duplicate overwrites a slot, a negative integer uses Ruby
array indexing, and an index beyond the submitted request count expands the
result array. A later length check cannot undo delivery and cannot detect a
duplicate that leaves the array length unchanged.

Run the independent, provider-free reproducer:

```sh
bundle exec ruby script/diagnostics/ruby_llm_batch_indices.rb
```

Observed on 2.0.0, with two expected requests:

```text
negative: ACCEPTED slots=2 statuses=[:cancelled, :failed]
duplicate: ACCEPTED slots=2 statuses=[:cancelled, :failed]
out_of_range: ACCEPTED slots=3 statuses=[:failed, :failed, :failed]
```

Expected: reject the entire malformed collection before delivery or status
mutation. This is a deterministic synthetic reproduction of the released gem's
behavior; it does not show that a real provider has returned these malformed
rows. No upstream issue or PR was published by this task.

Workbench mitigation: `Ai::EvaluationBatchResults` extends only the evaluation
Batch instance and validates all normalized indices against the immutable case
count before RubyLLM allocates/delivers results. It rejects duplicates, negative
and non-integer indices, and indices outside the frozen case count. Missing
results retain their positions, including when the provider omits its count.
The existing refresh error path records the failure and leaves cases unchanged.

This isolated workaround relies on RubyLLM's private `result_slot_count` hook.
Recheck or remove it when upgrading RubyLLM. The tests use the real Batch class
and verify no partial delivery, ordering, missing slots, collection caching,
instance isolation, and the evaluation job's error path.

## Local validation

| Check | Result |
| --- | --- |
| Full Rails suite | 322 runs, 2,818 assertions, 0 failures, 0 errors, 2 opt-in provider skips |
| Selenium browser suite | 2 runs, 9 assertions, 0 failures/errors |
| RuboCop | 270 files, no offenses |
| Zeitwerk eager loading | Passed |
| Brakeman 8.0.6 | 0 warnings, 0 errors |
| Bundler Audit, refreshed database | No known vulnerabilities; advisory DB commit `fb34fedf8a96f99e54bcfb9306519996a70baa25` |
| npm audit | 0 vulnerabilities |
| Production Rails assets | Passed |
| Clean production Vite build | Passed, Vite 8.3.0 |

The suite covers local Chat/structured output, tools and approvals, Knowledge,
Agent lifecycle/recovery, media storage and failure handling, evaluation/judge,
and reproduction export. Provider doubles establish local behavior only.
Browser coverage is narrower: the existing two Agent Run UI tests.

The build used locally installed Node 24.14.0; the project's setup/CI pin remains
24.21.0. This run does not certify the pinned Node setup, Docker build, hosted CI,
or a deployment. The initial sandbox Brakeman invocation failed during its
network version check; rerunning with network access completed the scan.

## Remaining acceptance boundaries

- No real provider request or paid API call was made in this review. The two
  live tests remain opt-in; live media, hosted search, Batch and judge behavior
  are not covered by the local green suite.
- No finite regression suite establishes that every RubyLLM provider is bug-free.
- Existing broad work-in-progress changes and encrypted credentials were
  preserved. No Git push, issue publication, or deployment was performed.
- The browser test server bound only to `127.0.0.1` and ended with the test
  process. No task-owned preview server or watcher is retained.
