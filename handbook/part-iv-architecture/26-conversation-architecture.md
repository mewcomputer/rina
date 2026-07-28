---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 26 — Conversation Architecture


## Decision
A conversation is a stable aggregate with stable message identities. Generation is an explicit turn with lifecycle:

`idle → preparing → streaming → completed | cancelled | failed`

Messages contain canonical content blocks, not provider response objects. Provider metadata remains provenance or diagnostics.

Promoting content creates or updates an artefact and records a `derivedFrom` relationship. The artefact is not owned by the conversation. Parent references keep the model branch-ready without requiring a branching UI in v1.
