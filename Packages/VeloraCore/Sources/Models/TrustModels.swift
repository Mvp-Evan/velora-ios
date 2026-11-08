import Foundation

// MARK: - Trust / KYC / seller onboarding (DES-v1.3-01-02)

/// Stable KYC / seller / invite error codes from the API.
public enum TrustErrorCode: String, Codable, Sendable, CaseIterable {
    case idNoTaken = "id_no_taken"
    case nationalNidTaken = "national_nid_taken"
    case idNoBlocked = "id_no_blocked"
    case userCancelled = "user_cancelled"
    case appNotInstalled = "app_not_installed"
    case kycCodeExpired = "kyc_code_expired"
    case channelRejected = "channel_rejected"
    case timeout = "timeout"
    case vendorUnavailable = "vendor_unavailable"
    case kycDailyLimit = "kyc_daily_limit"
    case stepRealNameRequired = "step_real_name_required"
    case stepProtocolRequired = "step_protocol_required"
    case depositNotFrozen = "deposit_not_frozen"
    case depositFailed = "deposit_failed"
    case protocolStale = "protocol_stale"
    case inviteInvalid = "invite_invalid"
    case inviteTypeMismatch = "invite_type_mismatch"
    case inviteQuota = "invite_quota"
    case inviteRequired = "invite_required"
    case principalMismatch = "principal_mismatch"
    case subMerchantFailed = "sub_merchant_failed"
    case applicationRejected = "application_rejected"
    case sellerOnboarding = "seller_onboarding"
    case realNameRequired = "real_name_required"

    /// User-facing next-step copy (DES §5.5). Prefer server `message` when present.
    public var fallbackMessage: String {
        switch self {
        case .userCancelled: return "已取消认证，可改用其他方式"
        case .appNotInstalled: return "未检测到该 App，请前往安装后重试"
        case .kycCodeExpired: return "认证凭证已失效，请重新发起"
        case .timeout: return "认证超时，请重试或换通道"
        case .vendorUnavailable: return "认证服务繁忙，请换支付宝 / 微信 / 国家网络身份认证"
        case .idNoTaken: return "该证件已绑定其他账号，请联系客服"
        case .nationalNidTaken: return "该网络身份已绑定其他账号，请联系客服"
        case .idNoBlocked: return "该身份无法用于认证，请联系客服"
        case .channelRejected: return "第三方未通过核身，请在该 App 内完成实名后再试"
        case .kycDailyLimit: return "今日认证次数已达上限，请明日再试"
        case .stepRealNameRequired: return "请先完成实名认证"
        case .stepProtocolRequired: return "请先签署卖家服务协议"
        case .depositNotFrozen: return "请先完成保证金冻结"
        case .depositFailed: return "保证金处理失败，请重试或联系客服"
        case .protocolStale: return "协议已更新，请重新签署"
        case .inviteInvalid: return "邀请码无效或已过期"
        case .inviteTypeMismatch: return "邀请码与申请身份不符"
        case .inviteQuota: return "邀请码名额已用尽"
        case .inviteRequired: return "新用户需填写邀请码"
        case .principalMismatch: return "主理人实名须与当前账号一致"
        case .subMerchantFailed: return "收款开通失败，可重提进件"
        case .applicationRejected: return "资质审核未通过"
        case .sellerOnboarding: return "请先完成卖家入驻"
        case .realNameRequired: return "请先完成实名认证"
        }
    }
}

public enum RealNameChannel: String, Codable, Sendable, CaseIterable {
    case alipay
    case wechat
    case nationalNid = "national_nid"

    public var title: String {
        switch self {
        case .alipay: return "支付宝认证"
        case .wechat: return "微信认证"
        case .nationalNid: return "国家网络身份认证"
        }
    }

    public var systemImage: String {
        switch self {
        case .alipay: return "yensign.circle"
        case .wechat: return "message"
        case .nationalNid: return "person.text.rectangle"
        }
    }

    /// Schemes used for `canOpenURL` probes (Info.plist must list them).
    public var probeSchemes: [String] {
        switch self {
        case .alipay: return ["alipay", "alipays"]
        case .wechat: return ["weixin", "weixinULAPI"]
        case .nationalNid: return ["idauth", "cyberidentity"]
        }
    }
}

public enum RealNameStatusValue: String, Codable, Sendable {
    case unverified
    case none
    case pendingJump = "pending_jump"
    case verifying
    case verified
    case failed
    case pending
    case rejected

    public var isVerified: Bool { self == .verified }

    public var displayLabel: String {
        switch self {
        case .verified: return "已实名"
        case .pendingJump, .verifying, .pending: return "认证中"
        case .failed, .rejected: return "认证失败"
        case .unverified, .none: return "未实名"
        }
    }
}

public struct RealNameJumpPayload: Decodable, Equatable, Sendable {
    public let url: String?
    public let appStoreUrl: String?
    public let downloadUrl: String?

    public init(url: String? = nil, appStoreUrl: String? = nil, downloadUrl: String? = nil) {
        self.url = url
        self.appStoreUrl = appStoreUrl
        self.downloadUrl = downloadUrl
    }

    public var openURL: URL? {
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    public var installURL: URL? {
        let raw = (appStoreUrl ?? downloadUrl)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

public struct RealNameSessionResponse: Decodable, Equatable, Sendable {
    public let sessionId: String?
    public let status: String?
    public let channel: String?
    public let jump: RealNameJumpPayload?
    public let failReason: String?
    public let nameMasked: String?
    public let idNoMasked: String?

    public init(
        sessionId: String? = nil,
        status: String? = nil,
        channel: String? = nil,
        jump: RealNameJumpPayload? = nil,
        failReason: String? = nil,
        nameMasked: String? = nil,
        idNoMasked: String? = nil
    ) {
        self.sessionId = sessionId
        self.status = status
        self.channel = channel
        self.jump = jump
        self.failReason = failReason
        self.nameMasked = nameMasked
        self.idNoMasked = idNoMasked
    }

    public var statusValue: RealNameStatusValue? {
        status.flatMap(RealNameStatusValue.init(rawValue:))
    }

    public var isAlreadyVerified: Bool { statusValue?.isVerified == true }
}

public struct RealNameStatusResponse: Decodable, Equatable, Sendable {
    public let status: String
    public let channel: String?
    public let failReason: String?
    public let nameMasked: String?
    public let idNoMasked: String?
    public let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status, channel, failReason, nameMasked, idNoMasked, sessionId
        case masked
    }

    public init(
        status: String,
        channel: String? = nil,
        failReason: String? = nil,
        nameMasked: String? = nil,
        idNoMasked: String? = nil,
        sessionId: String? = nil
    ) {
        self.status = status
        self.channel = channel
        self.failReason = failReason
        self.nameMasked = nameMasked
        self.idNoMasked = idNoMasked
        self.sessionId = sessionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? RealNameStatusValue.unverified.rawValue
        channel = try c.decodeIfPresent(String.self, forKey: .channel)
        failReason = try c.decodeIfPresent(String.self, forKey: .failReason)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        let flatName = try c.decodeIfPresent(String.self, forKey: .nameMasked)
        let flatId = try c.decodeIfPresent(String.self, forKey: .idNoMasked)
        if let nested = try c.decodeIfPresent([String: String].self, forKey: .masked) {
            nameMasked = nested["name"] ?? nested["name_masked"] ?? flatName
            idNoMasked = nested["id_no"] ?? nested["id_no_masked"] ?? flatId
        } else {
            nameMasked = flatName
            idNoMasked = flatId
        }
    }

    public var statusValue: RealNameStatusValue {
        RealNameStatusValue(rawValue: status) ?? .unverified
    }

    public var failCode: TrustErrorCode? {
        failReason.flatMap(TrustErrorCode.init(rawValue:))
    }
}

public struct RealNameCompleteRequest: Encodable, Equatable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct RealNameSessionCreateRequest: Encodable, Equatable, Sendable {
    public let channel: String

    public init(channel: RealNameChannel) {
        self.channel = channel.rawValue
    }

    public init(channel: String) {
        self.channel = channel
    }
}

// MARK: - Personal seller 4-step onboarding

public enum SellerOnboardingStepKey: String, Codable, Sendable, CaseIterable {
    case realName = "real_name"
    case protocolStep = "protocol"
    case deposit
    case subMerchant = "sub_merchant"

    public var title: String {
        switch self {
        case .realName: return "实名"
        case .protocolStep: return "协议"
        case .deposit: return "保证金"
        case .subMerchant: return "进件"
        }
    }

    public var detail: String {
        switch self {
        case .realName: return "完成实名认证"
        case .protocolStep: return "签署卖家服务协议"
        case .deposit: return "冻结个人卖家保证金"
        case .subMerchant: return "开通收款二级商户"
        }
    }
}

public enum SellerStepStatus: String, Codable, Sendable {
    case pending
    case done
    case failed
    case inProgress = "in_progress"
    case skippedDev = "skipped_dev"

    public var isComplete: Bool { self == .done || self == .skippedDev }
}

public struct SellerOnboardingStep: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { step }
    public let step: String
    public let status: String
    public let errorCode: String?
    public let refId: String?

    public init(step: String, status: String, errorCode: String? = nil, refId: String? = nil) {
        self.step = step
        self.status = status
        self.errorCode = errorCode
        self.refId = refId
    }

    public var key: SellerOnboardingStepKey? { SellerOnboardingStepKey(rawValue: step) }
    public var statusValue: SellerStepStatus { SellerStepStatus(rawValue: status) ?? .pending }
    public var trustError: TrustErrorCode? { errorCode.flatMap(TrustErrorCode.init(rawValue:)) }
}

public struct SellerProtocolInfo: Decodable, Equatable, Sendable {
    public let protocolCode: String?
    public let protocolVersion: String?
    public let contentHash: String?
    public let title: String?
    public let contentURL: String?
    public let contentMarkdown: String?

    public init(
        protocolCode: String? = nil,
        protocolVersion: String? = nil,
        contentHash: String? = nil,
        title: String? = nil,
        contentURL: String? = nil,
        contentMarkdown: String? = nil
    ) {
        self.protocolCode = protocolCode
        self.protocolVersion = protocolVersion
        self.contentHash = contentHash
        self.title = title
        self.contentURL = contentURL
        self.contentMarkdown = contentMarkdown
    }
}

public struct SellerOnboardingResponse: Decodable, Equatable, Sendable {
    public let steps: [SellerOnboardingStep]
    public let onboardingStatus: String?
    public let sellerType: String?
    public let protocolCode: String?
    public let protocolVersion: String?
    public let contentHash: String?
    public let protocolInfo: SellerProtocolInfo?
    public let signUrl: String?
    public let depositStatus: String?
    public let subMerchantStatus: String?

    enum CodingKeys: String, CodingKey {
        case steps, onboardingStatus, sellerType
        case protocolCode, protocolVersion, contentHash, protocolInfo
        case signUrl, depositStatus, subMerchantStatus
        case `protocol`
    }

    public init(
        steps: [SellerOnboardingStep] = [],
        onboardingStatus: String? = nil,
        sellerType: String? = nil,
        protocolCode: String? = nil,
        protocolVersion: String? = nil,
        contentHash: String? = nil,
        protocolInfo: SellerProtocolInfo? = nil,
        signUrl: String? = nil,
        depositStatus: String? = nil,
        subMerchantStatus: String? = nil
    ) {
        self.steps = steps
        self.onboardingStatus = onboardingStatus
        self.sellerType = sellerType
        self.protocolCode = protocolCode
        self.protocolVersion = protocolVersion
        self.contentHash = contentHash
        self.protocolInfo = protocolInfo
        self.signUrl = signUrl
        self.depositStatus = depositStatus
        self.subMerchantStatus = subMerchantStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = try c.decodeIfPresent([SellerOnboardingStep].self, forKey: .steps) ?? []
        onboardingStatus = try c.decodeIfPresent(String.self, forKey: .onboardingStatus)
        sellerType = try c.decodeIfPresent(String.self, forKey: .sellerType)
        protocolInfo = try c.decodeIfPresent(SellerProtocolInfo.self, forKey: .protocolInfo)
            ?? c.decodeIfPresent(SellerProtocolInfo.self, forKey: .protocol)
        protocolCode = try c.decodeIfPresent(String.self, forKey: .protocolCode) ?? protocolInfo?.protocolCode
        protocolVersion = try c.decodeIfPresent(String.self, forKey: .protocolVersion) ?? protocolInfo?.protocolVersion
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash) ?? protocolInfo?.contentHash
        signUrl = try c.decodeIfPresent(String.self, forKey: .signUrl)
        depositStatus = try c.decodeIfPresent(String.self, forKey: .depositStatus)
        subMerchantStatus = try c.decodeIfPresent(String.self, forKey: .subMerchantStatus)
    }

    public var isFinished: Bool { onboardingStatus == "finished" }

    public func step(_ key: SellerOnboardingStepKey) -> SellerOnboardingStep? {
        steps.first { $0.step == key.rawValue }
    }

    /// First incomplete step in forced order; nil when all done.
    public var currentStepKey: SellerOnboardingStepKey? {
        for key in SellerOnboardingStepKey.allCases {
            let st = step(key)?.statusValue ?? .pending
            if !st.isComplete { return key }
        }
        return nil
    }
}

public struct SellerActionRequest: Encodable, Equatable, Sendable {
    public let action: String
    public let protocolCode: String?
    public let protocolVersion: String?
    public let scrollEnd: Bool?

    public init(action: String, protocolCode: String? = nil, protocolVersion: String? = nil, scrollEnd: Bool? = nil) {
        self.action = action
        self.protocolCode = protocolCode
        self.protocolVersion = protocolVersion
        self.scrollEnd = scrollEnd
    }

    public static func start() -> SellerActionRequest { SellerActionRequest(action: "start") }

    public static func sign(protocolCode: String, protocolVersion: String, scrollEnd: Bool = true) -> SellerActionRequest {
        SellerActionRequest(action: "sign", protocolCode: protocolCode, protocolVersion: protocolVersion, scrollEnd: scrollEnd)
    }
}

public struct SellerDepositResponse: Decodable, Equatable, Sendable {
    public let depositId: String?
    public let status: String?
    public let amountFen: Int64?
    public let failReason: String?

    public init(depositId: String? = nil, status: String? = nil, amountFen: Int64? = nil, failReason: String? = nil) {
        self.depositId = depositId
        self.status = status
        self.amountFen = amountFen
        self.failReason = failReason
    }

    public var resolvedStatus: DepositStatus? { DepositStatus.normalize(status) }
    public var isFrozen: Bool { resolvedStatus?.allowsBidding == true }
    public var isPending: Bool { resolvedStatus == .pending || status == "deposit_pending" }
}

// MARK: - B-side merchant application (dual progress)

public struct MerchantApplicationResponse: Decodable, Equatable, Sendable {
    public let id: Int64?
    public let applyType: String?
    public let status: String?
    public let reviewStatus: String?
    public let subMerchantStatus: String?
    public let onboardingStatus: String?
    public let rejectReason: String?
    public let inviteCode: String?
    public let signUrl: String?

    public init(
        id: Int64? = nil,
        applyType: String? = nil,
        status: String? = nil,
        reviewStatus: String? = nil,
        subMerchantStatus: String? = nil,
        onboardingStatus: String? = nil,
        rejectReason: String? = nil,
        inviteCode: String? = nil,
        signUrl: String? = nil
    ) {
        self.id = id
        self.applyType = applyType
        self.status = status
        self.reviewStatus = reviewStatus
        self.subMerchantStatus = subMerchantStatus
        self.onboardingStatus = onboardingStatus
        self.rejectReason = rejectReason
        self.inviteCode = inviteCode
        self.signUrl = signUrl
    }

    public var isFinished: Bool { onboardingStatus == "finished" }

    public var reviewLabel: String { Self.label(for: reviewStatus ?? status) }
    public var subMerchantLabel: String { Self.label(for: subMerchantStatus) }

    public static func label(for raw: String?) -> String {
        switch raw {
        case "submitted", "pending", "reviewing": return "审核中"
        case "approved", "passed": return "已通过"
        case "rejected": return "已拒绝"
        case "applying", "processing", "pending_sign", "to_sign": return "处理中"
        case "finished", "succeeded", "active": return "已开通"
        case "failed": return "失败"
        case nil, "": return "未开始"
        default: return raw ?? "未知"
        }
    }
}

public struct MerchantApplicationCreateRequest: Encodable, Equatable, Sendable {
    public let inviteCode: String
    public let applyType: String
    public let docs: [String]?

    public init(inviteCode: String, applyType: String, docs: [String]? = nil) {
        self.inviteCode = inviteCode
        self.applyType = applyType
        self.docs = docs
    }
}

/// Parsed KYC return deep link (`paddock43://kyc/return` or Universal Link `/kyc/return/{channel}`).
public struct KYCReturnPayload: Equatable, Sendable {
    public let channel: String?
    public let sessionId: String
    public let code: String

    public init(channel: String? = nil, sessionId: String, code: String) {
        self.channel = channel
        self.sessionId = sessionId
        self.code = code
    }

    public static func parse(url: URL) -> KYCReturnPayload? {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let isAppScheme = scheme == "paddock43" || scheme == "velora"
        // paddock43://kyc/return?…  → host=kyc, path=/return
        // https://api…/kyc/return/alipay?…
        let matchesApp = isAppScheme && (host == "kyc" || path.contains("kyc") || path.contains("return"))
        let matchesUniversal = path.contains("/kyc/return")
        guard matchesApp || matchesUniversal else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ names: String...) -> String? {
            for name in names {
                if let v = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value, !v.isEmpty {
                    return v
                }
            }
            return nil
        }

        guard let sessionId = q("session_id", "sessionId", "id"),
              let code = q("code", "auth_code", "verify_result") else { return nil }

        var channel = q("channel")
        if channel == nil {
            let parts = url.path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(where: { $0.lowercased() == "return" }), idx + 1 < parts.count {
                channel = parts[idx + 1]
            }
        }
        return KYCReturnPayload(channel: channel, sessionId: sessionId, code: code)
    }
}
