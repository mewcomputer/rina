---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 19 — Domain Architecture


## Decision
Domain identities are strongly typed values such as `ConversationID`, `ArtefactID`, `RevisionID`, `SourceID`, and `ContextID`.

Conversations maintain ordered message references. Artefacts maintain revision lineage. Sources represent immutable imported content. Contexts reference objects. Relationships are first-class typed edges.

SwiftData records are persistence representations, not the public domain API. Mapping occurs at repository boundaries. Internal domain events may coordinate important changes without committing the product to event sourcing.
