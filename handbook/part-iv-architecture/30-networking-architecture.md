---
status: draft
confidence: high
implementation-state: partial
last-reviewed: 2026-07-27
---

# Chapter 30 — Networking Architecture


## Decision
Use `URLSession` behind a narrow transport protocol.

The request pipeline validates endpoint, injects authentication, encodes headers and body, applies timeout policy, executes, validates response, and maps errors.

Retries apply only to operations classified safe and retryable. Authentication, malformed request, and most client errors are not retried automatically. Swift task cancellation propagates to `URLSessionTask`.

The current streaming transport uses `URLSession.bytes(for:)` and exposes status-checked byte sequences behind `StreamingTransport`.

Web artefacts use a separate browser network policy. `connect-src` is `none` by default. An artefact may declare up to eight exact HTTPS origins in `metadata.networkOrigins` as a JSON array; the preview then permits `fetch`, XHR, WebSocket, and related connections only to those origins. Inline artefacts that request network capability require approval. The preview uses a non-persistent web data store and never receives provider credentials.
