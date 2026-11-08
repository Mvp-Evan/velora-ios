import Foundation

/// Public app bootstrap (`GET /api/v1/bootstrap`) — flags/gates/min_version; distinct from `/me/bootstrap`.
public struct PublicAppBootstrap: Decodable, Sendable {
    public let serverTime: Date
    public let minIOS: String
    public let minAndroid: String
    public let minVersion: String
    public let flags: [String: Bool]
    public let gates: [String: Bool]
    public let protocolLatest: [String: String]
    public let licensesURL: String
    public let sampling: TelemetrySamplingHints

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case minIOS = "min_ios"
        case minAndroid = "min_android"
        case minVersion = "min_version"
        case flags, gates
        case protocolLatest = "protocol_latest"
        case licensesURL = "licenses_url"
        case sampling
    }
}

public struct TelemetrySamplingHints: Decodable, Sendable {
    public let viewItemRate: Double
    public let bidRate: Double
    public let payRate: Double
    public let auctionNightViewItemRate: Double

    enum CodingKeys: String, CodingKey {
        case viewItemRate = "view_item_rate"
        case bidRate = "bid_rate"
        case payRate = "pay_rate"
        case auctionNightViewItemRate = "auction_night_view_item_rate"
    }
}

public struct TelemetryEventPayload: Encodable, Sendable {
    public let eventID: String
    public let name: String
    public let feature: String?
    public let props: [String: JSONValue]
    public let reviewer: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case name, feature, props, reviewer
    }

    public init(eventID: String, name: String, feature: String? = nil, props: [String: JSONValue] = [:], reviewer: Bool = false) {
        self.eventID = eventID
        self.name = name
        self.feature = feature
        self.props = props
        self.reviewer = reviewer
    }
}

/// Lightweight batch telemetry stub (DES-v1.3-14-03 §5.2); flush ~10s from app layer.
public final class TelemetryClient: @unchecked Sendable {
    private let post: (Data) async throws -> Void
    private var buffer: [TelemetryEventPayload] = []
    private let maxBuffer = 200
    private let lock = NSLock()

    public init(post: @escaping (Data) async throws -> Void) {
        self.post = post
    }

    public func track(_ event: TelemetryEventPayload) {
        lock.lock()
        defer { lock.unlock() }
        if buffer.count >= maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer + 1)
        }
        buffer.append(event)
    }

    public func flush(sentAt: Date = Date()) async throws {
        lock.lock()
        let batch = buffer
        buffer = []
        lock.unlock()
        guard !batch.isEmpty else { return }
        let body: [String: Any] = [
            "sent_at": ISO8601DateFormatter().string(from: sentAt),
            "events": batch.map { ev in
                var o: [String: Any] = ["event_id": ev.eventID, "name": ev.name, "reviewer": ev.reviewer]
                if let f = ev.feature { o["feature"] = f }
                if !ev.props.isEmpty { o["props"] = ev.props.mapValues { $0.encode() } }
                return o
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        try await post(data)
    }
}

/// Minimal JSON value for telemetry props (no PII types enforced client-side; server strips).
public enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public func encode() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        }
    }
}
