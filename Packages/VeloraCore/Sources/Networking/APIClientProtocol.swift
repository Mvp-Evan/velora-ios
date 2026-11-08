import Foundation

public enum HTTPMethod: String, Sendable { case GET, POST, PUT, PATCH, DELETE }

/// Surface area of `Velora/Core/Network/APIClient.swift` for dependency injection and tests.
@available(iOS 17.0, macOS 14.0, *)
public protocol APIClientProtocol: Actor {
    nonisolated func idempotencyKey() -> String
}
