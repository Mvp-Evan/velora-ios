import Foundation

// MARK: - Account five-state + restrictions (DES-v1.3-01-03) — app mirror of VeloraCore

enum AccountStatus: String, CaseIterable {
    case active
    case rateLimited = "rate_limited"
    case banPublish = "ban_publish"
    case banBid = "ban_bid"
    case frozen
    case pendingDeletion = "pending_deletion"

    var isRestrictionState: Bool {
        switch self {
        case .rateLimited, .banPublish, .banBid, .frozen: return true
        default: return false
        }
    }
}

struct AccountRestrictionItem: Codable, Equatable, Identifiable, Hashable {
    let type: String
    let endsAt: Date?
    let publicReason: String?

    var id: String {
        let end = endsAt.map { String($0.timeIntervalSince1970) } ?? "open"
        return "\(type)-\(end)"
    }

    var status: AccountStatus? { AccountStatus(rawValue: type) }
}

enum RestrictionErrorCode: String {
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

    var clearsLocalSession: Bool { self == .accountFrozen }

    var fallbackMessage: String {
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

extension APIError {
    var restrictionCode: RestrictionErrorCode? { RestrictionErrorCode(rawValue: code) }

    var restrictionMessage: String {
        if let r = restrictionCode { return message.isEmpty ? r.fallbackMessage : message }
        return message
    }
}

struct AccountAccessFlags: Equatable {
    let status: AccountStatus
    let restrictions: [AccountRestrictionItem]
    let isFrozen: Bool
    let isBanBid: Bool
    let isBanPublish: Bool
    let isRateLimited: Bool

    var canBid: Bool { !isFrozen && !isBanBid }
    var canPublish: Bool { !isFrozen && !isBanPublish }
    var showsDepositEntry: Bool { canBid }

    var banBidEndsAt: Date? {
        restrictions.first(where: { $0.type == AccountStatus.banBid.rawValue })?.endsAt
    }

    var banBidPublicReason: String? {
        restrictions.first(where: { $0.type == AccountStatus.banBid.rawValue })?.publicReason
    }

    var frozenPublicReason: String? {
        restrictions.first(where: { $0.type == AccountStatus.frozen.rawValue })?.publicReason
    }

    static func resolve(status raw: String?, restrictions: [AccountRestrictionItem] = []) -> AccountAccessFlags {
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

struct AccountGateNotice: Equatable, Identifiable {
    enum Kind: String {
        case frozen
        case sessionRevoked = "session_revoked"
    }

    let kind: Kind
    let message: String
    let publicReason: String?

    init(kind: Kind, message: String, publicReason: String? = nil) {
        self.kind = kind
        self.message = message
        self.publicReason = publicReason
    }

    var id: String { "\(kind.rawValue)-\(message)" }

    var title: String {
        switch kind {
        case .frozen: return "账号已冻结"
        case .sessionRevoked: return "登录已失效"
        }
    }

    var detailText: String {
        let reason = publicReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reason.isEmpty { return reason }
        return message
    }
}
