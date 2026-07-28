---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 43 — Error Architecture


## Decision
Each subsystem maps implementation failures into typed domain-level errors before crossing its boundary.

Errors carry category, retryability, recovery suggestion, diagnostic cause, and relevant operation identity. Partial results are represented explicitly for streaming, import, extraction, and export.

The UI shows concise outcomes and recovery actions. Raw HTTP bodies, stack traces, and provider payloads remain diagnostics.
