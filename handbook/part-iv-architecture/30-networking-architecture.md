---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 30 — Networking Architecture


## Decision
Use `URLSession` behind a narrow transport protocol.

The request pipeline validates endpoint, injects authentication, encodes headers and body, applies timeout policy, executes, validates response, and maps errors.

Retries apply only to operations classified safe and retryable. Authentication, malformed request, and most client errors are not retried automatically. Swift task cancellation propagates to `URLSessionTask`.
