---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 39 — Content Extraction Architecture


## Decision
Extraction is type-driven and asynchronous.

- PDF text and metadata: PDFKit
- image text when needed: Vision
- plain text and Markdown: direct decoding and Foundation
- type identification: Uniform Type Identifiers

Sources move through pending, extracting, ready, partially ready, or failed. Original content is never mutated. Derived text records include extractor version and provenance.
