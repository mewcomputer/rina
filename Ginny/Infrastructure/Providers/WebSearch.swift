import Foundation

struct WebSearchHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol WebSearchTransport: Sendable {
    func response(for request: URLRequest) async throws -> WebSearchHTTPResponse
}

struct URLSessionWebSearchTransport: WebSearchTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func response(for request: URLRequest) async throws -> WebSearchHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        return WebSearchHTTPResponse(statusCode: response.statusCode, data: data)
    }
}

enum WebSearchError: LocalizedError, Equatable, Sendable {
    case missingCredential(WebSearchProviderID)
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case providerUnavailable(WebSearchProviderID)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let provider):
            "Add a " + provider.displayName + " API key in Settings before searching."
        case .invalidBaseURL:
            "The web search base URL is invalid."
        case .invalidResponse:
            "The web search provider returned an invalid response."
        case .httpStatus(let status):
            "The web search provider returned HTTP " + String(status) + "."
        case .providerUnavailable(let provider):
            "The configured web search provider is unavailable: " + provider.displayName + "."
        case .requestFailed(let message):
            "Web search failed: " + message
        }
    }
}

protocol WebSearchProvider: Sendable {
    var id: WebSearchProviderID { get }

    func search(
        request: WebSearchRequest,
        baseURL: URL,
        credential: String
    ) async throws -> WebSearchResponse
}

struct TavilyWebSearchProvider: WebSearchProvider {
    let id: WebSearchProviderID = .tavily
    private let transport: any WebSearchTransport

    init(transport: any WebSearchTransport = URLSessionWebSearchTransport()) {
        self.transport = transport
    }

    func search(
        request: WebSearchRequest,
        baseURL: URL,
        credential: String
    ) async throws -> WebSearchResponse {
        let url = try searchURL(baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(TavilyRequest(request: request))

        let response = try await transport.response(for: urlRequest)
        try validate(response)
        let decoded = try decode(TavilyResponse.self, from: response.data)

        return WebSearchResponse(
            query: request.query,
            provider: id,
            answer: decoded.answer,
            results: decoded.results.map { result in
                WebSearchResult(
                    title: result.title,
                    url: result.url,
                    snippet: result.content,
                    publishedAt: result.publishedDate,
                    score: result.score,
                    provider: id
                )
            }
        )
    }
}

struct ExaWebSearchProvider: WebSearchProvider {
    let id: WebSearchProviderID = .exa
    private let transport: any WebSearchTransport

    init(transport: any WebSearchTransport = URLSessionWebSearchTransport()) {
        self.transport = transport
    }

    func search(
        request: WebSearchRequest,
        baseURL: URL,
        credential: String
    ) async throws -> WebSearchResponse {
        let url = try searchURL(baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(credential, forHTTPHeaderField: "x-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(ExaRequest(request: request))

        let response = try await transport.response(for: urlRequest)
        try validate(response)
        let decoded = try decode(ExaResponse.self, from: response.data)

        return WebSearchResponse(
            query: request.query,
            provider: id,
            answer: nil,
            results: decoded.results.map { result in
                let snippet = result.highlights?.joined(separator: "\n")
                    ?? result.text
                    ?? ""
                return WebSearchResult(
                    title: result.title,
                    url: result.url,
                    snippet: snippet,
                    publishedAt: result.publishedDate,
                    author: result.author,
                    provider: id
                )
            }
        )
    }
}

protocol WebSearchProviding: Sendable {
    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse
}

final class WebSearchConfigurationStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configuration() -> WebSearchConfiguration {
        let provider = WebSearchProviderID(
            rawValue: defaults.string(forKey: WebSearchPreferences.providerKey) ?? ""
        ) ?? .tavily
        let storedURL = defaults.string(
            forKey: WebSearchPreferences.baseURLKeyPrefix + provider.rawValue
        )
        let baseURL = storedURL.flatMap(URL.init(string:))
            ?? URL(string: provider.defaultBaseURL)!
        return WebSearchConfiguration(provider: provider, baseURL: baseURL)
    }
}

struct WebSearchService: WebSearchProviding {
    private let configurationStore: WebSearchConfigurationStore
    private let credentialStore: any CredentialStore
    private let providers: [any WebSearchProvider]

    init(
        configurationStore: WebSearchConfigurationStore = WebSearchConfigurationStore(),
        credentialStore: any CredentialStore,
        transport: any WebSearchTransport = URLSessionWebSearchTransport(),
        providers: [any WebSearchProvider]? = nil
    ) {
        self.configurationStore = configurationStore
        self.credentialStore = credentialStore
        self.providers = providers ?? [
            TavilyWebSearchProvider(transport: transport),
            ExaWebSearchProvider(transport: transport)
        ]
    }

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("search_web requires a non-empty query.")
        }

        let configuration = configurationStore.configuration()
        guard let credential = try credentialStore.credential(
            for: configuration.provider.credentialID
        ), !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebSearchError.missingCredential(configuration.provider)
        }

        guard let provider = providers.first(where: { $0.id == configuration.provider }) else {
            throw WebSearchError.providerUnavailable(configuration.provider)
        }
        return try await provider.search(
            request: request,
            baseURL: configuration.baseURL,
            credential: credential
        )
    }
}

private struct TavilyRequest: Encodable {
    let query: String
    let maxResults: Int
    let searchDepth = "basic"
    let includeAnswer: Bool
    let includeRawContent = false
    let includeDomains: [String]?
    let excludeDomains: [String]?
    let timeRange: String?

    init(request: WebSearchRequest) {
        query = request.query
        maxResults = min(request.maxResults, 20)
        includeAnswer = request.includeAnswer
        includeDomains = request.includeDomains.isEmpty ? nil : request.includeDomains
        excludeDomains = request.excludeDomains.isEmpty ? nil : request.excludeDomains
        timeRange = request.recency?.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
        case searchDepth = "search_depth"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case includeDomains = "include_domains"
        case excludeDomains = "exclude_domains"
        case timeRange = "time_range"
    }
}

private struct TavilyResponse: Decodable {
    let answer: String?
    let results: [TavilyResult]
}

private struct TavilyResult: Decodable {
    let title: String
    let url: String
    let content: String
    let score: Double?
    let publishedDate: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}

private struct ExaRequest: Encodable {
    let query: String
    let numResults: Int
    let includeDomains: [String]?
    let excludeDomains: [String]?
    let contents: ExaContents
    let startPublishedDate: String?

    init(request: WebSearchRequest) {
        query = request.query
        numResults = request.maxResults
        includeDomains = request.includeDomains.isEmpty ? nil : request.includeDomains
        excludeDomains = request.excludeDomains.isEmpty ? nil : request.excludeDomains
        contents = ExaContents()
        startPublishedDate = request.recency.map { ISO8601DateFormatter().string(from: $0.startDate) }
    }

    private enum CodingKeys: String, CodingKey {
        case query
        case numResults
        case includeDomains
        case excludeDomains
        case contents
        case startPublishedDate
    }
}

private struct ExaContents: Encodable {
    let highlights = true
}

private struct ExaResponse: Decodable {
    let results: [ExaResult]
}

private struct ExaResult: Decodable {
    let title: String
    let url: String
    let author: String?
    let publishedDate: String?
    let text: String?
    let highlights: [String]?
}

private extension WebSearchRecency {
    var startDate: Date {
        let calendar = Calendar(identifier: .gregorian)
        switch self {
        case .day: return calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month: return calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .year: return calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        }
    }
}

private func searchURL(_ baseURL: URL) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          components.scheme == "https",
          components.host != nil
    else {
        throw WebSearchError.invalidBaseURL
    }

    if !components.path.hasSuffix("/search") {
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/search"
    }
    guard let url = components.url else {
        throw WebSearchError.invalidBaseURL
    }
    return url
}

private func validate(_ response: WebSearchHTTPResponse) throws {
    guard (200..<300).contains(response.statusCode) else {
        throw WebSearchError.httpStatus(response.statusCode)
    }
}

private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw WebSearchError.invalidResponse
    }
}
