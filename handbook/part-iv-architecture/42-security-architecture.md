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

Web artefacts are network-isolated by default. Their preview CSP denies connections, images, fonts, frames, and external scripts unless the runtime explicitly provides a safe source. An artefact can request exact HTTPS origins through `metadata.networkOrigins`, which triggers approval for inline artefacts. The preview uses a non-persistent `WKWebView` data store without application cookies or credentials. Network responses remain untrusted page data and cannot grant tool or filesystem access.


Deletion semantics distinguish active data, recoverable data, caches, and physical removal.
