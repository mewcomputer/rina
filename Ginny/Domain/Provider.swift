import Foundation

enum ProviderID: String, CaseIterable, Codable, Equatable, Sendable {
    case umans
    case kimi
    case kimiCode
    case openAICompatible
    case codex

    var displayName: String {
        switch self {
        case .umans:
            "Umans"
        case .kimi:
            "Kimi"
        case .kimiCode:
            "Kimi Code"
        case .openAICompatible:
            "OpenAI-compatible"
        case .codex:
            "Codex"
        }
    }
}

enum ThinkingLevel: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case off
    case on
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    var displayName: String {
        rawValue.capitalized
    }
}

enum ProviderMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
}

struct ProviderContinuation: Codable, Equatable, Sendable {
    let provider: ProviderID
    let id: String
    let kind: String
    var fields: [String: String]
    var privateFields: Set<String>

    init(
        provider: ProviderID,
        id: String,
        kind: String,
        fields: [String: String],
        privateFields: Set<String> = []
    ) {
        self.provider = provider
        self.id = id
        self.kind = kind
        self.fields = fields
        self.privateFields = privateFields
    }

    init(provider: ProviderID, id: String, kind: String, fields: [String: String]) {
        self.init(
            provider: provider,
            id: id,
            kind: kind,
            fields: fields,
            privateFields: []
        )
    }

    var shareableFields: [String: String] {
        fields.filter { !privateFields.contains($0.key) }
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case id
        case kind
        case fields
        case privateFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ProviderID.self, forKey: .provider)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        fields = try container.decode([String: String].self, forKey: .fields)
        let decodedPrivateFields = try container.decodeIfPresent(Set<String>.self, forKey: .privateFields)
        privateFields = decodedPrivateFields ?? Set(fields.keys.filter(Self.defaultPrivateFieldNames.contains))
    }

    private static let defaultPrivateFieldNames: Set<String> = [
        "data",
        "encrypted_content",
        "model",
        "signature",
    ]
}

struct ProviderContinuationDelta: Equatable, Sendable {
    enum Operation: Equatable, Sendable {
        case append
        case replace
    }

    let provider: ProviderID
    let id: String
    let kind: String
    let field: String
    let value: String
    let operation: Operation
    let isPrivate: Bool

    init(
        provider: ProviderID,
        id: String,
        kind: String,
        field: String,
        value: String,
        operation: Operation,
        isPrivate: Bool = false
    ) {
        self.provider = provider
        self.id = id
        self.kind = kind
        self.field = field
        self.value = value
        self.operation = operation
        self.isPrivate = isPrivate
    }

    init(
        provider: ProviderID,
        id: String,
        kind: String,
        field: String,
        value: String,
        operation: Operation
    ) {
        self.init(
            provider: provider,
            id: id,
            kind: kind,
            field: field,
            value: value,
            operation: operation,
            isPrivate: false
        )
    }
}

enum JSONSchemaType: String, Codable, Equatable, Sendable {
    case object
    case array
    case string
    case number
    case integer
    case boolean
    case null
}

indirect enum JSONSchemaAdditionalProperties: Codable, Equatable, Sendable {
    case boolean(Bool)
    case schema(JSONSchema)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .schema(try container.decode(JSONSchema.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value):
            try container.encode(value)
        case .schema(let schema):
            try container.encode(schema)
        }
    }
}

final class JSONSchema: Codable, Equatable, Sendable {
    let type: JSONSchemaType
    let description: String?
    let properties: [String: JSONSchema]?
    let required: [String]?
    let items: JSONSchema?
    let enumValues: [String]?
    let additionalProperties: JSONSchemaAdditionalProperties?

    init(
        type: JSONSchemaType,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        items: JSONSchema? = nil,
        enumValues: [String]? = nil,
        additionalProperties: JSONSchemaAdditionalProperties? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items
        self.enumValues = enumValues
        self.additionalProperties = additionalProperties
    }

    static func object(
        properties: [String: JSONSchema],
        required: [String] = [],
        additionalProperties: JSONSchemaAdditionalProperties = .boolean(false),
        description: String? = nil
    ) -> JSONSchema {
        JSONSchema(
            type: .object,
            description: description,
            properties: properties,
            required: required.isEmpty ? nil : required,
            additionalProperties: additionalProperties
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case required
        case items
        case enumValues = "enum"
        case additionalProperties
    }

    static func == (lhs: JSONSchema, rhs: JSONSchema) -> Bool {
        lhs.type == rhs.type
            && lhs.description == rhs.description
            && lhs.properties == rhs.properties
            && lhs.required == rhs.required
            && lhs.items == rhs.items
            && lhs.enumValues == rhs.enumValues
            && lhs.additionalProperties == rhs.additionalProperties
    }
}

struct ProviderToolDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONSchema
}

struct ProviderToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    var arguments: String
    var isComplete: Bool
}

struct ProviderToolCallDelta: Equatable, Sendable {
    let provider: ProviderID
    let id: String
    let name: String?
    let arguments: String?
}

struct ProviderMessage: Codable, Equatable, Sendable {
    let role: ProviderMessageRole
    let content: String
    let continuations: [ProviderContinuation]
    let toolCalls: [ProviderToolCall]
    let toolCallID: String?
    let toolResultIsError: Bool?

    init(
        role: ProviderMessageRole,
        content: String,
        continuations: [ProviderContinuation] = [],
        toolCalls: [ProviderToolCall] = [],
        toolCallID: String? = nil,
        toolResultIsError: Bool? = nil
    ) {
        self.role = role
        self.content = content
        self.continuations = continuations
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolResultIsError = toolResultIsError
    }

    static func user(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .user, content: content)
    }

    static func assistant(
        _ content: String,
        continuations: [ProviderContinuation] = [],
        toolCalls: [ProviderToolCall] = []
    ) -> ProviderMessage {
        ProviderMessage(
            role: .assistant,
            content: content,
            continuations: continuations,
            toolCalls: toolCalls
        )
    }

    static func system(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .system, content: content)
    }

    static func tool(_ content: String, callID: String, isError: Bool = false) -> ProviderMessage {
        ProviderMessage(
            role: .tool,
            content: content,
            toolCallID: callID,
            toolResultIsError: isError
        )
    }
}

struct ProviderRequest: Equatable, Sendable {
    let messages: [ProviderMessage]
    let tools: [ProviderToolDefinition]

    init(messages: [ProviderMessage], tools: [ProviderToolDefinition] = []) {
        self.messages = messages
        self.tools = tools
    }
}

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var provider: ProviderID
    var endpoint: URL
    var model: String
    var credentialID: String
    var thinkingLevel: ThinkingLevel?
    var supportsTools: Bool?

    init(endpoint: URL, model: String, credentialID: String) {
        provider = .openAICompatible
        self.endpoint = endpoint
        self.model = model
        self.credentialID = credentialID
        thinkingLevel = nil
        supportsTools = nil
    }

    init(
        provider: ProviderID,
        endpoint: URL,
        model: String,
        credentialID: String,
        thinkingLevel: ThinkingLevel? = nil,
        supportsTools: Bool? = nil
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.credentialID = credentialID
        self.thinkingLevel = thinkingLevel
        self.supportsTools = supportsTools
    }
}

enum ProviderStreamEvent: Equatable, Sendable {
    case responseStarted
    case textDelta(String)
    case continuationDelta(ProviderContinuationDelta)
    case toolCallDelta(ProviderToolCallDelta)
    case finish(reason: String?)
    case responseEnded
}

enum ProviderError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case missingCredential
    case invalidResponse
    case httpStatus(Int, message: String?)
    case malformedEvent
    case remote(message: String)
}

protocol ProviderAdapter: Sendable {
    var supportsTools: Bool { get }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}
