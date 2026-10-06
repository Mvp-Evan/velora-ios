import Foundation

/// 金额单位：分
typealias Money = Int64

extension Money {
    var yuan: Double { Double(self) / 100 }
    /// ¥1,234 或 ¥1,234.50
    var display: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = self % 100 == 0 ? 0 : 2
        f.maximumFractionDigits = 2
        return "¥" + (f.string(from: NSNumber(value: yuan)) ?? "\(yuan)")
    }
    var displayNoSymbol: String { String(display.dropFirst()) }
    var displayFixed: String { String(format: "¥%.2f", yuan) }
}

// MARK: - Envelope / Paging

struct Envelope<T: Decodable>: Decodable {
    let data: T?
    let error: APIErrorBody?
}

struct APIErrorBody: Decodable, Error {
    let code: String
    let message: String
}

struct Page<T: Decodable>: Decodable {
    var items: [T]
    let page: Int
    let pageSize: Int
    let total: Int
    let hasMore: Bool
}

struct Empty: Decodable {}

// MARK: - User

struct User: Codable, Identifiable, Hashable {
    let id: Int64
    var nickname: String
    var avatar: String
    var bio: String?
    var location: String?
    var creditScore: Int
    var soldCount: Int
    var wonCount: Int
    var lotCount: Int
    var phoneMasked: String?
    var createdAt: Date?
}

struct TokenPair: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: User
    let isNew: Bool
}

struct Address: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var name: String
    var phone: String
    var province: String
    var city: String
    var district: String
    var detail: String
    var isDefault: Bool

    var oneLine: String { "\(province)\(city)\(district)\(detail)" }
    static let blank = Address(name: "", phone: "", province: "", city: "", district: "", detail: "", isDefault: false)
}

// MARK: - Lot

enum LotStatus: String, Codable {
    case draft, scheduled, live, ended, unsold, cancelled

    var label: String {
        switch self {
        case .draft: return "草稿"
        case .scheduled: return "预展中"
        case .live: return "竞拍中"
        case .ended: return "已结拍"
        case .unsold: return "流拍"
        case .cancelled: return "已撤拍"
        }
    }
}

struct MyBidStatus: Codable, Hashable {
    var hasBid: Bool = false
    var leading: Bool = false
    var maxAmount: Money = 0
}

struct Lot: Codable, Identifiable, Hashable {
    let id: Int64
    var sellerId: Int64
    var title: String
    var description: String
    var images: [String]
    var category: String
    var brand: String
    var scale: String
    var series: String
    var condition: String
    var boxStatus: String
    var location: String
    var startPrice: Money
    var depositAmount: Money
    var bidIncrement: Money
    var currentPrice: Money
    var currentBidderId: Int64?
    var bidCount: Int
    var startAt: Date
    var endAt: Date
    var durationSeconds: Int
    var antiSnipeSeconds: Int
    var extensionCount: Int
    var status: LotStatus
    var followCount: Int
    var viewCount: Int
    var winnerId: Int64?
    var orderId: Int64?
    var createdAt: Date

    var seller: User
    var currentBidder: User?
    var cover: String
    var displayPrice: Money
    var minNextBid: Money
    var isFollowing: Bool
    var myBid: MyBidStatus
    var recentBids: [Bid]?
    var hasReserve: Bool
    var reserveMet: Bool

    var isLive: Bool { status == .live }
    var isUpcoming: Bool { status == .scheduled }
    var isFinished: Bool { status == .ended || status == .unsold || status == .cancelled }
    var tags: [String] { [scale, brand, condition].filter { !$0.isEmpty } }
}

struct Bid: Codable, Identifiable, Hashable {
    let id: Int64
    let lotId: Int64
    let bidderId: Int64
    let amount: Money
    let createdAt: Date
    var leading: Bool
    var bidder: User?

    var bidderName: String { bidder?.nickname ?? "出价者\(bidderId % 1000)" }
    var bidderAvatar: String { bidder?.avatar ?? "" }
}

// MARK: - Order

enum OrderStatus: String, Codable {
    case pendingPayment = "pending_payment"
    case paid, shipped, completed, cancelled, refunded

    var label: String {
        switch self {
        case .pendingPayment: return "待付款"
        case .paid: return "待发货"
        case .shipped: return "待收货"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        case .refunded: return "已退款"
        }
    }
}

struct TimelineEvent: Codable, Hashable {
    let status: String
    let title: String
    let note: String?
    let at: Date
}

struct LotBrief: Codable, Hashable {
    let id: Int64
    let title: String
    let cover: String
    let scale: String
    let brand: String
}

struct Order: Codable, Identifiable, Hashable {
    let id: Int64
    let orderNo: String
    let lotId: Int64
    let buyerId: Int64
    let sellerId: Int64
    let hammerPrice: Money
    let buyerPremium: Money
    let buyerTotal: Money
    let sellerCommission: Money
    let sellerNet: Money
    var depositApplied: Money = 0
    var amountDue: Money = 0
    var status: OrderStatus
    let payDeadline: Date
    var paidAt: Date?
    var shippedAt: Date?
    var completedAt: Date?
    var address: [String: String]?
    var shippingCarrier: String?
    var trackingNo: String?
    var timeline: [TimelineEvent]
    let createdAt: Date
    var lot: LotBrief?
    var buyer: User
    var seller: User
    var role: String

    var isSeller: Bool { role == "seller" }
    var hasAddress: Bool { !(address?["name"] ?? "").isEmpty }
    /// 实际应付（押金抵扣后）；旧数据无字段时回退到 buyerTotal
    var payAmount: Money { amountDue > 0 || depositApplied > 0 ? amountDue : buyerTotal }
    var addressLine: String {
        guard let a = address else { return "" }
        return (a["province"] ?? "") + (a["city"] ?? "") + (a["district"] ?? "") + (a["detail"] ?? "")
    }
}

struct OrderDetail: Decodable {
    let order: Order
    let payments: [Payment]
}

// MARK: - Payment

enum PaymentStatus: String, Codable { case created, paying, succeeded, failed, closed, refunded }

struct Payment: Codable, Identifiable, Hashable {
    let id: Int64
    let orderId: Int64
    let provider: String
    let outTradeNo: String
    let amount: Money
    var status: PaymentStatus
    var clientPayload: [String: AnyCodable]?
    var failReason: String?
    var paidAt: Date?
}

struct PaymentMethod: Codable, Identifiable, Hashable {
    var id: String { provider }
    let provider: String
    let name: String
    let description: String
    let icon: String
    let enabled: Bool
}

// MARK: - Commission / Wallet / Tax

struct FeeBreakdown: Codable, Hashable {
    let hammerPrice: Money
    let buyerPremium: Money
    let buyerTotal: Money
    let sellerCommission: Money
    let sellerNet: Money
    let ruleName: String
    let sellerRateBp: Int
    let buyerPremiumBp: Int

    var sellerRateText: String { String(format: "%.1f%%", Double(sellerRateBp) / 100) }
}

struct Wallet: Codable, Hashable {
    let availableBalance: Money
    let pendingBalance: Money
    let totalIncome: Money
    let totalWithdrawn: Money
}

struct LedgerEntry: Codable, Identifiable, Hashable {
    let id: Int64
    let journalId: String
    let orderId: Int64?
    let account: String
    let direction: String
    let amount: Money
    let memo: String
    let createdAt: Date

    var accountLabel: String {
        switch account {
        case "seller_payable": return "在途货款"
        case "seller_wallet": return "钱包入账"
        case "tax_withheld": return "税费预提"
        case "withdrawal": return "提现"
        case "buyer_payment": return "付款"
        default: return account
        }
    }
    /// 对用户而言是否为收入
    var isIncome: Bool { account == "seller_wallet" && direction == "credit" || account == "seller_payable" && direction == "credit" }
}

struct WithdrawalRequest: Codable, Identifiable, Hashable {
    let id: Int64
    let amount: Money
    let status: String
    let note: String?
    let createdAt: Date
    let bankAccount: [String: String]?

    var statusLabel: String {
        switch status {
        case "pending": return "审核中"
        case "approved": return "已审核"
        case "paid": return "已到账"
        case "rejected": return "已驳回"
        default: return status
        }
    }
}

enum TaxpayerType: String, Codable, CaseIterable, Identifiable {
    case individual, soleProprietor = "sole_proprietor", enterprise
    var id: String { rawValue }
    var label: String {
        switch self {
        case .individual: return "自然人"
        case .soleProprietor: return "个体工商户"
        case .enterprise: return "企业"
        }
    }
}

struct TaxProfile: Codable, Hashable {
    let taxpayerType: TaxpayerType
    let realName: String
    let idType: String
    let idNumberMasked: String?
    let uscc: String?
    let taxRegion: String
    let bankName: String?
    let bankAccountMasked: String?
    let verifiedAt: Date?
}

struct TaxRecord: Codable, Identifiable, Hashable {
    let id: Int64
    let orderId: Int64
    let incomeType: String
    let grossIncome: Money
    let platformFee: Money
    let netIncome: Money
    let vatApplicable: Bool
    let withheldAmount: Money
    let period: String
    let quarter: String
    let settledAt: Date

    var incomeTypeLabel: String { incomeType == "business" ? "经营所得" : "财产转让所得" }
}

struct TaxReport: Codable, Identifiable, Hashable {
    let id: Int64
    let quarter: String
    let recordsCount: Int
    let totalIncome: Money
    let totalFee: Money
    let totalNet: Money
    let totalWithheld: Money
    let status: String
    let submissionRef: String?
    let submittedAt: Date?

    var statusLabel: String {
        switch status {
        case "draft": return "草稿"
        case "generated": return "已生成"
        case "submitted": return "已报送"
        case "accepted": return "已受理"
        case "rejected": return "被退回"
        default: return status
        }
    }
}

// MARK: - Chat

struct LotSummary: Codable, Hashable {
    let id: Int64
    let title: String
    let cover: String
    let currentPrice: Money
    let status: LotStatus
    let endAt: Date
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: Int64
    let lotId: Int64
    let buyerId: Int64
    let sellerId: Int64
    var lastMessage: String
    var lastMessageAt: Date?
    let peer: User
    let lot: LotSummary?
    var unread: Int
}

enum MessageType: String, Codable { case text, image, lotCard = "lot_card", system }

struct Message: Codable, Identifiable, Hashable {
    let id: Int64
    let conversationId: Int64
    let senderId: Int64
    let type: MessageType
    let content: String
    let payload: [String: AnyCodable]?
    let createdAt: Date
}

// MARK: - Meta

struct SortOption: Codable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let name: String
}

struct Filters: Codable {
    let categories: [String]
    let brands: [String]
    let scales: [String]
    let series: [String]
    let conditions: [String]
    let boxStatus: [String]
    let durations: [Int]
    let sorts: [SortOption]
    let hotKeywords: [String]

    static let empty = Filters(categories: [], brands: [], scales: [], series: [], conditions: [], boxStatus: [], durations: [], sorts: [], hotKeywords: [])
}

// MARK: - AnyCodable (for free-form payloads)

struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int64.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues(\.value) }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let b as Bool: try c.encode(b)
        case let i as Int64: try c.encode(i)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        default: try c.encodeNil()
        }
    }

    static func == (l: AnyCodable, r: AnyCodable) -> Bool { "\(l.value)" == "\(r.value)" }
    func hash(into h: inout Hasher) { h.combine("\(value)") }

    var string: String? { value as? String }
    var int64: Int64? { (value as? Int64) ?? (value as? Int).map(Int64.init) ?? (value as? Double).map(Int64.init) }
    var bool: Bool? { value as? Bool }
}
