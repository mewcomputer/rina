---
status: draft
confidence: medium
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 44 — Background Work and Lifecycle


## Decision
Assume foreground ownership for remote generation unless a platform-supported background mode applies. Persist progress frequently enough that suspension does not erase completed work.

Imports, indexing, extraction, export, and persistence use cancellable actor-coordinated tasks. Background time is opportunistic and never required for correctness.

Audio playback follows declared audio-session behaviour.
