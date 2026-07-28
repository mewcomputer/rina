---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 22 — Persistence Architecture


## Decision
Use SwiftData for structured records, the filesystem for large binary content, and Keychain Services for secrets.

Repositories hide persistence implementation from higher layers. Multi-record changes occur through logical transaction methods. External long-running work uses staged states instead of open transactions.

Every released schema change requires migration review and fixtures. Destructive migration is unacceptable without explicit export and recovery tooling. Caches are disposable and never authoritative.
