---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 20 — Application State Architecture


## Decision
Classify state before storing it.

- Persistent state belongs in repositories.
- Session state belongs in application services or scene coordinators.
- Operation state belongs to the active task or actor.
- Pure visual state remains local to SwiftUI.

`@Observable` types may expose state to SwiftUI and are main-actor isolated when they drive UI. Navigation is typed state. Streaming uses stable message and block identities with progressively persisted content.
