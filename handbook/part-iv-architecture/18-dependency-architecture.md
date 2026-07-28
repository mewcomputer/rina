---
status: draft
confidence: high
implementation-state: pre-implementation
last-reviewed: 2026-07-27
---

# Chapter 18 — Dependency Architecture


## Decision
Use explicit constructor injection with one application composition root. Do not use a global service locator.

Application-lifetime services include repositories, provider registry, attachment store, search coordinator, and secure credential store. Scene-lifetime services own navigation and scene presentation state. Generation, import, export, and extraction services are operation-scoped.

SwiftUI environment values may carry constructed feature dependencies, but must not become an untyped registry. Clocks, identifiers, transports, storage, and capability discovery are injectable for deterministic tests.
