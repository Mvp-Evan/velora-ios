import Foundation

// MARK: - Trust / KYC / seller (DES-v1.3-01-02) — app mirror of VeloraCore

enum TrustErrorCode: String {
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

    var fallbackMessage: String {
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
        case .stepRealNameRequired, .realNameRequired: return "请先完成实名认证"
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
        }
    }
}

extension APIError {
    var trustCode: TrustErrorCode? { TrustErrorCode(rawValue: code) }

    var trustMessage: String {
        if let t = trustCode { return message.isEmpty ? t.fallbackMessage : message }
        return message
    }
}

enum RealNameChannel: String, CaseIterable, Identifiable {
    case alipay, wechat, nationalNid = "national_nid"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .alipay: return "支付宝认证"
        case .wechat: return "微信认证"
        case .nationalNid: return "国家网络身份认证"
        }
    }

    var systemImage: String {
        switch self {
        case .alipay: return "yensign.circle"
        case .wechat: return "message"
        case .nationalNid: return "person.text.rectangle"
        }
    }

    var probeSchemes: [String] {
        switch self {
        case .alipay: return ["alipay", "alipays"]
        case .wechat: return ["weixin", "weixinULAPI"]
        case .nationalNid: return ["idauth", "cyberidentity"]
        }
    }
}

enum RealNameStatusValue: String {
    case unverified, none, pendingJump = "pending_jump", verifying, verified, failed, pending, rejected
    var isVerified: Bool { self == .verified }
    var displayLabel: String {
        switch self {
        case .verified: return "已实名"
        case .pendingJump, .verifying, .pending: return "认证中"
        case .failed, .rejected: return "认证失败"
        case .unverified, .none: return "未实名"
        }
    }
}

struct RealNameJumpPayload: Decodable, Equatable {
    let url: String?
    let appStoreUrl: String?
    let downloadUrl: String?

    var openURL: URL? {
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var installURL: URL? {
        let raw = (appStoreUrl ?? downloadUrl)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

struct RealNameSessionResponse: Decodable, Equatable {
    let sessionId: String?
    let status: String?
    let channel: String?
    let jump: RealNameJumpPayload?
    let failReason: String?
    let nameMasked: String?
    let idNoMasked: String?

    var statusValue: RealNameStatusValue? { status.flatMap(RealNameStatusValue.init(rawValue:)) }
    var isAlreadyVerified: Bool { statusValue?.isVerified == true }
}

struct RealNameStatusResponse: Decodable, Equatable {
    let status: String
    let channel: String?
    let failReason: String?
    let nameMasked: String?
    let idNoMasked: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status, channel, failReason, nameMasked, idNoMasked, sessionId, masked
    }

    init(
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

    init(from decoder: Decoder) throws {
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

    var statusValue: RealNameStatusValue { RealNameStatusValue(rawValue: status) ?? .unverified }
    var failCode: TrustErrorCode? { failReason.flatMap(TrustErrorCode.init(rawValue:)) }
}

enum SellerOnboardingStepKey: String, CaseIterable, Identifiable {
    case realName = "real_name"
    case protocolStep = "protocol"
    case deposit
    case subMerchant = "sub_merchant"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .realName: return "实名"
        case .protocolStep: return "协议"
        case .deposit: return "保证金"
        case .subMerchant: return "进件"
        }
    }

    var detail: String {
        switch self {
        case .realName: return "完成实名认证"
        case .protocolStep: return "签署卖家服务协议"
        case .deposit: return "冻结个人卖家保证金"
        case .subMerchant: return "开通收款二级商户"
        }
    }
}

enum SellerStepStatus: String {
    case pending, done, failed, inProgress = "in_progress", skippedDev = "skipped_dev"
    var isComplete: Bool { self == .done || self == .skippedDev }
}

struct SellerOnboardingStep: Decodable, Equatable, Identifiable {
    var id: String { step }
    let step: String
    let status: String
    let errorCode: String?
    let refId: String?

    var key: SellerOnboardingStepKey? { SellerOnboardingStepKey(rawValue: step) }
    var statusValue: SellerStepStatus { SellerStepStatus(rawValue: status) ?? .pending }
    var trustError: TrustErrorCode? { errorCode.flatMap(TrustErrorCode.init(rawValue:)) }
}

struct SellerProtocolInfo: Decodable, Equatable {
    let protocolCode: String?
    let protocolVersion: String?
    let contentHash: String?
    let title: String?
    let contentURL: String?
    let contentMarkdown: String?
}

struct SellerOnboardingResponse: Decodable, Equatable {
    let steps: [SellerOnboardingStep]
    let onboardingStatus: String?
    let sellerType: String?
    let protocolCode: String?
    let protocolVersion: String?
    let contentHash: String?
    let protocolInfo: SellerProtocolInfo?
    let signUrl: String?
    let depositStatus: String?
    let subMerchantStatus: String?

    enum CodingKeys: String, CodingKey {
        case steps, onboardingStatus, sellerType
        case protocolCode, protocolVersion, contentHash, protocolInfo
        case signUrl, depositStatus, subMerchantStatus
        case `protocol`
    }

    init(from decoder: Decoder) throws {
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

    var isFinished: Bool { onboardingStatus == "finished" }

    func step(_ key: SellerOnboardingStepKey) -> SellerOnboardingStep? {
        steps.first { $0.step == key.rawValue }
    }

    var currentStepKey: SellerOnboardingStepKey? {
        for key in SellerOnboardingStepKey.allCases {
            let st = step(key)?.statusValue ?? .pending
            if !st.isComplete { return key }
        }
        return nil
    }
}

struct SellerDepositResponse: Decodable, Equatable {
    let depositId: String?
    let status: String?
    let amountFen: Int64?
    let failReason: String?

    var resolvedStatus: DepositStatus? { DepositStatus.normalize(status) }
    var isFrozen: Bool { resolvedStatus?.allowsBidding == true }
    var isPending: Bool { resolvedStatus == .pending || status == "deposit_pending" }
}

struct MerchantApplicationResponse: Decodable, Equatable {
    let id: Int64?
    let applyType: String?
    let status: String?
    let reviewStatus: String?
    let subMerchantStatus: String?
    let onboardingStatus: String?
    let rejectReason: String?
    let inviteCode: String?
    let signUrl: String?

    var isFinished: Bool { onboardingStatus == "finished" }
    var reviewLabel: String { Self.label(for: reviewStatus ?? status) }
    var subMerchantLabel: String { Self.label(for: subMerchantStatus) }

    static func label(for raw: String?) -> String {
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

struct KYCReturnPayload: Equatable {
    let channel: String?
    let sessionId: String
    let code: String

    static func parse(url: URL) -> KYCReturnPayload? {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let isAppScheme = scheme == "paddock43" || scheme == "velora"
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
