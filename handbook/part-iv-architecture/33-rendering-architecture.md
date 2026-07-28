---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 33 — Rendering Architecture


## Decision
Rendering is block-oriented. A registry selects a renderer for each canonical block type.

Stable block identity prevents full message reconstruction during streaming. Text deltas are batched at a perceptually smooth cadence. Unsupported blocks show a safe summary while preserving their payload.

Renderers support native selection, meaningful copy behaviour, accessible reading order, and alternatives for visual-only content.
