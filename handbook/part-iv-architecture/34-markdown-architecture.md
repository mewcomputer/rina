---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 34 — Markdown Architecture


## Decision
Parse Markdown into a semantic intermediate representation and render with native SwiftUI and text components.

`AttributedString` Markdown support may handle compatible inline content but is not the sole parser for block semantics. Incomplete streaming syntax is expected; the renderer incrementally reparses at block boundaries and falls back to safe plain text.

Raw HTML is not executed by default. Links are validated. Original source is preserved for export fidelity.
