import Foundation

public struct Envelope<T: Decodable>: Decodable {
    public let data: T?
    public let error: APIErrorBody?
}

public struct APIErrorBody: Decodable, Error, Sendable {
    public let code: String
    public let message: String
}

public struct Empty: Decodable, Sendable {}
