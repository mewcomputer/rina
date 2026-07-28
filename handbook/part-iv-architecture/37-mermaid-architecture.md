---
status: draft
confidence: provisional
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 37 — Mermaid Architecture


## Decision
Mermaid source remains authoritative. Rendering occurs behind a `DiagramRenderer` protocol.

The likely first implementation uses an isolated `WKWebView` with bundled, version-pinned Mermaid assets. This remains provisional pending performance and security tests.

External script loading and navigation are disabled. Rendered output may be cached by source hash, renderer version, theme, and scale.
