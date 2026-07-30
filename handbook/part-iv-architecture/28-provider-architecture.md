---
status: draft
confidence: high
implementation-state: partial
last-reviewed: 2026-07-27
---

# Chapter 28 — Provider Architecture


## Decision
Each provider implements a common `ProviderAdapter` contract and publishes capability descriptors, including reasoning and tool-call support.

OpenAI-compatible and Anthropic-compatible endpoints use distinct adapter families because compatibility is partial and provider-specific. Adapters own model discovery, request translation, authentication, streaming translation, usage metadata, tool-call translation, and error normalisation.

Model identity is provider-qualified. Vendor SDK types never cross the adapter boundary. Custom endpoints require validation, secure credential association, and adapter contract tests.

The first adapter implementation targets OpenAI-compatible chat-completions endpoints. Its endpoint, model, and credential are configured independently of the conversation model so additional provider families can be added without changing user-owned message identities.

Responses-style adapters must validate tool-call identity before replay. The item ID and function-call ID are distinct provider fields and must be mapped to one canonical local call identity. If a provider streams arguments before a usable function name, the adapter buffers those arguments until a function-call completion event supplies a non-empty name. Final argument events are authoritative, must not duplicate already-streamed arguments, and every successful stream must include a terminal response event. Malformed persisted calls or malformed stream events fail locally before a request is sent. OAuth credentials may only be sent to the provider's pinned official endpoint.
