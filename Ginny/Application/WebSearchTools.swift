import Foundation

struct SearchWebTool: GinnyTool {
    private let service: any WebSearchProviding

    init(service: any WebSearchProviding) {
        self.service = service
    }

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "search_web",
            description: "Searches the web and returns concise results with citation metadata.",
            inputSchema: .object(
                properties: [
                    "query": JSONSchema(type: .string, description: "The focused web search query."),
                    "max_results": JSONSchema(type: .integer, description: "The number of results, from 1 to 20."),
                    "include_domains": JSONSchema(
                        type: .array,
                        items: JSONSchema(type: .string)
                    ),
                    "exclude_domains": JSONSchema(
                        type: .array,
                        items: JSONSchema(type: .string)
                    ),
                    "recency": JSONSchema(
                        type: .string,
                        enumValues: WebSearchRecency.allCases.map(\.rawValue)
                    ),
                    "include_answer": JSONSchema(type: .boolean)
                ],
                required: ["query"]
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .automatic }

    func execute(arguments: String) async throws -> String {
        let decoded = try decode(arguments)
        let response = try await service.search(decoded.request)
        return try String(decoding: JSONEncoder().encode(response), as: UTF8.self)
    }

    private func decode(_ arguments: String) throws -> DecodedArguments {
        guard let data = arguments.data(using: .utf8) else {
            throw ToolExecutionError.invalidArguments("search_web arguments were not valid JSON.")
        }

        do {
            return try JSONDecoder().decode(DecodedArguments.self, from: data)
        } catch {
            throw ToolExecutionError.invalidArguments("search_web arguments were not valid JSON.")
        }
    }

    private struct DecodedArguments: Decodable {
        let request: WebSearchRequest

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let query = try container.decode(String.self, forKey: .query)
            let maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? 5
            let includeDomains = try container.decodeIfPresent([String].self, forKey: .includeDomains) ?? []
            let excludeDomains = try container.decodeIfPresent([String].self, forKey: .excludeDomains) ?? []
            let recency = try container.decodeIfPresent(WebSearchRecency.self, forKey: .recency)
            let includeAnswer = try container.decodeIfPresent(Bool.self, forKey: .includeAnswer) ?? false
            request = WebSearchRequest(
                query: query,
                maxResults: maxResults,
                includeDomains: includeDomains,
                excludeDomains: excludeDomains,
                recency: recency,
                includeAnswer: includeAnswer
            )
        }

        private enum CodingKeys: String, CodingKey {
            case query
            case maxResults = "max_results"
            case includeDomains = "include_domains"
            case excludeDomains = "exclude_domains"
            case recency
            case includeAnswer = "include_answer"
        }
    }
}
