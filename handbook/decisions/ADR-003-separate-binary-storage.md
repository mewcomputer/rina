# ADR — Separate binary and structured storage

**Status:** Accepted

## Decision
Store large binary payloads in content-addressed filesystem storage and metadata in SwiftData.

## Consequences
The choice creates a stable architectural direction while preserving replaceable implementation boundaries.
