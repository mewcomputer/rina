---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 40 — Speech Architecture


## Decision
Define a `SpeechSynthesiser` protocol and a separate actor-isolated playback coordinator.

Apple speech synthesis is the default local implementation. A neural backend may implement the same contract.

Streaming text passes through sentence-and-clause segmentation. Only stable segments are queued; the final incomplete segment flushes at completion. User interruption stops active playback and clears queued speech.
