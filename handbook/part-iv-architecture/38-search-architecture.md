---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 38 — Search Architecture


## Decision
Combine structured metadata queries with a local full-text index. Define a semantic-search boundary but keep its model and index provisional.

Repositories emit indexable changes. An indexing actor coalesces updates and records index version. Ranking considers textual relevance, title matches, object type, recency, authorship, and relationship proximity.

Indexes remain on-device and eventually consistent. Primary objects remain openable when indexing is delayed.
