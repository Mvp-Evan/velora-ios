import Foundation

// MARK: - Account five-state + restrictions (DES-v1.3-01-03 / ACC-08)

/// Primary account status (`users.status`).
public enum AccountStatus: String, Codable, Sendable, CaseIterable {
    case active
    case rateLimited = "rate_limited"
    case banPublish = "ban_publish"
    case banBid = "ban_bid"
    case frozen
    case pendingDeletion = "pending_deletion"

    public var isRestrictionState: Bool {
        switch self {
        case .rateLimited, .banPublish, .banBid, .frozen: return true
        default: return false
        }
    }
}

/// `GET /me` `restrictions[]` item (DES §5.7 / §6).
public struct AccountRestrictionItem: Codable, Equatable, Sendable, Identifiable {
    public let type: String
    public let endsAt: Date?
    public let publicReason: String?

    public var id: String {
        let end = endsAt.map { String($0.timeIntervalSince1970) } ?? "open"
        return "\(type)-\(end)"
    }

    public var status: AccountStatus? { AccountStatus(rawValue: type) }

    public init(type: String, endsAt: Date? = nil, publicReason: String? = nil) {
        self.type = type
        self.endsAt = endsAt
        self.publicReason = publicReason
    }
}

/// Stable restriction / blacklist error codes (DES §6). Overlaps with auth for `account_frozen`.
public enum RestrictionErrorCode: String, Codable, Sendable, CaseIterable {
    case accountFrozen = "account_frozen"
    case bidForbidden = "bid_forbidden"
    case publishForbidden = "publish_forbidden"
    case withdrawForbidden = "withdraw_forbidden"
    case idNoBlocked = "id_no_blocked"
    case deviceBlocked = "device_blocked"
    case addressBlocked = "address_blocked"
    case addressTooCoarse = "address_too_coarse"
    case creditTooLow = "credit_too_low"
    case missingReason = "missing_reason"

    public var clearsLocalSession: Bool {
        self == .accountFrozen
    }

    public var fallbackMessage: String {
        switch self {
        case .accountFrozen: return "账号已冻结，请联系客服"
        case .bidForbidden: return "账号已被限制竞拍"
        case .publishForbidden: return "账号已被限制发布"
        case .withdrawForbidden: return "账号已被限制提现"
        case .idNoBlocked: return "该身份无法用于认证，请联系客服"
        case .deviceBlocked: return "当前设备暂无法完成该操作"
        case .addressBlocked: return "收货地址暂无法使用，请更换后重试"
        case .addressTooCoarse: return "地址信息不完整，请补充门牌后重试"
        case .creditTooLow: return "信用分过低，暂无法完成该操作"
        case .missingReason: return "请填写原因"
        }
    }
}

/// Resolved capability flags from status + restriction rows (union of active flags).
public struct AccountAccessFlags: Equatable, Sendable {
    public let status: AccountStatus
    public let restrictions: [AccountRestrictionItem]
    public let isFrozen: Bool
    public let isBanBid: Bool
    public let isBanPublish: Bool
    public let isRateLimited: Bool

    public var canBid: Bool { !isFrozen && !isBanBid }
    public var canPublish: Bool { !isFrozen && !isBanPublish }
    /// Deposit / lottery entry should stay hidden when bidding is forbidden.
    public var showsDepositEntry: Bool { canBid }

    public var banBidEndsAt: Date? {
        restrictions.first(where: { $0.type == AccountStatus.banBid.rawValue })?.endsAt
    }

    public var banBidPublicReason: String? {
        restrictions.first(where: { $0.type == AccountStatus.banBid.rawValue })?.publicReason
    }

    public var frozenPublicReason: String? {
        restrictions.first(where: { $0.type == AccountStatus.frozen.rawValue })?.publicReason
    }

    public init(
        status: AccountStatus,
        restrictions: [AccountRestrictionItem] = [],
        isFrozen: Bool,
        isBanBid: Bool,
        isBanPublish: Bool,
        isRateLimited: Bool
    ) {
        self.status = status
        self.restrictions = restrictions
        self.isFrozen = isFrozen
        self.isBanBid = isBanBid
        self.isBanPublish = isBanPublish
        self.isRateLimited = isRateLimited
    }

    /// Middleware-style union: status column plus unexpired restriction rows.
    public static func resolve(status raw: String?, restrictions: [AccountRestrictionItem] = []) -> AccountAccessFlags {
        let parsed = AccountStatus(rawValue: raw ?? "") ?? .active
        let types = Set(restrictions.map(\.type))
        let frozen = parsed == .frozen || types.contains(AccountStatus.frozen.rawValue)
        let banBid = parsed == .banBid || types.contains(AccountStatus.banBid.rawValue)
        let banPublish = parsed == .banPublish || types.contains(AccountStatus.banPublish.rawValue)
        let rateLimited = parsed == .rateLimited || types.contains(AccountStatus.rateLimited.rawValue)
        return AccountAccessFlags(
            status: parsed,
            restrictions: restrictions,
            isFrozen: frozen,
            isBanBid: banBid,
            isBanPublish: banPublish,
            isRateLimited: rateLimited
        )
    }
}

/// Client presentation after `account_frozen` / WS `session_revoked` (DES §9).
public struct AccountGateNotice: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case frozen
        case sessionRevoked = "session_revoked"
    }

    public let kind: Kind
    public let message: String
    public let publicReason: String?

    public var id: String { "\(kind.rawValue)-\(message)" }

    public init(kind: Kind, message: String, publicReason: String? = nil) {
        self.kind = kind
        self.message = message
        self.publicReason = publicReason
    }

    public var title: String {
        switch kind {
        case .frozen: return "账号已冻结"
        case .sessionRevoked: return "登录已失效"
        }
    }

    public var detailText: String {
        let reason = publicReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reason.isEmpty { return reason }
        return message
    }
}
