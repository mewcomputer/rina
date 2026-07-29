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

The `fetch_url` tool uses a separate narrow transport. Its first implementation accepts only HTTP and HTTPS URLs intended for public web content, rejects known local/private hostname and literal-address forms plus embedded credentials and non-standard ports, revalidates redirect targets, uses an ephemeral credential-free `URLSession`, limits redirects, response bytes, and elapsed time, and accepts readable text formats only. It extracts text without executing page scripts and returns the source URL and response metadata with an explicit untrusted-content marker. Fetches require user approval until URL provenance and domain allowlists are represented in application state. This client-side policy is not a server-grade SSRF boundary; DNS resolution and rebinding hardening remain follow-up work if remote fetching expands.
