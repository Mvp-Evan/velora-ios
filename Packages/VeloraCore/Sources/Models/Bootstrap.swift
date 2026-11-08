import Foundation

/// Shared bootstrap shape for SPM consumers (mirrors `Velora/Models/Bootstrap.swift`).
public struct BootstrapNavTab: Decodable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let icon: String?

    public init(key: String, title: String, icon: String? = nil) {
        self.key = key
        self.title = title
        self.icon = icon
    }
}

public struct BootstrapNavSchema: Decodable, Equatable, Sendable {
    public let version: Int
    public let tabs: [BootstrapNavTab]
    public let meBuyerEntries: [BootstrapMeEntry]
    public let meSellerEntries: [BootstrapMeEntry]

    enum CodingKeys: String, CodingKey {
        case version, tabs, meBuyerEntries, meSellerEntries
    }

    public init(
        version: Int,
        tabs: [BootstrapNavTab],
        meBuyerEntries: [BootstrapMeEntry] = [],
        meSellerEntries: [BootstrapMeEntry] = []
    ) {
        self.version = version
        self.tabs = tabs
        self.meBuyerEntries = meBuyerEntries
        self.meSellerEntries = meSellerEntries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = Self.decodeVersion(from: c)
        tabs = try c.decodeIfPresent([BootstrapNavTab].self, forKey: .tabs) ?? []
        meBuyerEntries = try c.decodeIfPresent([BootstrapMeEntry].self, forKey: .meBuyerEntries) ?? []
        meSellerEntries = try c.decodeIfPresent([BootstrapMeEntry].self, forKey: .meSellerEntries) ?? []
    }

    /// Accepts Int (`13`) or version strings like `"v13"` / `"13"`.
    private static func decodeVersion(from c: KeyedDecodingContainer<CodingKeys>) -> Int {
        if let v = try? c.decode(Int.self, forKey: .version) { return v }
        if let s = try? c.decode(String.self, forKey: .version) {
            let digits = s.filter(\.isNumber)
            if let n = Int(digits), !digits.isEmpty { return n }
        }
        return 1
    }
}

public struct BootstrapMeEntry: Decodable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let icon: String?
    public let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case key, title, icon, enabled
    }

    public init(key: String, title: String, icon: String? = nil, enabled: Bool = true) {
        self.key = key
        self.title = title
        self.icon = icon
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public struct BootstrapPublishAction: Decodable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let enabled: Bool
    public let requiresCapability: String?

    enum CodingKeys: String, CodingKey {
        case key, title, enabled, requiresCapability
    }

    public init(key: String, title: String, enabled: Bool, requiresCapability: String? = nil) {
        self.key = key
        self.title = title
        self.enabled = enabled
        self.requiresCapability = requiresCapability
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        requiresCapability = try c.decodeIfPresent(String.self, forKey: .requiresCapability)
    }
}

public struct BootstrapCapabilities: Decodable, Equatable, Sendable {
    public var canFixed: Bool
    public var canAuction: Bool
    public var canBatchList: Bool
    public var canInvoiceService: Bool
    public var canSession: Bool
    public var canPromote: Bool
    public var canSpotRelease: Bool
    public var canLottery: Bool
    public var canPresale: Bool
    public var canSpecialNo: Bool
    public var canStore: Bool
    public var canVip: Bool

    enum CodingKeys: String, CodingKey {
        case canFixed, canAuction, canBatchList, canInvoiceService, canSession, canPromote
        case canSpotRelease, canLottery, canPresale, canSpecialNo, canStore, canVip
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canFixed = try c.decodeIfPresent(Bool.self, forKey: .canFixed) ?? false
        canAuction = try c.decodeIfPresent(Bool.self, forKey: .canAuction) ?? false
        canBatchList = try c.decodeIfPresent(Bool.self, forKey: .canBatchList) ?? false
        canInvoiceService = try c.decodeIfPresent(Bool.self, forKey: .canInvoiceService) ?? false
        canSession = try c.decodeIfPresent(Bool.self, forKey: .canSession) ?? false
        canPromote = try c.decodeIfPresent(Bool.self, forKey: .canPromote) ?? false
        canSpotRelease = try c.decodeIfPresent(Bool.self, forKey: .canSpotRelease) ?? false
        canLottery = try c.decodeIfPresent(Bool.self, forKey: .canLottery) ?? false
        canPresale = try c.decodeIfPresent(Bool.self, forKey: .canPresale) ?? false
        canSpecialNo = try c.decodeIfPresent(Bool.self, forKey: .canSpecialNo) ?? false
        canStore = try c.decodeIfPresent(Bool.self, forKey: .canStore) ?? false
        canVip = try c.decodeIfPresent(Bool.self, forKey: .canVip) ?? false
    }
}

public struct BootstrapMeProfile: Decodable, Equatable, Sendable {
    public let status: String?
    public let realNameStatus: String?
    public let creditScore: Int
    public let sellerType: String?

    enum CodingKeys: String, CodingKey {
        case status, realNameStatus, creditScore, sellerType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        realNameStatus = try c.decodeIfPresent(String.self, forKey: .realNameStatus)
        creditScore = try c.decodeIfPresent(Int.self, forKey: .creditScore) ?? 0
        sellerType = try c.decodeIfPresent(String.self, forKey: .sellerType)
    }
}

public struct BootstrapSellerProfile: Decodable, Equatable, Sendable {
    public let sellerType: String
    public let capabilities: BootstrapCapabilities
    public let onboardingStatus: String?
    public let badge: String?
    /// DES-v1.3-05-01 — drives buyer-visible 金牌代拍 vs 观察期.
    public let assessmentLevel: String?
}

/// `GET /me/bootstrap` data object (DES-v1.3-00-02).
public struct MeBootstrapDTO: Decodable, Equatable, Sendable {
    public let navSchema: BootstrapNavSchema
    public let publishActions: [BootstrapPublishAction]
    public let me: BootstrapMeProfile?
    public let seller: BootstrapSellerProfile?
    public let flags: [String: Bool]
    public let serverTime: Int64

    enum CodingKeys: String, CodingKey {
        case navSchema, nav, publishActions, me, seller, flags, serverTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let schema = try c.decodeIfPresent(BootstrapNavSchema.self, forKey: .navSchema) {
            navSchema = schema
        } else if let schema = try c.decodeIfPresent(BootstrapNavSchema.self, forKey: .nav) {
            navSchema = schema
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.navSchema,
                .init(codingPath: c.codingPath, debugDescription: "missing nav_schema / nav")
            )
        }
        publishActions = try c.decodeIfPresent([BootstrapPublishAction].self, forKey: .publishActions) ?? []
        me = try c.decodeIfPresent(BootstrapMeProfile.self, forKey: .me)
        seller = try c.decodeIfPresent(BootstrapSellerProfile.self, forKey: .seller)
        flags = try c.decodeIfPresent([String: Bool].self, forKey: .flags) ?? [:]
        serverTime = Self.decodeServerTimeMs(from: c, forKey: .serverTime)
    }

    /// Accepts unix-ms Int64 or ISO8601 / RFC3339 string (Go `time.Time`).
    private static func decodeServerTimeMs(
        from c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int64 {
        if let ms = try? c.decode(Int64.self, forKey: key) { return ms }
        if let s = try? c.decode(String.self, forKey: key) {
            if let ms = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return ms
            }
            if let date = Self.parseISO8601Date(s) {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
        }
        return 0
    }

    private static func parseISO8601Date(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

public enum BootstrapTabKey: String, Sendable {
    case buy, community, publish, inbox, me, home, auctions

    public static func from(navKey: String) -> BootstrapTabKey? {
        switch navKey {
        case "buy": return .buy
        case "community": return .community
        case "publish": return .publish
        case "inbox", "messages": return .inbox
        case "me": return .me
        case "home": return .home
        case "auctions": return .auctions
        default: return nil
        }
    }
}
