---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 27 — Context Assembly Architecture


## Decision
A deterministic `ContextAssembler` produces ordered provider-neutral items with provenance.

Inputs may include selected messages, artefact revisions, extracted source text, context members, system instructions, and task constraints. A tokenizer abstraction estimates limits.

When limits require omission, the assembler applies documented priorities, preserves recent continuity, and records excluded material. Provider adapters perform final wire-format translation.
