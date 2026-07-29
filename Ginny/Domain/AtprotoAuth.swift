import Foundation

enum AtprotoAuthState: Equatable, Sendable {
    case signedOut
    case signedIn(AtprotoAccount)
}

struct AtprotoAccount: Codable, Equatable, Sendable {
    let handle: String
    let did: String
    let pdsURL: String
    let serviceEndpoint: URL
}

enum AtprotoAuthError: LocalizedError, Equatable, Sendable {
    case invalidHandle
    case invalidAppPassword
    case invalidPDSURL
    case identityResolutionFailed
    case identityVerificationFailed
    case missingSession
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidHandle:
            "Enter an atproto handle or DID."
        case .invalidAppPassword:
            "Enter an app password."
        case .invalidPDSURL:
            "Enter a valid HTTPS PDS URL."
        case .identityResolutionFailed:
            "Could not resolve that atproto identity. Check the handle and try again."
        case .identityVerificationFailed:
            "The handle and DID document did not agree, so sign-in was stopped."
        case .missingSession:
            "The atproto server did not return a session."
        case .requestFailed:
            "The atproto request failed. Check your connection and try again."
        }
    }
}
