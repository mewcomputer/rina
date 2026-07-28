---
status: draft
confidence: medium
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 35 — Code Rendering Architecture


## Decision
Code blocks retain source text, optional language, and presentation metadata. A replaceable highlighter supplies syntax colour.

Code uses monospaced typography, supports copy, respects accessibility scaling, and uses horizontal scrolling where wrapping damages meaning. Language detection may improve presentation but never rewrites source.

The initial application displays code but does not execute it.
