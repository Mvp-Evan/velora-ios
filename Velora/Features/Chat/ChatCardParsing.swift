import Foundation

/// Parse IM card payloads for listing / order / image (DES-v1.3-11-02 §5.6).
enum ChatCardParsing {
    static func listing(from message: Message) -> ChatListingCardPayload? {
        if let payload = message.payload, let card = listing(from: payload) { return card }
        return decode(ChatListingCardPayload.self, content: message.content)
    }

    static func order(from message: Message) -> ChatOrderCardPayload? {
        if let payload = message.payload, let card = order(from: payload) { return card }
        return decode(ChatOrderCardPayload.self, content: message.content)
    }

    static func image(from message: Message) -> ChatImagePayload? {
        if let payload = message.payload {
            if let url = string(payload["url"]?.value) ?? string(payload["image_url"]?.value), !url.isEmpty {
                return ChatImagePayload(
                    url: url,
                    width: intValue(payload["width"]?.value),
                    height: intValue(payload["height"]?.value),
                    sha256: string(payload["sha256"]?.value)
                )
            }
        }
        if !message.content.isEmpty {
            return ChatImagePayload(url: message.content)
        }
        return nil
    }

    static func listing(from payload: [String: AnyCodable]) -> ChatListingCardPayload? {
        let id = int64(payload["listing_id"]?.value)
            ?? int64(payload["listingId"]?.value)
            ?? int64(payload["lot_id"]?.value)
            ?? int64(payload["lotId"]?.value)
        guard let id else { return nil }
        let title = string(payload["title"]?.value) ?? ChatCopy.listingCardTitle
        let price = int64(payload["price"]?.value) ?? 0
        return ChatListingCardPayload(
            listingId: id,
            title: title,
            cover: string(payload["cover"]?.value),
            price: price,
            status: string(payload["status"]?.value) ?? string(payload["status_snapshot"]?.value)
        )
    }

    static func order(from payload: [String: AnyCodable]) -> ChatOrderCardPayload? {
        let id = int64(payload["order_id"]?.value) ?? int64(payload["orderId"]?.value)
        guard let id else { return nil }
        return ChatOrderCardPayload(
            orderId: id,
            orderNo: string(payload["order_no"]?.value) ?? string(payload["orderNo"]?.value),
            amount: int64(payload["amount"]?.value) ?? 0,
            status: string(payload["status"]?.value),
            title: string(payload["title"]?.value)
                ?? string(payload["listing_title"]?.value)
                ?? string(payload["listingTitle"]?.value)
        )
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, content: String) -> T? {
        guard let data = content.data(using: .utf8) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(T.self, from: data)
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

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}
