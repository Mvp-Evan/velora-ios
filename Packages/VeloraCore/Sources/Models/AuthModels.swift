import Foundation

// MARK: - Auth error codes (DES-v1.3-01-01 §6)

/// Stable auth / session error codes from the API and WS kick path.
public enum AuthErrorCode: String, Codable, Sendable, CaseIterable {
    case smsTooFrequent = "sms_too_frequent"
    case smsDailyLimit = "sms_daily_limit"
    case smsLocked = "sms_locked"
    case smsUnavailable = "sms_unavailable"
    case invalidSmsCode = "invalid_sms_code"
    case inviteRequired = "invite_required"
    case inviteInvalid = "invite_invalid"
    case accountFrozen = "account_frozen"
    case accountBlocked = "account_blocked"
    case needBindPhone = "need_bind_phone"
    case bindTicketExpired = "bind_ticket_expired"
    case oauthTaken = "oauth_taken"
    case deletionBlocked = "deletion_blocked"
    case unauthorized = "unauthorized"
    case missingIdempotencyKey = "missing_idempotency_key"
    case tooManyRequests = "too_many_requests"

    /// WebSocket kick event type (not an HTTP error body code).
    public static let sessionRevokedEvent = "session_revoked"

    public var clearsLocalSession: Bool {
        switch self {
        case .unauthorized, .accountFrozen, .accountBlocked:
            return true
        default:
            return false
        }
    }
}

// MARK: - SMS / Login DTOs

public struct SendSmsResponse: Decodable, Equatable, Sendable {
    public let retryAfter: Int?
    public let sent: Bool?
    /// Legacy non-production field; production responses must omit any code.
    public let devCode: String?

    public init(retryAfter: Int? = nil, sent: Bool? = nil, devCode: String? = nil) {
        self.retryAfter = retryAfter
        self.sent = sent
        self.devCode = devCode
    }

    public var cooldownSeconds: Int { max(0, retryAfter ?? 60) }
}

public struct LoginRequestBody: Encodable, Equatable, Sendable {
    public let phone: String
    public let code: String
    public let inviteCode: String?
    public let deviceId: String?

    public init(phone: String, code: String, inviteCode: String? = nil, deviceId: String? = nil) {
        self.phone = phone
        self.code = code
        self.inviteCode = inviteCode
        self.deviceId = deviceId
    }
}

public struct AuthDeletionHint: Decodable, Equatable, Sendable {
    public let status: String
    public let executeAt: Date?

    public init(status: String, executeAt: Date? = nil) {
        self.status = status
        self.executeAt = executeAt
    }

    public var isPendingDeletion: Bool { status == "pending_deletion" }
}

public struct AuthUserSnapshot: Decodable, Equatable, Sendable {
    public let id: Int64
    public let nickname: String
    public let status: String?
    public let realNameStatus: String?

    public init(id: Int64, nickname: String, status: String? = nil, realNameStatus: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.status = status
        self.realNameStatus = realNameStatus
    }

    public var isPendingDeletion: Bool { status == "pending_deletion" }
}

/// Login / refresh token pair shape used by decoding tests (subset of full app `TokenPair`).
public struct AuthTokenPair: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?
    public let user: AuthUserSnapshot?
    public let isNew: Bool
    public let deletion: AuthDeletionHint?

    enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresAt, user, isNew, deletion
    }

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date? = nil,
        user: AuthUserSnapshot? = nil,
        isNew: Bool = false,
        deletion: AuthDeletionHint? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
        self.isNew = isNew
        self.deletion = deletion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        user = try c.decodeIfPresent(AuthUserSnapshot.self, forKey: .user)
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        deletion = try c.decodeIfPresent(AuthDeletionHint.self, forKey: .deletion)
    }
}

// MARK: - Sessions (GET /me/sessions)

public struct DeviceSession: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let deviceName: String?
    public let ipMasked: String?
    public let lastSeen: Date?
    public let current: Bool

    enum CodingKeys: String, CodingKey {
        case id, deviceName, ipMasked, lastSeen, current
    }

    public init(
        id: String,
        deviceName: String? = nil,
        ipMasked: String? = nil,
        lastSeen: Date? = nil,
        current: Bool = false
    ) {
        self.id = id
        self.deviceName = deviceName
        self.ipMasked = ipMasked
        self.lastSeen = lastSeen
        self.current = current
    }

    public init(from decoder: Decoder) throws {
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

public struct SessionsListResponse: Decodable, Equatable, Sendable {
    public let items: [DeviceSession]

    enum CodingKeys: String, CodingKey {
        case items, sessions
    }

    public init(items: [DeviceSession]) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([DeviceSession].self) {
            items = arr
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([DeviceSession].self, forKey: .items) {
            self.items = items
        } else if let sessions = try c.decodeIfPresent([DeviceSession].self, forKey: .sessions) {
            items = sessions
        } else {
            items = []
        }
    }
}

// MARK: - Account deletion (ACC-07)

public struct DeletionBlocker: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { code ?? message }
    public let code: String?
    public let message: String
    public let ref: String?
    /// DES-v1.3-12-01 ME-07 — optional count / hint on precheck blockers.
    public let count: Int?
    public let hint: String?

    public init(
        code: String? = nil,
        message: String,
        ref: String? = nil,
        count: Int? = nil,
        hint: String? = nil
    ) {
        self.code = code
        self.message = message
        self.ref = ref
        self.count = count
        self.hint = hint
    }

    enum CodingKeys: String, CodingKey {
        case code, message, ref, count, hint
    }

    public init(from decoder: Decoder) throws {
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

public struct DeletionStatusResponse: Decodable, Equatable, Sendable {
    public let status: String
    public let executeAt: Date?
    public let blockers: [DeletionBlocker]

    enum CodingKeys: String, CodingKey {
        case status, executeAt, blockers
    }

    public init(status: String, executeAt: Date? = nil, blockers: [DeletionBlocker] = []) {
        self.status = status
        self.executeAt = executeAt
        self.blockers = blockers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "none"
        executeAt = try c.decodeIfPresent(Date.self, forKey: .executeAt)
        blockers = try c.decodeIfPresent([DeletionBlocker].self, forKey: .blockers) ?? []
    }

    public var isPending: Bool { status == "pending_deletion" }
    public var coolOffDaysHint: Int { 15 }
}

public struct DeletionPrecheckResponse: Decodable, Equatable, Sendable {
    public let blockers: [DeletionBlocker]
    /// DES-v1.3-12-01 — server `eligible`; falls back to empty blockers.
    public let eligible: Bool

    public var canDelete: Bool { eligible && blockers.isEmpty }

    public init(blockers: [DeletionBlocker] = [], eligible: Bool? = nil) {
        self.blockers = blockers
        self.eligible = eligible ?? blockers.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case blockers, eligible, canDelete
    }

    public init(from decoder: Decoder) throws {
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
