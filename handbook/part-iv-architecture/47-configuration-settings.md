---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 47 — Configuration and Settings Architecture


## Decision
Non-secret durable settings use a typed settings repository. Secrets remain in Keychain. Feature flags are explicit and environment-aware.

Provider configuration contains provider type, display name, endpoint, credential reference, permitted custom headers, and model preferences. Endpoint and model validation occur before use.

Settings keys are versioned and migrated through typed transformations.
