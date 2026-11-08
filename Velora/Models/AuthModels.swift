import Foundation

// MARK: - Auth error codes (DES-v1.3-01-01) — mirrored from VeloraCore

enum AuthErrorCode: String {
    case smsTooFrequent = "sms_too_frequent"
    case smsDailyLimit = "sms_daily_limit"
    case smsLocked = "sms_locked"
    case smsUnavailable = "sms_unavailable"
    case invalidSmsCode = "invalid_sms_code"
    case inviteRequired = "invite_required"
    case inviteInvalid = "invite_invalid"
    case accountFrozen = "account_frozen"
    case accountBlocked = "account_blocked"
    case deletionBlocked = "deletion_blocked"
    case unauthorized = "unauthorized"
    case tooManyRequests = "too_many_requests"

    static let sessionRevokedEvent = "session_revoked"

    var clearsLocalSession: Bool {
        switch self {
        case .unauthorized, .accountFrozen, .accountBlocked: return true
        default: return false
        }
    }
}

extension APIError {
    var authCode: AuthErrorCode? { AuthErrorCode(rawValue: code) }
}

// MARK: - SMS / sessions / deletion DTOs

struct SendSmsResult: Decodable {
    let retryAfter: Int?
    let sent: Bool?
    let devCode: String?

    var cooldownSeconds: Int { max(0, retryAfter ?? 60) }
}

struct AuthDeletionHint: Codable, Hashable {
    let status: String
    let executeAt: Date?

    var isPendingDeletion: Bool { status == "pending_deletion" }
}

struct DeviceSession: Decodable, Identifiable, Hashable {
    let id: String
    let deviceName: String?
    let ipMasked: String?
    let lastSeen: Date?
    let current: Bool

    enum CodingKeys: String, CodingKey {
        case id, deviceName, ipMasked, lastSeen, current
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .id) {
            id = String(i)
        } else if let s = try c.decodeIfPresent(String.self, forKey: .id), !s.isEmpty {
            id = s
        } else {
            id = UUID().uuidString
        }
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
        ipMasked = try c.decodeIfPresent(String.self, forKey: .ipMasked)
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
}

struct SessionsListResponse: Decodable {
    let items: [DeviceSession]

    enum CodingKeys: String, CodingKey { case items, sessions }

    init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([DeviceSession].self) {
            items = arr
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([DeviceSession].self, forKey: .items) {
            self.items = items
        } else {
            items = try c.decodeIfPresent([DeviceSession].self, forKey: .sessions) ?? []
        }
    }
}

struct DeletionBlocker: Decodable, Identifiable, Hashable {
    var id: String { code ?? message }
    let code: String?
    let message: String
    let ref: String?
    /// DES-v1.3-12-01 ME-07 — optional count / hint on precheck blockers.
    let count: Int?
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case code, message, ref, count, hint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        ref = try c.decodeIfPresent(String.self, forKey: .ref)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        if let message = try c.decodeIfPresent(String.self, forKey: .message), !message.isEmpty {
            self.message = message
        } else if let hint, !hint.isEmpty {
            self.message = hint
        } else {
            self.message = "暂时无法注销"
        }
    }
}

struct DeletionStatusResponse: Decodable {
    let status: String
    let executeAt: Date?
    let blockers: [DeletionBlocker]

    enum CodingKeys: String, CodingKey { case status, executeAt, blockers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "none"
        executeAt = try c.decodeIfPresent(Date.self, forKey: .executeAt)
        blockers = try c.decodeIfPresent([DeletionBlocker].self, forKey: .blockers) ?? []
    }

    var isPending: Bool { status == "pending_deletion" }
}

struct DeletionPrecheckResponse: Decodable {
    let blockers: [DeletionBlocker]
    /// DES-v1.3-12-01 — server `eligible`; falls back to empty blockers.
    let eligible: Bool

    var canDelete: Bool { eligible && blockers.isEmpty }

    enum CodingKeys: String, CodingKey { case blockers, eligible, canDelete }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockers = try c.decodeIfPresent([DeletionBlocker].self, forKey: .blockers) ?? []
        if let eligible = try c.decodeIfPresent(Bool.self, forKey: .eligible) {
            self.eligible = eligible
        } else if let canDelete = try c.decodeIfPresent(Bool.self, forKey: .canDelete) {
            self.eligible = canDelete
        } else {
            self.eligible = blockers.isEmpty
        }
    }
}
