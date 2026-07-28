# Draft Status
This edition is coherent enough to guide implementation, and the first provider-backed conversation slice is now implemented.

**High confidence:** object model, local-first posture, graph relationships, SwiftUI, SwiftData/filesystem/Keychain split, provider adapters, canonical streams, native rendering, speech boundary, security, testing.

**Implemented slice:** OpenAI-compatible and Anthropic-compatible streaming requests use a narrow URLSession byte transport, fragmented SSE parsing, canonical provider events, Keychain credentials, and SwiftStreamingMarkdown rendering. Generation is cancellable end to end and preserves partial content in active and persisted sessions. Provider continuation metadata preserves Kimi reasoning text and Anthropic thinking/signature blocks across turns. OpenAI-compatible models can receive tool definitions, stream tool calls, execute the safe read-only `current_time` tool, persist tool-call/result blocks, and resume the generation.

**Provisional:** semantic search implementation, neural TTS backend, Mermaid renderer, Anthropic tool execution, exact multi-window behaviour, sync protocol, image-editing workflows, and broader tool permission/approval flows.
