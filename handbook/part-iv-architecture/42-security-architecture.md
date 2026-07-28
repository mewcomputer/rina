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

Deletion semantics distinguish active data, recoverable data, caches, and physical removal.
