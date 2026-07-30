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

Unknown future block types remain preservable even if a current renderer cannot display them. A block may begin incomplete and receive typed deltas. Provider reasoning traces and raw wire payloads are not ordinary text content. The native UI and explicit public conversation snapshots may expose reasoning and tool activity through dedicated disclosures, while keeping those payloads separate from ordinary response blocks.

Provider continuations may carry both a user-visible reasoning summary and provider-owned replay state. Replay state, including encrypted reasoning content, signatures, redacted thinking data, and model binding metadata, is persisted as private continuation fields so the owning adapter can resume a compatible request. Private fields are never rendered as thinking text or included in public conversation snapshots. A provider adapter must only replay opaque state when it is valid for the selected provider and model.
