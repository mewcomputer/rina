---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 29 — Model and Capability Resolution


## Decision
Capabilities are explicit values: text generation, streaming, structured output, image generation, local rewriting, speech synthesis, embeddings, and future extensions.

Resolution considers user choice, provider availability, runtime platform support, model capability, privacy posture, and operation needs. User choice wins when valid; otherwise a documented default applies.

Unsupported combinations fail before network work begins. Local intelligence is preferred for lightweight private tasks when adequate.
