---
status: draft
confidence: medium
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 45 — Observability and Diagnostics


## Decision
Use `os.Logger` for structured logging and `OSSignposter` or equivalent APIs for performance tracing.

Correlation identifiers connect request, stream, persistence, render, and completion without storing content. Useful local metrics include time to first event, throughput, save latency, render latency, extraction duration, and index lag.

Remote analytics would require a separate product and privacy decision.
