import Foundation

// MARK: - Listing detail / Q&A / photo-request (DES-v1.3-02-04) — app mirror of VeloraCore

// MARK: - Listing detail / Q&A / photo-request (DES-v1.3-02-04 / ITEM-01～06)

/// Stable detail / Q&A / 补图 error codes (DES §6).
enum ListingDetailErrorCode: String, Codable, Sendable, CaseIterable {
    case loginRequired = "login_required"
    case realNameRequired = "real_name_required"
    case accountFrozen = "account_frozen"
    case qaLocked = "qa_locked"
    case questionLimitExceeded = "question_limit_exceeded"
    case contactInfoForbidden = "contact_info_forbidden"
    case imageImmutable = "image_immutable"
    case photoRequestLocked = "photo_request_locked"
    case cannotAskSelf = "cannot_ask_self"
    case watermarkRequired = "watermark_required"
    case cameraRequired = "camera_required"
    case questionAnswered = "question_answered"
    case listingNotPublic = "listing_not_public"
    case rateLimited = "rate_limited"
    case reserveHidden = "reserve_hidden"

    var fallbackMessage: String {
        switch self {
        case .loginRequired: return "去登录"
        case .realNameRequired: return "去实名"
        case .accountFrozen: return "账号已冻结，请联系客服"
        case .qaLocked: return "已结束，问答已关闭"
        case .questionLimitExceeded: return "每个商品最多提问 5 条"
        case .contactInfoForbidden: return "含联系方式"
        case .imageImmutable: return "有出价后原图不可删除"
        case .photoRequestLocked: return "商品已结束，无法再请求补图"
        case .cannotAskSelf: return "不能向自己的商品提问"
        case .watermarkRequired: return "补图须带水印"
        case .cameraRequired: return "补图请使用 App 内相机拍摄"
        case .questionAnswered: return "已回答的提问不可删除"
        case .listingNotPublic: return "该商品已退出公开检索"
        case .rateLimited: return "操作过于频繁，请稍后再试"
        case .reserveHidden: return "保留价金额不可见"
        }
    }
}

enum ListingTradeType: String, Codable, Sendable, CaseIterable {
    case auction
    case fixed
    case release

    var detailTemplate: ListingDetailTemplate {
        switch self {
        case .auction: return .auction
        case .fixed: return .direct
        case .release: return .release
        }
    }
}

/// Client template selector (auction / 直购 / 发售).
enum ListingDetailTemplate: String, Codable, Sendable, CaseIterable {
    case auction
    case direct
    case release
}

/// ITEM-02 condition grades.
enum ListingConditionGrade: String, Codable, Sendable, CaseIterable {
    case newSealed = "new_sealed"
    case unpackedMint = "unpacked_mint"
    case flawed

    var label: String {
        switch self {
        case .newSealed: return "全新未拆"
        case .unpackedMint: return "已拆无瑕"
        case .flawed: return "有瑕疵"
        }
    }

    /// Maps enum + legacy Chinese filter labels onto ITEM-02.
    static func normalize(_ raw: String?) -> ListingConditionGrade? {
        guard let raw, !raw.isEmpty else { return nil }
        if let g = ListingConditionGrade(rawValue: raw) { return g }
        switch raw {
        case "全新未拆": return .newSealed
        case "已拆无瑕", "99新", "95新": return .unpackedMint
        case "有瑕疵", "9成新", "8成新": return .flawed
        default: return nil
        }
    }

    static func displayLabel(_ raw: String?) -> String {
        if let g = normalize(raw) { return g.label }
        return raw ?? ""
    }
}

enum ListingImageRole: String, Codable, Sendable, CaseIterable {
    case cover
    case gallery
    case flaw
    case supplement
}

enum ListingQuestionStatus: String, Codable, Sendable, CaseIterable {
    case pendingMod = "pending_mod"
    case visible
    case rejected
    case locked
}

enum PhotoRequestStatus: String, Codable, Sendable, CaseIterable {
    case open
    case merged
    case fulfilled
    case closed
}

enum PhotoRequestPart: String, Codable, Sendable, CaseIterable, Hashable {
    case front, back, side, chassis, box, flaw, other

    var title: String {
        switch self {
        case .front: return "正面"
        case .back: return "背面"
        case .side: return "侧面"
        case .chassis: return "底盘"
        case .box: return "包装盒"
        case .flaw: return "瑕疵处"
        case .other: return "其他"
        }
    }
}

enum ListingDetailLimits {
    static let maxQuestionsPerListingUser = 5
    static let maxQuestionRunes = 200
    static let maxQuestionsPerMinute = 3
    static let flawDescCollapseRunes = 80
    static let photoSourceInAppCamera = "in_app_camera"
    static let watermarkBrand = "毂毂"
    static let questionsPageSize = 10
    static let bidsPageSize = 20
}

/// Rules snapshot frozen at list-time (DES §5.1).
struct ListingRulesSnapshot: Codable, Equatable, Sendable {
    let depositRule: String?
    let payDeadlineHours: Int?
    let shipDeadlineHours: Int?
    let afterSaleHours: Int?
    let feeNote: String?
    /// Optional deposit amount (fen) already computed for this lot.
    let depositAmount: Int64?

    init(
        depositRule: String? = nil,
        payDeadlineHours: Int? = nil,
        shipDeadlineHours: Int? = nil,
        afterSaleHours: Int? = nil,
        feeNote: String? = nil,
        depositAmount: Int64? = nil
    ) {
        self.depositRule = depositRule
        self.payDeadlineHours = payDeadlineHours
        self.shipDeadlineHours = shipDeadlineHours
        self.afterSaleHours = afterSaleHours
        self.feeNote = feeNote
        self.depositAmount = depositAmount
    }

    var summaryLines: [String] {
        var lines: [String] = []
        if let depositAmount, depositAmount > 0 {
            let yuan = Double(depositAmount) / 100
            lines.append(String(format: "保证金约 %.0f 元起", yuan))
        } else if let depositRule, !depositRule.isEmpty {
            lines.append(depositRule)
        }
        if let h = payDeadlineHours { lines.append("拍中后 \(h) 小时内付款") }
        if let h = shipDeadlineHours { lines.append("卖家付款后 \(h) 小时内发货") }
        if let h = afterSaleHours { lines.append("售后协商窗口 \(h) 小时") }
        if let feeNote, !feeNote.isEmpty { lines.append(feeNote) }
        return lines
    }
}

struct ListingImage: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let url: String
    let role: ListingImageRole
    let immutable: Bool
    let watermarked: Bool
    let sortOrder: Int?

    init(
        id: Int64,
        url: String,
        role: ListingImageRole = .gallery,
        immutable: Bool = false,
        watermarked: Bool = false,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.role = role
        self.immutable = immutable
        self.watermarked = watermarked
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        url = try c.decode(String.self, forKey: .url)
        let roleRaw = try c.decodeIfPresent(String.self, forKey: .role) ?? ListingImageRole.gallery.rawValue
        role = ListingImageRole(rawValue: roleRaw) ?? .gallery
        immutable = try c.decodeIfPresent(Bool.self, forKey: .immutable) ?? false
        watermarked = try c.decodeIfPresent(Bool.self, forKey: .watermarked) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
    }

    enum CodingKeys: String, CodingKey {
        case id, url, role, immutable, watermarked, sortOrder
    }
}

struct ListingQuestion: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let listingId: Int64
    let askerId: Int64
    let content: String
    let answer: String?
    let answeredAt: Date?
    let status: ListingQuestionStatus
    let rejectReason: String?
    let version: Int64
    let createdAt: Date?
    let askerNickname: String?

    init(
        id: Int64,
        listingId: Int64,
        askerId: Int64,
        content: String,
        answer: String? = nil,
        answeredAt: Date? = nil,
        status: ListingQuestionStatus = .pendingMod,
        rejectReason: String? = nil,
        version: Int64 = 1,
        createdAt: Date? = nil,
        askerNickname: String? = nil
    ) {
        self.id = id
        self.listingId = listingId
        self.askerId = askerId
        self.content = content
        self.answer = answer
        self.answeredAt = answeredAt
        self.status = status
        self.rejectReason = rejectReason
        self.version = version
        self.createdAt = createdAt
        self.askerNickname = askerNickname
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId) ?? 0
        askerId = try c.decodeIfPresent(Int64.self, forKey: .askerId) ?? 0
        content = try c.decode(String.self, forKey: .content)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        answeredAt = try c.decodeIfPresent(Date.self, forKey: .answeredAt)
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? ListingQuestionStatus.visible.rawValue
        status = ListingQuestionStatus(rawValue: statusRaw) ?? .visible
        rejectReason = try c.decodeIfPresent(String.self, forKey: .rejectReason)
        version = try c.decodeIfPresent(Int64.self, forKey: .version) ?? 1
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        askerNickname = try c.decodeIfPresent(String.self, forKey: .askerNickname)
    }

    enum CodingKeys: String, CodingKey {
        case id, content, answer, status, version
        case listingId, askerId, answeredAt, rejectReason, createdAt, askerNickname
    }

    var isVisibleToPublic: Bool { status == .visible || status == .locked }
    var isPending: Bool { status == .pendingMod }
    var isRejected: Bool { status == .rejected }
    var hasAnswer: Bool { !(answer ?? "").isEmpty }
}

struct PhotoRequestRow: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let listingId: Int64
    let part: PhotoRequestPart
    let status: PhotoRequestStatus
    let count: Int
    let fulfilledAt: Date?

    init(
        id: Int64,
        listingId: Int64,
        part: PhotoRequestPart,
        status: PhotoRequestStatus = .open,
        count: Int = 1,
        fulfilledAt: Date? = nil
    ) {
        self.id = id
        self.listingId = listingId
        self.part = part
        self.status = status
        self.count = count
        self.fulfilledAt = fulfilledAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId) ?? 0
        let partRaw = try c.decode(String.self, forKey: .part)
        part = PhotoRequestPart(rawValue: partRaw) ?? .other
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? PhotoRequestStatus.open.rawValue
        status = PhotoRequestStatus(rawValue: statusRaw) ?? .open
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        fulfilledAt = try c.decodeIfPresent(Date.self, forKey: .fulfilledAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, part, status, count, listingId, fulfilledAt
    }

    /// UX copy:「3 人想看底盘」
    var progressText: String {
        "\(count) 人想看\(part.title)"
    }
}

/// Public listing detail payload (DES §5.1 / §6). Optional D10 fields decode when present.
struct ListingDetail: Decodable, Equatable, Sendable, Identifiable {
    let id: Int64
    let sellerId: Int64
    /// Optional seller chip (DES-v1.3-05-01); absent on legacy payloads.
    let sellerBadge: SellerBadge?
    let tradeType: String
    let title: String
    let brand: String?
    let series: String?
    let model: String?
    let scale: String?
    let condition: String
    let description: String?
    let images: [ListingImage]
    let imageURLs: [String]
    let price: Int64
    let stock: Int
    let status: String
    let soldAt: Date?
    let soldPricePublic: Int64?
    let soldCount: Int?
    let version: Int64
    let negotiable: Bool
    let freeShipping: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let flawDesc: String?
    let flawImages: [ListingImage]
    let rulesSnapshot: ListingRulesSnapshot?
    let questions: [ListingQuestion]
    let photoRequests: [PhotoRequestRow]
    let qaLocked: Bool
    let conditionIncomplete: Bool
    let viewers: Int?
    let favoriteCount: Int?
    let isFavorited: Bool
    let hasReserve: Bool?
    let reserveMet: Bool?
    let lotId: Int64?
    let releaseMode: String?
    let releaseStatus: String?
    let releaseStartsAt: Date?
    /// Spot / lottery / presale release id when `trade_type=release` (DES-v1.3-06-01).
    let releaseId: Int64?
    /// Seller-only extras (must stay absent on buyer paths — tested separately).
    let reservePriceOwn: Int64?
    let costPrice: Int64?

    var trade: ListingTradeType { ListingTradeType(rawValue: tradeType) ?? .fixed }
    var template: ListingDetailTemplate { trade.detailTemplate }
    var conditionGrade: ListingConditionGrade? { ListingConditionGrade.normalize(condition) }
    var conditionLabel: String { ListingConditionGrade.displayLabel(condition) }

    var galleryURLs: [String] {
        let structured = images
            .filter { $0.role == .cover || $0.role == .gallery || $0.role == .supplement }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            .map(\.url)
        if !structured.isEmpty { return structured }
        return imageURLs
    }

    var flawImageURLs: [String] {
        let fromRole = images.filter { $0.role == .flaw }.map(\.url)
        if !fromRole.isEmpty { return fromRole }
        return flawImages.map(\.url)
    }

    var showsFlawSection: Bool {
        conditionGrade == .flawed || !flawImageURLs.isEmpty || !(flawDesc ?? "").isEmpty
    }

    var canPurchase: Bool { !conditionIncomplete && stock > 0 && status != "sold" && status != "off_shelf" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        sellerId = try c.decodeIfPresent(Int64.self, forKey: .sellerId) ?? 0
        sellerBadge = try c.decodeIfPresent(SellerBadge.self, forKey: .sellerBadge)
        tradeType = try c.decodeIfPresent(String.self, forKey: .tradeType) ?? "fixed"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        series = try c.decodeIfPresent(String.self, forKey: .series)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        scale = try c.decodeIfPresent(String.self, forKey: .scale)
        condition = try c.decodeIfPresent(String.self, forKey: .condition) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        price = try c.decodeIfPresent(Int64.self, forKey: .price) ?? 0
        stock = try c.decodeIfPresent(Int.self, forKey: .stock) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        soldAt = try c.decodeIfPresent(Date.self, forKey: .soldAt)
        soldPricePublic = try c.decodeIfPresent(Int64.self, forKey: .soldPricePublic)
        soldCount = try c.decodeIfPresent(Int.self, forKey: .soldCount)
        version = try c.decodeIfPresent(Int64.self, forKey: .version) ?? 1
        negotiable = try c.decodeIfPresent(Bool.self, forKey: .negotiable) ?? false
        freeShipping = try c.decodeIfPresent(Bool.self, forKey: .freeShipping)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        flawDesc = try c.decodeIfPresent(String.self, forKey: .flawDesc)
        rulesSnapshot = try c.decodeIfPresent(ListingRulesSnapshot.self, forKey: .rulesSnapshot)
        questions = try c.decodeIfPresent([ListingQuestion].self, forKey: .questions) ?? []
        photoRequests = try c.decodeIfPresent([PhotoRequestRow].self, forKey: .photoRequests) ?? []
        qaLocked = try c.decodeIfPresent(Bool.self, forKey: .qaLocked) ?? false
        conditionIncomplete = try c.decodeIfPresent(Bool.self, forKey: .conditionIncomplete) ?? false
        viewers = try c.decodeIfPresent(Int.self, forKey: .viewers)
        favoriteCount = try c.decodeIfPresent(Int.self, forKey: .favoriteCount)
        isFavorited = try c.decodeIfPresent(Bool.self, forKey: .isFavorited)
            ?? c.decodeIfPresent(Bool.self, forKey: .favorited)
            ?? false
        hasReserve = try c.decodeIfPresent(Bool.self, forKey: .hasReserve)
        reserveMet = try c.decodeIfPresent(Bool.self, forKey: .reserveMet)
        releaseMode = try c.decodeIfPresent(String.self, forKey: .releaseMode)
        releaseStatus = try c.decodeIfPresent(String.self, forKey: .releaseStatus)
        releaseStartsAt = try c.decodeIfPresent(Date.self, forKey: .releaseStartsAt)
        releaseId = try c.decodeIfPresent(Int64.self, forKey: .releaseId)
        reservePriceOwn = try c.decodeIfPresent(Int64.self, forKey: .reservePriceOwn)
        costPrice = try c.decodeIfPresent(Int64.self, forKey: .costPrice)

        // images may be [ListingImage] or [String] (legacy).
        if let objs = try? c.decode([ListingImage].self, forKey: .images) {
            images = objs
            imageURLs = objs.map(\.url)
        } else if let urls = try? c.decode([String].self, forKey: .images) {
            imageURLs = urls
            images = urls.enumerated().map {
                ListingImage(id: Int64($0.offset), url: $0.element, role: $0.offset == 0 ? .cover : .gallery, sortOrder: $0.offset)
            }
        } else {
            images = []
            imageURLs = []
        }

        if let flaws = try? c.decode([ListingImage].self, forKey: .flawImages) {
            flawImages = flaws
        } else if let urls = try? c.decode([String].self, forKey: .flawImages) {
            flawImages = urls.enumerated().map {
                ListingImage(id: Int64(10_000 + $0.offset), url: $0.element, role: .flaw, sortOrder: $0.offset)
            }
        } else {
            flawImages = []
        }

        // Nested auction lot (current server shape).
        if let lot = try c.decodeIfPresent(NestedLot.self, forKey: .lot) {
            lotId = lot.id
        } else {
            lotId = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, brand, series, model, scale, condition, description, images, price, stock, status, version
        case negotiable, sellerId, sellerBadge, tradeType, soldAt, soldPricePublic, soldCount, freeShipping
        case createdAt, updatedAt, flawDesc, flawImages, rulesSnapshot, questions, photoRequests
        case qaLocked, conditionIncomplete, viewers, favoriteCount, isFavorited, favorited
        case hasReserve, reserveMet, lotId, lot, releaseMode, releaseStatus, releaseStartsAt, releaseId
        case reservePriceOwn, costPrice
    }

    private struct NestedLot: Decodable {
        let id: Int64
    }
}

struct ListingQuestionsPage: Codable, Equatable, Sendable {
    let items: [ListingQuestion]
    let page: Int?
    let pageSize: Int?
    let total: Int?
    let hasMore: Bool?
    let qaLocked: Bool?

    init(
        items: [ListingQuestion],
        page: Int? = nil,
        pageSize: Int? = nil,
        total: Int? = nil,
        hasMore: Bool? = nil,
        qaLocked: Bool? = nil
    ) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.hasMore = hasMore
        self.qaLocked = qaLocked
    }
}

struct PhotoRequestsResponse: Codable, Equatable, Sendable {
    let items: [PhotoRequestRow]

    init(items: [PhotoRequestRow]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([PhotoRequestRow].self) {
            items = arr
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([PhotoRequestRow].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey { case items }
}

// MARK: - Validators / copy helpers

enum ListingQAValidator {
    /// Client preflight matching DES §5.5 order (length + contact). Server still authoritative.
    static func validateQuestion(_ content: String, alreadyAsked: Int) -> ListingDetailErrorCode? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if alreadyAsked >= ListingDetailLimits.maxQuestionsPerListingUser {
            return .questionLimitExceeded
        }
        if trimmed.count > ListingDetailLimits.maxQuestionRunes {
            return .questionLimitExceeded
        }
        if ListingQAContactGuard.containsContactInfo(trimmed) {
            return .contactInfoForbidden
        }
        return nil
    }
}

/// Q&A contact / 引流 guard (DES §5.5 / T-07). Extends shortcut patterns with QQ / URL / 加微.
enum ListingQAContactGuard {
    private static let phonePattern = try! NSRegularExpression(
        pattern: #"(?:\+?86)?1[3-9]\d{9}|\d{3,4}-?\d{7,8}"#
    )
    private static let wechatPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:微信(?:号)?|wx|wechat|v信|薇信|加微|加微信)[:：\s\-]*[a-zA-Z0-9_\-]{0,20}"#
    )
    private static let qqPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:qq|扣扣)[:：\s\-]*\d{5,12}"#
    )
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:https?://|www\.)[^\s]+"#
    )

    static func containsContactInfo(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        if phonePattern.firstMatch(in: s, range: range) != nil { return true }
        if wechatPattern.firstMatch(in: s, range: range) != nil { return true }
        if qqPattern.firstMatch(in: s, range: range) != nil { return true }
        if urlPattern.firstMatch(in: s, range: range) != nil { return true }
        return false
    }
}

enum ListingReserveCopy {
    /// Buyer-facing three-state copy only (DES §5.3 / §9). Never「差 xx 到达」.
    static func text(hasReserve: Bool?, reserveMet: Bool?) -> String? {
        guard let hasReserve else { return nil }
        if !hasReserve { return "无保留价" }
        if reserveMet == true { return "已达保留价" }
        return "有保留价"
    }
}

enum ListingWatermark {
    /// Preview / compose watermark line (DES §5.6). Server re-applies on upload.
    static func line(shortCode: String, date: Date, shooterIdSuffix: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(ListingDetailLimits.watermarkBrand) \(shortCode) \(fmt.string(from: date)) \(shooterIdSuffix)"
    }

    static func shortCode(listingId: Int64) -> String {
        String(format: "%04X", listingId & 0xFFFF)
    }

    static func idSuffix(_ userId: Int64) -> String {
        String(format: "%04d", abs(userId) % 10_000)
    }
}

/// Schema helper used by tests: buyer detail JSON must not expose reserved keys.
enum ListingDetailBuyerSchema {
    static let forbiddenKeys: Set<String> = [
        "reserve_price",
        "cost_price",
        "phone",
        "wechat",
        "qr_code",
    ]

    static func leakedKeys(in jsonObject: Any) -> [String] {
        var found: [String] = []
        walk(jsonObject, path: "", into: &found)
        return found
    }

    private static func walk(_ node: Any, path: String, into found: inout [String]) {
        if let dict = node as? [String: Any] {
            for (k, v) in dict {
                let next = path.isEmpty ? k : "\(path).\(k)"
                if forbiddenKeys.contains(k) { found.append(next) }
                walk(v, path: next, into: &found)
            }
        } else if let arr = node as? [Any] {
            for (i, v) in arr.enumerated() {
                walk(v, path: "\(path)[\(i)]", into: &found)
            }
        }
    }
}
