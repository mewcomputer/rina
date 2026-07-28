---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 32 — Structured Response Architecture


## Decision
Messages contain ordered canonical blocks with stable identifiers and versioned payloads.

Initial types: text, markdown, code, table, Mermaid, image, file reference, citation group, tool call, tool result, and provider notice.

Unknown future block types remain preservable even if a current renderer cannot display them. A block may begin incomplete and receive typed deltas. Provider reasoning traces and raw wire payloads are not ordinary user-visible content.
