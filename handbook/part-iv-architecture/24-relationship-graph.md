---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 24 — Relationship Graph Architecture


## Decision
Persist relationships as directed typed edges with source identity, predicate, target identity, timestamps, and optional attributes.

Initial predicates include `relatedTo`, `derivedFrom`, `revisionOf`, `references`, and `supportedBy`.

Repositories support incoming, outgoing, and predicate-filtered queries. Deleting an object does not cascade through semantic relationships. The initial vocabulary remains curated rather than becoming a general ontology editor.
