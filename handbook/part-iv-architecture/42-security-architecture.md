---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 42 — Security Architecture


## Decision
Secrets use Keychain Services. Files use appropriate iOS Data Protection. Logs exclude prompts, source content, credentials, and response bodies by default.

Remote providers, custom endpoints, imported files, Mermaid rendering, and external links are trust boundaries. Credentials are referenced by opaque identifiers and injected only during authorised request construction.

Web retrieval is a separate trust boundary. `fetch_url` is approval-required and currently accepts only HTTP and HTTPS targets intended for public web content. It rejects known local/private hostname and literal-address forms, embedded credentials, and non-standard ports; validates each redirect; uses an ephemeral session without cookies or credential storage; caps redirects, response size, and timeout; and does not execute fetched scripts. Fetched text is marked as untrusted data in the tool result. Page content must never be treated as agent instructions or permission to disclose workspace data. This client-side policy is not a server-grade SSRF boundary; DNS resolution and rebinding hardening remain follow-up work if remote fetching expands.

Deletion semantics distinguish active data, recoverable data, caches, and physical removal.
