## What and why

<!-- The behavior change and the reason for it. Link the issue. -->

## Checks

- [ ] `bin/rails test` and `bin/rails test:system`
- [ ] `bin/rubocop`, `bin/brakeman --no-pager`, `bin/rails zeitwerk:check`
- [ ] Docs, diagrams and changelog updated in the same change (evidence only in `docs/CAPABILITIES.md`)
- [ ] No provider calls in tests; live checks (if any) recorded with date, model and cost
- [ ] No credentials, private data or `config/credentials.yml.enc` in the diff

## Migrations or security implications

<!-- None, or describe them. -->
