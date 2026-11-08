import Foundation

/// Build `OfferCard` from IM message payload / content JSON (DES-v1.3-04-02 §5.6).
enum OfferCardParsing {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dt = withFrac.date(from: s) { return dt }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let dt = plain.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static func from(message: Message) -> OfferCard? {
        if let payload = message.payload, let card = from(payload: payload) {
            return card
        }
        if let data = message.content.data(using: .utf8),
           let card = try? decoder.decode(OfferCard.self, from: data) {
            return card
        }
        return nil
    }

    static func from(payload: [String: AnyCodable]) -> OfferCard? {
        var dict: [String: Any] = [:]
        for (k, v) in payload {
            dict[k] = unwrap(v.value)
        }
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let card = try? decoder.decode(OfferCard.self, from: data) else {
            // Minimal fallback when only offer_id is present.
            if let id = int64(payload["offer_id"]?.value) ?? int64(payload["offerId"]?.value) {
                let list = int64(payload["list_price"]?.value) ?? int64(payload["listPrice"]?.value) ?? 0
                let offer = int64(payload["offer_price"]?.value) ?? int64(payload["offerPrice"]?.value) ?? 0
                let round = intValue(payload["round"]?.value) ?? 1
                let expires = date(payload["expires_at"]?.value) ?? date(payload["expiresAt"]?.value) ?? Date().addingTimeInterval(86400)
                return OfferCard(
                    offerId: id,
                    listingId: int64(payload["listing_id"]?.value) ?? int64(payload["listingId"]?.value),
                    cover: payload["cover"]?.value as? String,
                    title: payload["title"]?.value as? String,
                    listPrice: list,
                    offerPrice: offer,
                    expiresAt: expires,
                    round: round,
                    status: (payload["status"]?.value as? String).flatMap(OfferStatus.init(rawValue:)),
                    actions: []
                )
            }
            return nil
        }
        return card
    }

    private static func unwrap(_ value: Any) -> Any {
        if let a = value as? AnyCodable { return unwrap(a.value) }
        if let arr = value as? [Any] { return arr.map(unwrap) }
        if let dict = value as? [String: Any] {
            return dict.mapValues(unwrap)
        }
        return value
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? Double { return Int64(v) }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let dt = withFrac.date(from: s) { return dt }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
