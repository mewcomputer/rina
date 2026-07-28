# Draft Status
This edition is coherent enough to guide implementation, and the first provider-backed conversation slice is now implemented.

**High confidence:** object model, local-first posture, graph relationships, SwiftUI, SwiftData/filesystem/Keychain split, provider adapters, canonical streams, native rendering, speech boundary, security, testing.

**Implemented slice:** OpenAI-compatible streaming requests use a narrow URLSession byte transport, fragmented SSE parsing, canonical provider events, Keychain credentials, and SwiftStreamingMarkdown rendering. Conversation state preserves completed and partial assistant content in the active session.

**Provisional:** semantic search implementation, neural TTS backend, Mermaid renderer, exact multi-window behaviour, sync protocol, image-editing workflows.
