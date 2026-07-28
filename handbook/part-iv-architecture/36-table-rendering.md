---
status: draft
confidence: medium
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 36 — Table Rendering Architecture


## Decision
Tables use a canonical row, column, and cell model. Markdown tables convert into this representation where possible.

Small tables size to content. Wide tables scroll horizontally with stable headers. Large tables virtualise rows or use a file-style preview. Copy and export preserve structure rather than flattening the visual layout.
