---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 21 — Presentation Architecture


## Decision
SwiftUI is the primary presentation framework. UIKit appears only through narrow interoperability wrappers when required.

Views describe state and dispatch intent. They do not persist data, call providers, extract files, or update indexes. The application adopts Dynamic Type, VoiceOver, keyboard commands, drag and drop, context menus, share sheets, Quick Look, and document pickers.

Large conversations use lazy containers, stable identity, batched streaming updates, and measured invalidation boundaries.
