---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 25 — Revision Architecture


## Decision
Artefact revisions are immutable. An artefact points to its current revision and retains ordered lineage.

Editing uses transient drafts, periodic autosave checkpoints, and explicit user checkpoints. Restoring an older revision creates a new revision rather than rewriting history.

Initial releases retain revisions. Future compaction must preserve explicit checkpoints and be documented as policy.
