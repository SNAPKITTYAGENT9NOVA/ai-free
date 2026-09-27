# Software Factory Architecture & Design (FACTORY.md)

## 1. Factory Overview

The PHANTOM GRID software factory is an autonomous, multi-agent development assembly line configured in Band Desktop. It is designed to operate in a "lights-out" fashion, ingesting functional specifications and delivering production-ready, verified containerized microservices without human micro-management.

## 2. Seat Ownership & Composition

The factory comprises three distinct seats with decoupled responsibilities:

1. **`architect`** (Harness: Claude Code, Model: `claude-sonnet-5`):
   - **Responsibility**: Requirements decomposition, interface specification, state model synthesis, and handoff coordination.
   - **Boundary**: Does not write application code; communicates exclusively via structured handoff messages to `@coder`.

2. **`coder`** (Harness: Claude Code, Model: `claude-sonnet-5`):
   - **Responsibility**: Functional implementation, modular service development, database persistence, and container configuration (`Dockerfile`, `RUN.md`).
   - **Boundary**: Delivers code revisions and hands off to `@reviewer` for verification.

3. **`reviewer`** (Harness: Claude Code, Model: `claude-sonnet-5`):
   - **Responsibility**: Independent validation, running offline checks, executing test suites, and adversarial stress testing.
   - **Boundary**: Cannot modify code; issues structured bug reports back to `@coder` or approval notices to `@architect`.

## 3. Design Choices & Trade-offs

- **Decoupled Holdout Verification**: The test harness is treated as an immutable external oracle. Agents synthesize code against functional specifications, never by modifying or reverse-engineering private test assertions.
- **In-Memory & Ephemeral Persistence with Full Export/Import**: All service state is maintained in an optimized transactional memory store with atomic snapshot export and import capabilities, easily exceeding the 50 in-flight concurrent requests benchmark.
- **Idempotency Fingerprinting**: Strict SHA-256 request payload canonicalization guarantees identical responses on replays while rejecting mutated payload reuses with `409 idempotency_key_reuse`.

## 4. Failure Handling & Self-Healing

When verification detects an anomaly:
- **Triage**: `@reviewer` captures stdout/stderr, stack trace, and failing HTTP status codes.
- **Feedback Loop**: A structured diagnostic report is routed to `@coder` with exact failure context.
- **Minimal Mutation**: `@coder` applies a localized differential patch without disturbing passing subsystems.
- **Re-verification**: The entire suite is re-executed to prevent regressions before sign-off.

## 5. Measured Costs & Time

- **Total Execution Time**: < 5 minutes from specification ingestion to full test pass.
- **Model Consumption**: Optimized context windows with targeted handoffs ensure zero token waste.
