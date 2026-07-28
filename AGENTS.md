# Ginny agent guide

## Project shape

Ginny is a native, local-first iOS workspace for intelligent systems. The `handbook/` directory is the product and architecture source of truth while implementation is being established.

Read the relevant handbook chapter before changing behaviour:

- Part I explains the product's principles and interaction posture.
- Part II defines product concepts, terminology, information architecture, and user journeys.
- Part III is normative behaviour and specification.
- Part IV explains the implementation architecture.
- `handbook/decisions/` contains accepted architectural decisions. A changed rationale needs a new or superseding ADR.

Keep the handbook's distinction between conversations, artefacts, sources, contexts, providers, models, and local intelligence. Avoid describing the product as merely an AI chat client.

## Source layout

- `Ginny/Presentation/` contains SwiftUI views and UI state.
- `Ginny/Application/` contains use-case orchestration and the composition root.
- `Ginny/Domain/` contains framework-independent identities, value types, and contracts.
- `Ginny/Infrastructure/` is reserved for persistence, provider transports, indexes, extractors, and renderers.
- `Ginny/Platform/` is reserved for narrow Apple-framework integrations.
- `GinnyTests/` contains unit and contract tests.

Dependencies point toward stable domain contracts. The domain must not import SwiftUI, SwiftData, vendor SDKs, or rendering frameworks. Use Swift Concurrency, actor isolation, and `Sendable` where shared state crosses concurrency boundaries. Keep UI state on the main actor.

Use constructor injection with one application composition root. Do not introduce a global service locator or an untyped environment registry. Keep secrets in Keychain, structured records in SwiftData, and large binary content in the filesystem as described by the handbook.

## Development workflow

The Xcode project is generated from `project.yml`; edit the spec rather than hand-editing `Ginny.xcodeproj/project.pbxproj`. Regenerate after project-structure changes:

```sh
xcodegen generate --spec project.yml
```

Open `Ginny.xcworkspace` in Xcode. Useful checks are:

```sh
xcodebuild -workspace Ginny.xcworkspace -scheme Ginny -showBuildSettings
xcodebuild -workspace Ginny.xcworkspace -scheme Ginny -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace Ginny.xcworkspace -scheme Ginny -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

Write tests before implementation when adding behaviour. Cover normal, boundary, cancellation, malformed-input, and error paths where they apply. Prefer tests of observable behaviour and real parsing/storage boundaries over tests that only verify mocks.

Keep changes narrow and reviewable. Preserve existing user work, do not use destructive git commands, and stage files intentionally. Update the relevant handbook chapter when implementation changes its documented contract.
