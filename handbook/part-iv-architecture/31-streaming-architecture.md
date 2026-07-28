---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 31 — Streaming Architecture


## Decision
Provider streams become `AsyncSequence` values of canonical events.

```mermaid
flowchart LR
 A[URLSession bytes] --> B[Framer] --> C[Provider parser] --> D[Canonical events]
 D --> E[Conversation engine]
 E --> F[Renderer]
 E --> G[Persistence]
 E --> H[Speech segmenter]
```

SSE parsing operates on bytes and line boundaries, tolerates split chunks, supports multi-line data, and never equates a network chunk with an event.

Events include response start, block start, text delta, metadata delta, block end, usage, finish reason, warning, and response end. Persistence batches deltas. Malformed streams preserve partial content and produce typed errors.
