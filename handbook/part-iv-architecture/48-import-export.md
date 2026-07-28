---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 48 — Import and Export Architecture


## Decision
Use Uniform Type Identifiers to define formats and native document pickers and share-sheet integration for entry points.

Imports stage content, validate type and size, commit to content-addressed storage, create source records, and schedule extraction.

Artefacts export through format-specific exporters. Markdown and text preserve source. Rich formats render from canonical blocks. A future package format may bundle objects and relationships but must not become the only path.
