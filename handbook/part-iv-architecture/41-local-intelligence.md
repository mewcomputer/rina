---
status: draft
confidence: medium
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 41 — Local Intelligence Architecture


## Decision
Apple Foundation Models are the preferred implementation of local intelligence when runtime capability is available.

Initial tasks: title generation, summarisation, rewriting, metadata suggestions, and lightweight classification.

Tasks use narrow sessions, explicit instructions, and structured outputs where appropriate. Generated data is validated. Unavailable or unsuitable tasks may fall back to a configured remote provider with clear privacy implications.

Exact API usage must be reviewed against the chosen deployment target and current SDK.
