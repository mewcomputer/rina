---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 23 — Attachment and File Storage


## Decision
Binary content is written through an `AttachmentStore` using content-derived addresses, preferably SHA-256.

Write flow: stream to a temporary file, compute the digest, validate expected properties, atomically move into content-addressed storage, then commit metadata.

Imported names are metadata, not trusted paths. Cleanup derives from persisted references plus a grace period. Missing or corrupt files become explicit integrity errors.
