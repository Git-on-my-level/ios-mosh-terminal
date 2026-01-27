# Ticket 014 — Release readiness: tests, QA checklist, attributions

## Goal
Prepare a v1 build that is shippable and maintainable.

## Deliverables
- Tests:
  - Unit tests for persistence and parsing
  - State machine tests for reconnect/idempotency
- Manual QA checklist document: `docs/QA_V1.md`
- About/Licenses screen populated with dependencies and license texts/attributions
- Basic app metadata placeholders (icons can be stubbed)

## Non-goals
- Marketing site
- Advanced analytics/crash reporting (disallowed in v1)

## Acceptance criteria
- CI (or local) test suite passes
- QA checklist covers the acceptance items from `SPEC_V1.md`
- Licenses/attributions are present and accurate
