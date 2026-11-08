import Foundation
import CryptoKit

// MARK: - Lottery enroll / draw / waitlist (DES-v1.3-06-02 REL-02/03/04/05 / D24)

/// Product defaults (design §3 / §5.1 / §5.5 / §13 / §15).
public enum LotteryConfigDefaults {
    public static let payWindowSec = 7_200
    public static let payWindowMinSec = 1_800
    public static let payWindowMaxSec = 86_400
    public static let depositDefaultFen: Int64 = 20_000
    public static let creditMin = 80
    public static let n12RemindSec = 1_800
    public static let algorithmVersion = "fy-sha256-v1"
    public static let orderType = "lottery"
    public static let depositType = "lottery"
    public static let launchGateKey = "feature_flags.lottery"
    public static let meEntryKey = "lottery"
    public static let seedPrefixLength = 8
    public static let externalRandomMaxLen = 512
    /// Static reproduce guide path (design §5.4 / §5.6) — App links / copies.
    public static let reproduceGuidePath = "/static/lottery-reproduce.html"
}

// MARK: - Status / dims / place

/// `release.status` for mode=lottery (design §4).
public enum LotteryReleaseStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case enrollScheduled = "enroll_scheduled"
    case enrolling
    case enrollClosed = "enroll_closed"
    case hashing
    case drawing
    case drawn
    case completed

    public var displayLabel: String {
        switch self {
        case .draft: return "草稿"
        case .enrollScheduled: return "报名未开始"
        case .enrolling: return "报名中"
        case .enrollClosed: return "报名已截止"
        case .hashing: return "封单中"
        case .drawing: return "开奖中"
        case .drawn: return "已开奖"
        case .completed: return "已结束"
        }
    }

    public var isDrawingInProgress: Bool {
        self == .hashing || self == .drawing
    }

    public var allowsEnroll: Bool {
        self == .enrolling
    }
}

/// `lottery_entry.status` (design §4).
public enum LotteryEntryStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case registered
    case won
    case waitlisted
    case lost
    case paid
    case forfeited

    public var displayLabel: String {
        switch self {
        case .registered: return "待开奖"
        case .won: return "中签待付"
        case .waitlisted: return "候补"
        case .lost: return "未中签"
        case .paid: return "已付款"
        case .forfeited: return "已弃权"
        }
    }

    public var isTerminal: Bool {
        self == .lost || self == .paid || self == .forfeited
    }

    public var showsPayCTA: Bool {
        self == .won
    }

    public var showsDepositReleasedHint: Bool {
        self == .lost || self == .paid
    }
}

/// Result place on draw (design §3).
public enum LotteryResultPlace: String, Codable, Sendable, CaseIterable, Equatable {
    case won
    case waitlisted
    case lost
}

/// Dedup dimension keys (design §5.2).
public enum LotteryDedupDim: String, Codable, Sendable, CaseIterable, Equatable {
    case idNo = "id_no"
    case device
    case address
    case payAccount = "pay_account"

    public var displayLabel: String {
        switch self {
        case .idNo: return "证件"
        case .device: return "设备"
        case .address: return "收货地址"
        case .payAccount: return "支付账户"
        }
    }
}

/// `order.win_source` (design §3 / §5.5).
public enum LotteryWinSource: String, Codable, Sendable, CaseIterable, Equatable {
    case drawn
    case waitlist

    public var displayLabel: String {
        switch self {
        case .drawn: return "开奖中签"
        case .waitlist: return "候补递补"
        }
    }
}

// MARK: - Eligibility / checklist / CTA

public struct LotteryEligibility: Codable, Equatable, Sendable {
    public let realNamed: Bool?
    public let depositFrozen: Bool?
    public let creditOk: Bool?
    public let creditScore: Int?
    public let vipLevel: Int?
    public let vipOk: Bool?
    public let alreadyEntered: Bool?
    public let entryId: Int64?
    public let addressReady: Bool?
    public let deviceReady: Bool?

    public init(
        realNamed: Bool? = nil,
        depositFrozen: Bool? = nil,
        creditOk: Bool? = nil,
        creditScore: Int? = nil,
        vipLevel: Int? = nil,
        vipOk: Bool? = nil,
        alreadyEntered: Bool? = nil,
        entryId: Int64? = nil,
        addressReady: Bool? = nil,
        deviceReady: Bool? = nil
    ) {
        self.realNamed = realNamed
        self.depositFrozen = depositFrozen
        self.creditOk = creditOk
        self.creditScore = creditScore
        self.vipLevel = vipLevel
        self.vipOk = vipOk
        self.alreadyEntered = alreadyEntered
        self.entryId = entryId
        self.addressReady = addressReady
        self.deviceReady = deviceReady
    }

    public var isRealNamed: Bool { realNamed == true }
    public var isDepositFrozen: Bool { depositFrozen == true }
    public var isCreditOk: Bool {
        if let creditOk { return creditOk }
        if let creditScore { return creditScore >= LotteryConfigDefaults.creditMin }
        return false
    }
    public var isVipOk: Bool { vipOk != false }
    public var hasEntered: Bool { alreadyEntered == true || entryId != nil }
    public var resolvedVipLevel: Int { vipLevel ?? 0 }
}

public enum LotteryEnrollStep: String, Sendable, Equatable, CaseIterable {
    case login
    case realName
    case credit
    case deposit
    case address

    public var title: String {
        switch self {
        case .login: return "登录"
        case .realName: return "实名认证"
        case .credit: return "信用分"
        case .deposit: return "冻结保证金"
        case .address: return "收货地址"
        }
    }

    public var actionTitle: String {
        switch self {
        case .login: return "去登录"
        case .realName: return "去实名"
        case .credit: return "查看信用"
        case .deposit: return "去冻结保证金"
        case .address: return "填写地址"
        }
    }
}

public struct LotteryEnrollChecklistItem: Equatable, Sendable, Identifiable {
    public let step: LotteryEnrollStep
    public let done: Bool

    public var id: String { step.rawValue }

    public init(step: LotteryEnrollStep, done: Bool) {
        self.step = step
        self.done = done
    }
}

public enum LotteryCTA: String, Sendable, Equatable {
    case login
    case waitEnrollOpen
    case completeEligibility
    case enroll
    case enrolledWaiting
    case drawing
    case viewProof
    case pay
    case waitlist
    case lost
    case paid
    case forfeited
    case enrollClosed
    case ended

    public var buttonTitle: String {
        switch self {
        case .login: return "登录后报名"
        case .waitEnrollOpen: return "报名未开始"
        case .completeEligibility: return LotteryCopy.completeEligibility
        case .enroll: return LotteryCopy.enroll
        case .enrolledWaiting: return LotteryCopy.enrolledWaiting
        case .drawing: return LotteryCopy.drawing
        case .viewProof: return LotteryCopy.viewProof
        case .pay: return LotteryCopy.payCTA
        case .waitlist: return LotteryCopy.waitlist
        case .lost: return LotteryCopy.lost
        case .paid: return LotteryCopy.paid
        case .forfeited: return LotteryCopy.forfeited
        case .enrollClosed: return LotteryCopy.enrollClosed
        case .ended: return LotteryCopy.ended
        }
    }

    public var isPrimaryAction: Bool {
        switch self {
        case .login, .completeEligibility, .enroll, .pay, .viewProof: return true
        default: return false
        }
    }
}

// MARK: - Release detail (GET /api/v1/releases/{id} mode=lottery)

public struct LotteryReleaseDetail: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let merchantId: Int64?
    public let listingId: Int64?
    public let brandId: Int64?
    public let title: String?
    public let cover: String?
    public let mode: String?
    public let status: LotteryReleaseStatus?
    public let enrollStartAt: Date?
    public let enrollEndAt: Date?
    public let drawAt: Date?
    public let quotaN: Int?
    public let waitlistM: Int?
    public let payWindowSec: Int?
    public let depositFen: Int64?
    public let priceFen: Int64?
    public let dedupDims: [String]?
    public let algorithmVersion: String?
    public let legalReviewRequired: Bool?
    public let legalReviewed: Bool?
    public let entriesHash: String?
    public let entriesCount: Int?
    public let eligibility: LotteryEligibility?
    public let myEntry: LotteryEntry?
    public let remainingUnpaidWon: Int?
    public let serverNow: Date?
    public let serverNowMs: Int64?
    public let serverTime: Date?
    public let serverTimeMs: Int64?

    public init(
        id: Int64,
        merchantId: Int64? = nil,
        listingId: Int64? = nil,
        brandId: Int64? = nil,
        title: String? = nil,
        cover: String? = nil,
        mode: String? = nil,
        status: LotteryReleaseStatus? = nil,
        enrollStartAt: Date? = nil,
        enrollEndAt: Date? = nil,
        drawAt: Date? = nil,
        quotaN: Int? = nil,
        waitlistM: Int? = nil,
        payWindowSec: Int? = nil,
        depositFen: Int64? = nil,
        priceFen: Int64? = nil,
        dedupDims: [String]? = nil,
        algorithmVersion: String? = nil,
        legalReviewRequired: Bool? = nil,
        legalReviewed: Bool? = nil,
        entriesHash: String? = nil,
        entriesCount: Int? = nil,
        eligibility: LotteryEligibility? = nil,
        myEntry: LotteryEntry? = nil,
        remainingUnpaidWon: Int? = nil,
        serverNow: Date? = nil,
        serverNowMs: Int64? = nil,
        serverTime: Date? = nil,
        serverTimeMs: Int64? = nil
    ) {
        self.id = id
        self.merchantId = merchantId
        self.listingId = listingId
        self.brandId = brandId
        self.title = title
        self.cover = cover
        self.mode = mode
        self.status = status
        self.enrollStartAt = enrollStartAt
        self.enrollEndAt = enrollEndAt
        self.drawAt = drawAt
        self.quotaN = quotaN
        self.waitlistM = waitlistM
        self.payWindowSec = payWindowSec
        self.depositFen = depositFen
        self.priceFen = priceFen
        self.dedupDims = dedupDims
        self.algorithmVersion = algorithmVersion
        self.legalReviewRequired = legalReviewRequired
        self.legalReviewed = legalReviewed
        self.entriesHash = entriesHash
        self.entriesCount = entriesCount
        self.eligibility = eligibility
        self.myEntry = myEntry
        self.remainingUnpaidWon = remainingUnpaidWon
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
        self.serverTime = serverTime
        self.serverTimeMs = serverTimeMs
    }

    enum CodingKeys: String, CodingKey {
        case id, merchantId, listingId, brandId, title, cover, mode, status
        case enrollStartAt, enrollEndAt, drawAt, quotaN, waitlistM, payWindowSec
        case depositFen, exclusiveDepositFen, priceFen, dedupDims, algorithmVersion
        case legalReviewRequired, legalReviewed, entriesHash, entriesCount
        case eligibility, userEligibility, myEntry, remainingUnpaidWon
        case serverNow, serverNowMs, serverTime, serverTimeMs
        case n, m
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        merchantId = try c.decodeIfPresent(Int64.self, forKey: .merchantId)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId)
        brandId = try c.decodeIfPresent(Int64.self, forKey: .brandId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        status = try c.decodeIfPresent(LotteryReleaseStatus.self, forKey: .status)
        enrollStartAt = try c.decodeIfPresent(Date.self, forKey: .enrollStartAt)
        enrollEndAt = try c.decodeIfPresent(Date.self, forKey: .enrollEndAt)
        drawAt = try c.decodeIfPresent(Date.self, forKey: .drawAt)
        quotaN = try c.decodeIfPresent(Int.self, forKey: .quotaN)
            ?? c.decodeIfPresent(Int.self, forKey: .n)
        waitlistM = try c.decodeIfPresent(Int.self, forKey: .waitlistM)
            ?? c.decodeIfPresent(Int.self, forKey: .m)
        payWindowSec = try c.decodeIfPresent(Int.self, forKey: .payWindowSec)
        depositFen = try c.decodeIfPresent(Int64.self, forKey: .depositFen)
            ?? c.decodeIfPresent(Int64.self, forKey: .exclusiveDepositFen)
        priceFen = try c.decodeIfPresent(Int64.self, forKey: .priceFen)
        dedupDims = try c.decodeIfPresent([String].self, forKey: .dedupDims)
        algorithmVersion = try c.decodeIfPresent(String.self, forKey: .algorithmVersion)
        legalReviewRequired = try c.decodeIfPresent(Bool.self, forKey: .legalReviewRequired)
        legalReviewed = try c.decodeIfPresent(Bool.self, forKey: .legalReviewed)
        entriesHash = try c.decodeIfPresent(String.self, forKey: .entriesHash)
        entriesCount = try c.decodeIfPresent(Int.self, forKey: .entriesCount)
        eligibility = try c.decodeIfPresent(LotteryEligibility.self, forKey: .eligibility)
            ?? c.decodeIfPresent(LotteryEligibility.self, forKey: .userEligibility)
        myEntry = try c.decodeIfPresent(LotteryEntry.self, forKey: .myEntry)
        remainingUnpaidWon = try c.decodeIfPresent(Int.self, forKey: .remainingUnpaidWon)
        serverNow = try c.decodeIfPresent(Date.self, forKey: .serverNow)
        serverNowMs = try c.decodeIfPresent(Int64.self, forKey: .serverNowMs)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        serverTimeMs = try c.decodeIfPresent(Int64.self, forKey: .serverTimeMs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(merchantId, forKey: .merchantId)
        try c.encodeIfPresent(listingId, forKey: .listingId)
        try c.encodeIfPresent(brandId, forKey: .brandId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(enrollStartAt, forKey: .enrollStartAt)
        try c.encodeIfPresent(enrollEndAt, forKey: .enrollEndAt)
        try c.encodeIfPresent(drawAt, forKey: .drawAt)
        try c.encodeIfPresent(quotaN, forKey: .quotaN)
        try c.encodeIfPresent(waitlistM, forKey: .waitlistM)
        try c.encodeIfPresent(payWindowSec, forKey: .payWindowSec)
        try c.encodeIfPresent(depositFen, forKey: .depositFen)
        try c.encodeIfPresent(priceFen, forKey: .priceFen)
        try c.encodeIfPresent(dedupDims, forKey: .dedupDims)
        try c.encodeIfPresent(algorithmVersion, forKey: .algorithmVersion)
        try c.encodeIfPresent(legalReviewRequired, forKey: .legalReviewRequired)
        try c.encodeIfPresent(legalReviewed, forKey: .legalReviewed)
        try c.encodeIfPresent(entriesHash, forKey: .entriesHash)
        try c.encodeIfPresent(entriesCount, forKey: .entriesCount)
        try c.encodeIfPresent(eligibility, forKey: .eligibility)
        try c.encodeIfPresent(myEntry, forKey: .myEntry)
        try c.encodeIfPresent(remainingUnpaidWon, forKey: .remainingUnpaidWon)
        try c.encodeIfPresent(serverNow, forKey: .serverNow)
        try c.encodeIfPresent(serverNowMs, forKey: .serverNowMs)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(serverTimeMs, forKey: .serverTimeMs)
    }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "抽签发售"
    }

    public var isLotteryMode: Bool {
        (mode ?? "").lowercased() == SpotReleaseMode.lottery.rawValue
    }

    public var resolvedQuotaN: Int { max(1, quotaN ?? 1) }

    public var resolvedWaitlistM: Int { max(0, waitlistM ?? resolvedQuotaN) }

    public var resolvedPayWindowSec: Int {
        let w = payWindowSec ?? LotteryConfigDefaults.payWindowSec
        return min(
            max(w, LotteryConfigDefaults.payWindowMinSec),
            LotteryConfigDefaults.payWindowMaxSec
        )
    }

    public var resolvedDepositFen: Int64 {
        depositFen ?? LotteryConfigDefaults.depositDefaultFen
    }

    public var resolvedAlgorithmVersion: String {
        let v = algorithmVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? LotteryConfigDefaults.algorithmVersion : v
    }

    public var resolvedServerNowMs: Int64? {
        if let serverNowMs, serverNowMs > 0 { return serverNowMs }
        if let serverTimeMs, serverTimeMs > 0 { return serverTimeMs }
        if let serverNow { return Int64(serverNow.timeIntervalSince1970 * 1000) }
        if let serverTime { return Int64(serverTime.timeIntervalSince1970 * 1000) }
        return nil
    }

    public var resolvedServerNow: Date? {
        if let ms = resolvedServerNowMs {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        return nil
    }
}

// MARK: - Entry / enroll body / deposit

public struct LotteryDeviceAttestation: Codable, Equatable, Sendable {
    public let vendorId: String?
    public let platform: String
    public let empty: Bool?

    public init(vendorId: String? = nil, platform: String = "ios", empty: Bool? = nil) {
        self.vendorId = vendorId
        self.platform = platform
        self.empty = empty
    }

    public var isEmptyDevice: Bool {
        if empty == true { return true }
        let v = (vendorId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty
    }
}

public struct LotteryEntryCreateBody: Codable, Equatable, Sendable {
    public let addressId: Int64
    public let deviceAttestation: LotteryDeviceAttestation

    public init(addressId: Int64, deviceAttestation: LotteryDeviceAttestation) {
        self.addressId = addressId
        self.deviceAttestation = deviceAttestation
    }
}

public struct LotteryEntry: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let entryNo: Int64?
    public let releaseId: Int64?
    public let status: LotteryEntryStatus?
    public let rank: Int?
    public let place: LotteryResultPlace?
    public let orderId: Int64?
    public let depositId: Int64?
    public let payDeadline: Date?
    public let winSource: LotteryWinSource?
    public let title: String?
    public let cover: String?
    public let priceFen: Int64?
    public let waitlistRank: Int?
    public let remainingUnpaidWon: Int?
    public let depositStatus: String?
    public let drawAt: Date?
    public let enrolledAt: Date?
    public let serverNow: Date?
    public let serverNowMs: Int64?

    public init(
        id: Int64,
        entryNo: Int64? = nil,
        releaseId: Int64? = nil,
        status: LotteryEntryStatus? = nil,
        rank: Int? = nil,
        place: LotteryResultPlace? = nil,
        orderId: Int64? = nil,
        depositId: Int64? = nil,
        payDeadline: Date? = nil,
        winSource: LotteryWinSource? = nil,
        title: String? = nil,
        cover: String? = nil,
        priceFen: Int64? = nil,
        waitlistRank: Int? = nil,
        remainingUnpaidWon: Int? = nil,
        depositStatus: String? = nil,
        drawAt: Date? = nil,
        enrolledAt: Date? = nil,
        serverNow: Date? = nil,
        serverNowMs: Int64? = nil
    ) {
        self.id = id
        self.entryNo = entryNo
        self.releaseId = releaseId
        self.status = status
        self.rank = rank
        self.place = place
        self.orderId = orderId
        self.depositId = depositId
        self.payDeadline = payDeadline
        self.winSource = winSource
        self.title = title
        self.cover = cover
        self.priceFen = priceFen
        self.waitlistRank = waitlistRank
        self.remainingUnpaidWon = remainingUnpaidWon
        self.depositStatus = depositStatus
        self.drawAt = drawAt
        self.enrolledAt = enrolledAt
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
    }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "抽签活动"
    }

    public var resolvedStatus: LotteryEntryStatus {
        status ?? .registered
    }

    public var resolvedWaitlistRank: Int? {
        waitlistRank ?? (resolvedStatus == .waitlisted ? rank : nil)
    }

    public var isDepositReleased: Bool {
        let s = (depositStatus ?? "").lowercased()
        return s == "released" || s == "refunded" || resolvedStatus.showsDepositReleasedHint
    }

    public var resolvedServerNow: Date? {
        if let serverNowMs, serverNowMs > 0 {
            return Date(timeIntervalSince1970: Double(serverNowMs) / 1000)
        }
        return serverNow
    }
}

public struct LotteryEntryCreateResult: Codable, Equatable, Sendable {
    public let entry: LotteryEntry?
    public let entryId: Int64?
    public let entryNo: Int64?
    public let releaseId: Int64?
    public let status: LotteryEntryStatus?
    public let depositId: Int64?
    public let depositStatus: String?
    public let alreadyEntered: Bool?
    public let payParams: [String: String]?

    public init(
        entry: LotteryEntry? = nil,
        entryId: Int64? = nil,
        entryNo: Int64? = nil,
        releaseId: Int64? = nil,
        status: LotteryEntryStatus? = nil,
        depositId: Int64? = nil,
        depositStatus: String? = nil,
        alreadyEntered: Bool? = nil,
        payParams: [String: String]? = nil
    ) {
        self.entry = entry
        self.entryId = entryId
        self.entryNo = entryNo
        self.releaseId = releaseId
        self.status = status
        self.depositId = depositId
        self.depositStatus = depositStatus
        self.alreadyEntered = alreadyEntered
        self.payParams = payParams
    }

    public var resolvedEntryId: Int64? {
        entry?.id ?? entryId
    }

    public var isRegistered: Bool {
        let s = entry?.status ?? status
        return s == .registered || alreadyEntered == true
    }

    public var needsDepositPayment: Bool {
        let s = (depositStatus ?? "").lowercased()
        return s == "pending" || s == "requires_payment" || (payParams?.isEmpty == false)
    }
}

public struct LotteryDepositResult: Codable, Equatable, Sendable {
    public let depositId: Int64?
    public let paymentId: Int64?
    public let amountFen: Int64?
    public let status: String?
    public let channel: String?
    public let payParams: [String: String]?

    public init(
        depositId: Int64? = nil,
        paymentId: Int64? = nil,
        amountFen: Int64? = nil,
        status: String? = nil,
        channel: String? = nil,
        payParams: [String: String]? = nil
    ) {
        self.depositId = depositId
        self.paymentId = paymentId
        self.amountFen = amountFen
        self.status = status
        self.channel = channel
        self.payParams = payParams
    }

    public var isFrozen: Bool {
        let s = (status ?? "").lowercased()
        return s == "frozen" || s == "held" || s == "success" || s == "succeeded" || s == "paid"
    }
}

// MARK: - Draw proof (GET /api/v1/releases/{id}/draw-proof)

public struct LotteryMaskedParticipant: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let rank: Int?
    public let nicknameMasked: String?
    public let phoneMasked: String?

    public var id: String {
        "\(rank ?? 0)-\(nicknameMasked ?? "")-\(phoneMasked ?? "")"
    }

    public init(rank: Int? = nil, nicknameMasked: String? = nil, phoneMasked: String? = nil) {
        self.rank = rank
        self.nicknameMasked = nicknameMasked
        self.phoneMasked = phoneMasked
    }

    enum CodingKeys: String, CodingKey {
        case rank, nicknameMasked, phoneMasked, nickname, phone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank)
        nicknameMasked = try c.decodeIfPresent(String.self, forKey: .nicknameMasked)
            ?? c.decodeIfPresent(String.self, forKey: .nickname)
        phoneMasked = try c.decodeIfPresent(String.self, forKey: .phoneMasked)
            ?? c.decodeIfPresent(String.self, forKey: .phone)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(rank, forKey: .rank)
        try c.encodeIfPresent(nicknameMasked, forKey: .nicknameMasked)
        try c.encodeIfPresent(phoneMasked, forKey: .phoneMasked)
    }

    public var displayName: String {
        let nick = (nicknameMasked?.isEmpty == false) ? nicknameMasked! : "参与者"
        if let phone = phoneMasked, !phone.isEmpty {
            return "\(nick) · \(phone)"
        }
        return nick
    }
}

/// Public draw-proof payload (design §5.6) — no user_id / entry_id / full id hashes.
public struct LotteryDrawProof: Codable, Equatable, Sendable, Identifiable {
    public let releaseId: Int64
    public let entriesCount: Int?
    public let entriesHash: String?
    public let algorithmVersion: String?
    public let externalSource: String?
    public let externalRef: String?
    public let externalRandom: String?
    public let seed: String?
    public let n: Int?
    public let m: Int?
    public let drawnAt: Date?
    public let winners: [LotteryMaskedParticipant]
    public let waitlist: [LotteryMaskedParticipant]
    public let legalReviewed: Bool?
    public let proofSig: String?
    public let title: String?

    public var id: Int64 { releaseId }

    public init(
        releaseId: Int64,
        entriesCount: Int? = nil,
        entriesHash: String? = nil,
        algorithmVersion: String? = nil,
        externalSource: String? = nil,
        externalRef: String? = nil,
        externalRandom: String? = nil,
        seed: String? = nil,
        n: Int? = nil,
        m: Int? = nil,
        drawnAt: Date? = nil,
        winners: [LotteryMaskedParticipant] = [],
        waitlist: [LotteryMaskedParticipant] = [],
        legalReviewed: Bool? = nil,
        proofSig: String? = nil,
        title: String? = nil
    ) {
        self.releaseId = releaseId
        self.entriesCount = entriesCount
        self.entriesHash = entriesHash
        self.algorithmVersion = algorithmVersion
        self.externalSource = externalSource
        self.externalRef = externalRef
        self.externalRandom = externalRandom
        self.seed = seed
        self.n = n
        self.m = m
        self.drawnAt = drawnAt
        self.winners = winners
        self.waitlist = waitlist
        self.legalReviewed = legalReviewed
        self.proofSig = proofSig
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case releaseId, entriesCount, entriesHash, algorithmVersion
        case externalSource, externalRef, externalRandom, seed
        case n, m, quotaN, waitlistM, drawnAt, winners, waitlist
        case legalReviewed, proofSig, title
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        releaseId = try c.decode(Int64.self, forKey: .releaseId)
        entriesCount = try c.decodeIfPresent(Int.self, forKey: .entriesCount)
        entriesHash = try c.decodeIfPresent(String.self, forKey: .entriesHash)
        algorithmVersion = try c.decodeIfPresent(String.self, forKey: .algorithmVersion)
        externalSource = try c.decodeIfPresent(String.self, forKey: .externalSource)
        externalRef = try c.decodeIfPresent(String.self, forKey: .externalRef)
        externalRandom = try c.decodeIfPresent(String.self, forKey: .externalRandom)
        seed = try c.decodeIfPresent(String.self, forKey: .seed)
        n = try c.decodeIfPresent(Int.self, forKey: .n)
            ?? c.decodeIfPresent(Int.self, forKey: .quotaN)
        m = try c.decodeIfPresent(Int.self, forKey: .m)
            ?? c.decodeIfPresent(Int.self, forKey: .waitlistM)
        drawnAt = try c.decodeIfPresent(Date.self, forKey: .drawnAt)
        winners = try c.decodeIfPresent([LotteryMaskedParticipant].self, forKey: .winners) ?? []
        waitlist = try c.decodeIfPresent([LotteryMaskedParticipant].self, forKey: .waitlist) ?? []
        legalReviewed = try c.decodeIfPresent(Bool.self, forKey: .legalReviewed)
        proofSig = try c.decodeIfPresent(String.self, forKey: .proofSig)
        title = try c.decodeIfPresent(String.self, forKey: .title)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(releaseId, forKey: .releaseId)
        try c.encodeIfPresent(entriesCount, forKey: .entriesCount)
        try c.encodeIfPresent(entriesHash, forKey: .entriesHash)
        try c.encodeIfPresent(algorithmVersion, forKey: .algorithmVersion)
        try c.encodeIfPresent(externalSource, forKey: .externalSource)
        try c.encodeIfPresent(externalRef, forKey: .externalRef)
        try c.encodeIfPresent(externalRandom, forKey: .externalRandom)
        try c.encodeIfPresent(seed, forKey: .seed)
        try c.encodeIfPresent(n, forKey: .n)
        try c.encodeIfPresent(m, forKey: .m)
        try c.encodeIfPresent(drawnAt, forKey: .drawnAt)
        try c.encode(winners, forKey: .winners)
        try c.encode(waitlist, forKey: .waitlist)
        try c.encodeIfPresent(legalReviewed, forKey: .legalReviewed)
        try c.encodeIfPresent(proofSig, forKey: .proofSig)
        try c.encodeIfPresent(title, forKey: .title)
    }

    public var resolvedAlgorithmVersion: String {
        let v = algorithmVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? LotteryConfigDefaults.algorithmVersion : v
    }

    public var isLegalReviewed: Bool { legalReviewed == true }

    /// Flat public field lines for「复制全部字段」(design §9).
    public var copyAllFieldsText: String {
        var lines: [String] = []
        lines.append("release_id=\(releaseId)")
        if let entriesCount { lines.append("entries_count=\(entriesCount)") }
        if let entriesHash { lines.append("entries_hash=\(entriesHash)") }
        lines.append("algorithm_version=\(resolvedAlgorithmVersion)")
        if let externalSource { lines.append("external_source=\(externalSource)") }
        if let externalRef { lines.append("external_ref=\(externalRef)") }
        if let externalRandom { lines.append("external_random=\(externalRandom)") }
        if let seed { lines.append("seed=\(seed)") }
        if let n { lines.append("n=\(n)") }
        if let m { lines.append("m=\(m)") }
        if let drawnAt {
            lines.append("drawn_at=\(ISO8601DateFormatter().string(from: drawnAt))")
        }
        lines.append("legal_reviewed=\(isLegalReviewed)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Error codes / copy

public enum LotteryErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case authRequired = "auth_required"
    case unauthorized
    case loginRequired = "login_required"
    case realNameRequired = "real_name_required"
    case creditTooLow = "credit_too_low"
    case accountRestricted = "account_restricted"
    case enrollClosed = "enroll_closed"
    case enrollNotStarted = "enroll_not_started"
    case vipLevelRequired = "vip_level_required"
    case alreadyEntered = "already_entered"
    case duplicateIdNo = "duplicate_id_no"
    case duplicateDevice = "duplicate_device"
    case duplicateAddress = "duplicate_address"
    case duplicatePayAccount = "duplicate_pay_account"
    case deviceRequired = "device_required"
    case addressRequired = "address_required"
    case depositNotFrozen = "deposit_not_frozen"
    case relatedAccountBlocked = "related_account_blocked"
    case drawNotReady = "draw_not_ready"
    case drawTooEarly = "draw_too_early"
    case drawAlreadyDone = "draw_already_done"
    case legalReviewRequired = "legal_review_required"
    case externalRandomTooOld = "external_random_too_old"
    case rateLimited = "rate_limited"
    case capabilityDisabled = "capability_disabled"
    case featureDisabled = "feature_disabled"

    public var opensLogin: Bool {
        self == .authRequired || self == .unauthorized || self == .loginRequired
    }

    public var opensRealName: Bool {
        self == .realNameRequired
    }

    public var opensDeposit: Bool {
        self == .depositNotFrozen
    }

    public var opensAddress: Bool {
        self == .addressRequired
    }

    public var isDedupConflict: Bool {
        switch self {
        case .duplicateIdNo, .duplicateDevice, .duplicateAddress, .duplicatePayAccount:
            return true
        default:
            return false
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return "请重试"
        case .authRequired, .unauthorized, .loginRequired: return "请先登录"
        case .realNameRequired: return "请先完成实名认证"
        case .creditTooLow: return LotteryCopy.creditTooLow
        case .accountRestricted: return "账号受限，暂不可抽签"
        case .enrollClosed: return LotteryCopy.enrollClosed
        case .enrollNotStarted: return "报名尚未开始"
        case .vipLevelRequired: return "会员等级不足，暂不可报名"
        case .alreadyEntered: return "本场已报名"
        case .duplicateIdNo: return LotteryCopy.duplicateGeneric
        case .duplicateDevice: return LotteryCopy.duplicateGeneric
        case .duplicateAddress: return LotteryCopy.duplicateAddress
        case .duplicatePayAccount: return LotteryCopy.duplicateGeneric
        case .deviceRequired: return "当前设备无法完成报名，请联系客服"
        case .addressRequired: return "请先设置默认收货地址"
        case .depositNotFrozen: return "请先冻结保证金"
        case .relatedAccountBlocked: return "关联账号受限"
        case .drawNotReady: return "开奖凭证尚未公示"
        case .drawTooEarly: return "尚未到开奖时间"
        case .drawAlreadyDone: return "本场已开奖"
        case .legalReviewRequired: return "本场须法务审阅后开奖"
        case .externalRandomTooOld: return "外部随机值开奖日过早"
        case .rateLimited: return "操作过于频繁，请稍后再试"
        case .capabilityDisabled, .featureDisabled: return "抽签功能暂未开放"
        }
    }
}

public enum LotteryCopy {
    public static let pageTitle = "抽签报名"
    public static let myEntriesTitle = "我的抽签"
    public static let proofTitle = "开奖凭证"
    public static let enroll = "立即报名"
    public static let enrolledWaiting = "已报名 · 待开奖"
    public static let completeEligibility = "去完成资格"
    public static let drawing = "结果计算中"
    public static let viewProof = "查看开奖凭证"
    public static let payCTA = "去付款"
    public static let waitlist = "候补中"
    public static let lost = "未中签"
    public static let paid = "已付款"
    public static let forfeited = "已弃权"
    public static let enrollClosed = "报名已截止"
    public static let ended = "活动已结束"
    public static let depositReleased = "保证金已解冻"
    public static let depositDeducted = "保证金已扣除"
    public static let creditTooLow = "信用分不足 80，暂不可抽签"
    public static let duplicateGeneric = "本场报名资格已被占用"
    public static let duplicateAddress = "该收货地址已报名本场"
    public static let duplicateHint = "如需帮助请联系客服"
    public static let serverTimeHint = "以服务器时间为准"
    public static let weakNetRetry = "网络不稳定，可放心重试"
    public static let payWindowHint = "中签后 2 小时内付款"
    public static let n12RemindHint = "付款截止前 30 分钟将提醒你"
    public static let legalReviewedBadge = "本场已经法务审阅"
    public static let reproduceGuide = "复现说明"
    public static let copyAllFields = "复制全部字段"
    public static let copyHash = "复制哈希"
    public static let copySeed = "复制 seed"
    public static let emptyEntries = "还没有抽签报名"
    public static let emptyEntriesHint = "报名后可在这里查看中签与候补"
    public static let waitlistPositionPrefix = "当前候补位"
    public static let remainingUnpaidPrefix = "剩余中签未付"
    public static let forbiddenSpotBuyCTA = "请使用中签付款，勿走普通购买"
    public static let reproduceSteps: [String] = [
        "下载封单时刻公示的人数与哈希，与凭证 entries_hash 比对。",
        "向公众核对 external_ref 指向的开奖公告。",
        "seed = SHA-256(entries_hash_hex || external_random)（无分隔符）。",
        "按 fy-sha256-v1（HMAC-SHA256 拒绝采样 Fisher–Yates）洗牌，取前 N/M。",
    ]
}

// MARK: - Pure logic

public enum LotteryLogic {
    /// Design §5.4 / §5.6 — `seed = SHA-256(entries_hash_hex || UTF-8(external_random))` then hex.
    public static func computeSeed(entriesHashHex: String, externalRandom: String) -> String {
        let hash = entriesHashHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let random = externalRandom
        let digest = SHA256.hash(data: Data((hash + random).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func seedPrefix(
        _ seedHex: String,
        length: Int = LotteryConfigDefaults.seedPrefixLength
    ) -> String {
        let s = seedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard length > 0 else { return "" }
        return String(s.prefix(length))
    }

    /// Preview helper for merchant/ops paste check (design §5.4).
    public static func previewSeedPrefix(entriesHashHex: String, externalRandom: String) -> String {
        seedPrefix(computeSeed(entriesHashHex: entriesHashHex, externalRandom: externalRandom))
    }

    public static func isValidExternalRandom(_ raw: String) -> Bool {
        let s = raw
        if s.isEmpty || s.count > LotteryConfigDefaults.externalRandomMaxLen { return false }
        // Reject ASCII control characters (design §8).
        return s.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
    }

    public static func countdownSeconds(until target: Date, serverNow: Date) -> Int {
        max(0, Int(target.timeIntervalSince(serverNow).rounded(.down)))
    }

    public static func formatCountdown(seconds: Int) -> String {
        let s = max(0, seconds)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if d > 0 { return String(format: "%d天%02d:%02d:%02d", d, h, m, sec) }
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    public static func payDeadlineCountdownLine(seconds: Int) -> String {
        "\(formatCountdown(seconds: seconds)) · \(LotteryCopy.serverTimeHint)"
    }

    public static func isPayRemindWindow(
        now: Date,
        payDeadline: Date,
        remindSec: Int = LotteryConfigDefaults.n12RemindSec
    ) -> Bool {
        let remaining = payDeadline.timeIntervalSince(now)
        return remaining > 0 && remaining <= TimeInterval(remindSec)
    }

    public static func isPayOverdue(now: Date, payDeadline: Date?) -> Bool {
        guard let payDeadline else { return false }
        return payDeadline.timeIntervalSince(now) <= 0
    }

    public static func enrollChecklist(
        isLoggedIn: Bool,
        eligibility: LotteryEligibility?,
        hasAddress: Bool
    ) -> [LotteryEnrollChecklistItem] {
        [
            LotteryEnrollChecklistItem(step: .login, done: isLoggedIn),
            LotteryEnrollChecklistItem(step: .realName, done: eligibility?.isRealNamed == true),
            LotteryEnrollChecklistItem(step: .credit, done: eligibility?.isCreditOk == true),
            LotteryEnrollChecklistItem(step: .deposit, done: eligibility?.isDepositFrozen == true),
            LotteryEnrollChecklistItem(
                step: .address,
                done: hasAddress || eligibility?.addressReady == true
            ),
        ]
    }

    public static func nextEnrollStep(
        isLoggedIn: Bool,
        eligibility: LotteryEligibility?,
        hasAddress: Bool
    ) -> LotteryEnrollStep? {
        enrollChecklist(isLoggedIn: isLoggedIn, eligibility: eligibility, hasAddress: hasAddress)
            .first { !$0.done }?
            .step
    }

    public static func enrollReady(
        isLoggedIn: Bool,
        eligibility: LotteryEligibility?,
        hasAddress: Bool
    ) -> Bool {
        nextEnrollStep(isLoggedIn: isLoggedIn, eligibility: eligibility, hasAddress: hasAddress) == nil
    }

    public static func isEnrollOpen(_ detail: LotteryReleaseDetail, serverNow: Date) -> Bool {
        if let status = detail.status, !status.allowsEnroll {
            // enroll_scheduled / draft may still be gated by start_at below.
            if status != .enrollScheduled && status != .draft {
                return false
            }
        }
        if let start = detail.enrollStartAt, let end = detail.enrollEndAt {
            // Boundary: now == end allowed (design §10).
            return serverNow >= start && serverNow <= end
        }
        return detail.status == .enrolling
    }

    public static func resolveReleaseCTA(
        detail: LotteryReleaseDetail,
        serverNow: Date,
        isLoggedIn: Bool,
        hasAddress: Bool
    ) -> LotteryCTA {
        if let mine = detail.myEntry {
            return resolveEntryCTA(entry: mine, releaseStatus: detail.status, serverNow: serverNow)
        }
        if detail.eligibility?.hasEntered == true {
            let stub = LotteryEntry(
                id: detail.eligibility?.entryId ?? 0,
                releaseId: detail.id,
                status: .registered
            )
            return resolveEntryCTA(entry: stub, releaseStatus: detail.status, serverNow: serverNow)
        }

        let status = detail.status
        if status == .completed { return .ended }
        if status?.isDrawingInProgress == true { return .drawing }
        if status == .drawn { return .viewProof }
        if status == .enrollClosed { return .enrollClosed }

        if let start = detail.enrollStartAt, serverNow < start {
            return isLoggedIn ? .waitEnrollOpen : .login
        }

        if !isEnrollOpen(detail, serverNow: serverNow) {
            if status == .enrollScheduled || (detail.enrollStartAt.map { serverNow < $0 } == true) {
                return isLoggedIn ? .waitEnrollOpen : .login
            }
            return .enrollClosed
        }

        if !isLoggedIn { return .login }

        if !enrollReady(isLoggedIn: isLoggedIn, eligibility: detail.eligibility, hasAddress: hasAddress) {
            return .completeEligibility
        }

        return .enroll
    }

    public static func resolveEntryCTA(
        entry: LotteryEntry,
        releaseStatus: LotteryReleaseStatus? = nil,
        serverNow: Date = Date()
    ) -> LotteryCTA {
        switch entry.resolvedStatus {
        case .registered:
            if releaseStatus?.isDrawingInProgress == true { return .drawing }
            if releaseStatus == .drawn || releaseStatus == .completed { return .viewProof }
            return .enrolledWaiting
        case .won:
            if isPayOverdue(now: serverNow, payDeadline: entry.payDeadline) {
                return .forfeited
            }
            return .pay
        case .waitlisted:
            return .waitlist
        case .lost:
            return .lost
        case .paid:
            return .paid
        case .forfeited:
            return .forfeited
        }
    }

    public static func waitlistPositionLine(rank: Int?, remainingUnpaid: Int?) -> String {
        var parts: [String] = []
        if let rank, rank > 0 {
            parts.append("\(LotteryCopy.waitlistPositionPrefix) \(rank)")
        }
        if let remainingUnpaid, remainingUnpaid >= 0 {
            parts.append("\(LotteryCopy.remainingUnpaidPrefix) \(remainingUnpaid)")
        }
        return parts.isEmpty ? LotteryCopy.waitlist : parts.joined(separator: " · ")
    }

    public static func formatYuan(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 {
            return String(format: "%.0f", yuan)
        }
        return String(format: "%.2f", yuan)
    }

    public static func deviceAttestation(vendorId: String?) -> LotteryDeviceAttestation {
        let trimmed = vendorId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return LotteryDeviceAttestation(vendorId: trimmed, platform: "ios", empty: false)
        }
        return LotteryDeviceAttestation(vendorId: nil, platform: "ios", empty: true)
    }
}
