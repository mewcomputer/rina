---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 46 — Testing Architecture


## Decision
Use pure domain tests, repository contract tests, provider fixture tests, byte-level stream parser tests, SwiftData migration tests, renderer snapshots, accessibility tests, and end-to-end smoke tests.

Tests inject clocks, identifiers, transports, capability discovery, and file locations. Every provider adapter is exercised against normal, fragmented, malformed, cancelled, and error fixtures.

A released schema cannot change without migration fixtures from earlier versions.
