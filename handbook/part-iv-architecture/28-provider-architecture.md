---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 28 — Provider Architecture


## Decision
Each provider implements a common `ProviderAdapter` contract and publishes capability descriptors.

OpenAI-compatible and Anthropic-compatible endpoints use distinct adapter families because compatibility is partial and provider-specific. Adapters own model discovery, request translation, authentication, streaming translation, usage metadata, and error normalisation.

Model identity is provider-qualified. Vendor SDK types never cross the adapter boundary. Custom endpoints require validation, secure credential association, and adapter contract tests.
