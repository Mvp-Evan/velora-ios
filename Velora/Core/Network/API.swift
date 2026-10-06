import Foundation

/// 按领域组织的类型化接口
enum API {
    private static var c: APIClient { .shared }

    // MARK: Auth
    static func sendSms(phone: String) async throws -> [String: AnyCodable] {
        try await c.request(.POST, "auth/sms", body: .json(JSONDict(["phone": phone])), auth: false)
    }
    static func login(phone: String, code: String) async throws -> TokenPair {
        try await c.request(.POST, "auth/login", body: .json(JSONDict(["phone": phone, "code": code])), auth: false)
    }
    static func refresh(_ token: String) async throws -> TokenPair {
        try await c.request(.POST, "auth/refresh", body: .json(JSONDict(["refresh_token": token])), auth: false, retry: false)
    }
    static func logout(_ token: String) async { _ = try? await c.request(.POST, "auth/logout", body: .json(JSONDict(["refresh_token": token]))) as Empty }

    // MARK: Me
    struct MeResponse: Decodable { let user: User; let unread: Int }
    static func me() async throws -> MeResponse { try await c.request(.GET, "me") }
    static func updateMe(_ fields: JSONDict) async throws -> User { try await c.request(.PATCH, "me", body: .json(fields)) }
    static func user(_ id: Int64) async throws -> User { try await c.request(.GET, "users/\(id)") }

    static func myLots(status: String = "all", page: Int = 1) async throws -> Page<Lot> {
        try await c.request(.GET, "me/lots", query: ["status": status, "page": "\(page)"])
    }
    static func myBids(page: Int = 1) async throws -> Page<Lot> { try await c.request(.GET, "me/bids", query: ["page": "\(page)"]) }
    static func myFollows(page: Int = 1) async throws -> Page<Lot> { try await c.request(.GET, "me/follows", query: ["page": "\(page)"]) }
    static func myOrders(role: String, status: String?, page: Int = 1) async throws -> Page<Order> {
        try await c.request(.GET, "me/orders", query: ["role": role, "status": status, "page": "\(page)"])
    }

    // MARK: Addresses
    static func addresses() async throws -> [Address] { try await c.request(.GET, "me/addresses") }
    static func createAddress(_ a: Address) async throws -> Address { try await c.request(.POST, "me/addresses", body: .json(a)) }
    static func updateAddress(_ a: Address) async throws -> Address { try await c.request(.PUT, "me/addresses/\(a.id)", body: .json(a)) }
    static func deleteAddress(_ id: Int64) async throws { _ = try await c.request(.DELETE, "me/addresses/\(id)") as Empty }

    // MARK: Meta
    static func filters() async throws -> Filters { try await c.request(.GET, "meta/filters", auth: false) }
    static func estimateFee(category: String, price: Money) async throws -> FeeBreakdown {
        try await c.request(.POST, "fees/estimate", body: .json(JSONDict(["category": category, "price": price])), auth: false)
    }

    // MARK: Lots
    struct LotQuery {
        var status: String? = nil
        var q: String? = nil
        var category: String? = nil
        var brand: String? = nil
        var scale: String? = nil
        var series: String? = nil
        var condition: String? = nil
        var minPrice: Money? = nil
        var maxPrice: Money? = nil
        var sellerId: Int64? = nil
        var sort: String? = nil
        var page = 1
        var pageSize = 20

        var query: [String: String?] {
            ["status": status, "q": q, "category": category, "brand": brand, "scale": scale, "series": series,
             "condition": condition, "min_price": minPrice.map(String.init), "max_price": maxPrice.map(String.init),
             "seller_id": sellerId.map(String.init), "sort": sort, "page": "\(page)", "page_size": "\(pageSize)"]
        }
    }
    static func lots(_ q: LotQuery) async throws -> Page<Lot> { try await c.request(.GET, "lots", query: q.query) }
    static func lot(_ id: Int64) async throws -> Lot { try await c.request(.GET, "lots/\(id)") }
    static func lotBids(_ id: Int64, page: Int = 1) async throws -> Page<Bid> { try await c.request(.GET, "lots/\(id)/bids", query: ["page": "\(page)"]) }
    static func createLot(_ body: JSONDict) async throws -> Lot { try await c.request(.POST, "lots", body: .json(body)) }
    static func cancelLot(_ id: Int64) async throws -> Lot { try await c.request(.POST, "lots/\(id)/cancel") }
    static func follow(_ id: Int64, _ on: Bool) async throws { _ = try await c.request(on ? .POST : .DELETE, "lots/\(id)/follow") as [String: AnyCodable] }

    struct BidResponse: Decodable { let lot: Lot; let bid: Bid }
    static func bid(_ lotId: Int64, amount: Money) async throws -> BidResponse {
        try await c.request(.POST, "lots/\(lotId)/bids", body: .json(JSONDict(["amount": amount])))
    }

    struct LotDepositInfo: Decodable {
        let deposit: LotDeposit?
    }
    struct LotDeposit: Codable, Identifiable, Hashable {
        let id: Int64
        let lotId: Int64
        let buyerId: Int64
        let amount: Money
        var status: String
    }
    static func lotDeposit(_ lotId: Int64) async throws -> LotDepositInfo {
        try await c.request(.GET, "lots/\(lotId)/deposit")
    }
    static func createDepositPayment(lotId: Int64, provider: String) async throws -> Payment {
        try await c.request(.POST, "lots/\(lotId)/deposit/payments", body: .json(JSONDict(["provider": provider])))
    }

    // MARK: Orders / Payments
    static func order(_ id: Int64) async throws -> OrderDetail { try await c.request(.GET, "orders/\(id)") }
    static func setOrderAddress(_ id: Int64, addressId: Int64) async throws -> Order {
        try await c.request(.PUT, "orders/\(id)/address", body: .json(JSONDict(["address_id": addressId])))
    }
    static func ship(_ id: Int64, carrier: String, trackingNo: String) async throws -> Order {
        try await c.request(.POST, "orders/\(id)/ship", body: .json(JSONDict(["carrier": carrier, "tracking_no": trackingNo])))
    }
    static func confirm(_ id: Int64) async throws -> Order { try await c.request(.POST, "orders/\(id)/confirm") }

    static func paymentMethods() async throws -> [PaymentMethod] { try await c.request(.GET, "payments/methods", auth: false) }
    static func createPayment(orderId: Int64, provider: String) async throws -> Payment {
        try await c.request(.POST, "orders/\(orderId)/payments", body: .json(JSONDict(["provider": provider])))
    }
    static func payment(_ id: Int64) async throws -> Payment { try await c.request(.GET, "payments/\(id)") }
    static func syncPayment(_ id: Int64) async throws -> Payment { try await c.request(.POST, "payments/\(id)/sync") }
    static func mockConfirm(_ id: Int64, success: Bool) async throws -> Payment {
        try await c.request(.POST, "payments/\(id)/mock-confirm", body: .json(JSONDict(["success": success])))
    }

    // MARK: Wallet / Tax
    static func wallet() async throws -> Wallet { try await c.request(.GET, "me/wallet") }
    static func ledger(page: Int = 1) async throws -> Page<LedgerEntry> { try await c.request(.GET, "me/wallet/ledger", query: ["page": "\(page)"]) }
    static func withdrawals() async throws -> [WithdrawalRequest] { try await c.request(.GET, "me/withdrawals") }
    static func requestWithdrawal(amount: Money, bankName: String, accountName: String, accountNo: String) async throws -> WithdrawalRequest {
        try await c.request(.POST, "me/withdrawals", body: .json(JSONDict(["amount": amount, "bank_name": bankName, "account_name": accountName, "account_no": accountNo])))
    }
    static func taxProfile() async throws -> TaxProfile? { try await c.requestOptional(.GET, "me/tax-profile") }
    static func putTaxProfile(_ body: JSONDict) async throws -> TaxProfile { try await c.request(.PUT, "me/tax-profile", body: .json(body)) }
    static func taxRecords(period: String? = nil, page: Int = 1) async throws -> Page<TaxRecord> {
        try await c.request(.GET, "me/tax-records", query: ["period": period, "page": "\(page)"])
    }
    static func taxReports() async throws -> [TaxReport] { try await c.request(.GET, "me/tax-reports") }
    static func exportTaxReport(_ id: Int64) async throws -> Data { try await c.download("me/tax-reports/\(id)/export") }

    // MARK: Chat
    static func conversations() async throws -> [Conversation] { try await c.request(.GET, "conversations") }
    static func openConversation(lotId: Int64) async throws -> Conversation {
        try await c.request(.POST, "conversations", body: .json(JSONDict(["lot_id": lotId])))
    }
    static func markAllConversationsRead() async throws {
        _ = try await c.request(.POST, "conversations/read-all") as Empty
    }
    static func messages(_ convId: Int64, before: Int64? = nil) async throws -> [Message] {
        try await c.request(.GET, "conversations/\(convId)/messages", query: ["before": before.map(String.init), "limit": "50"])
    }
    static func send(_ convId: Int64, type: MessageType, content: String) async throws -> Message {
        try await c.request(.POST, "conversations/\(convId)/messages", body: .json(JSONDict(["type": type.rawValue, "content": content])))
    }

    // MARK: Upload
    struct UploadResponse: Decodable { let urls: [String] }
    static func upload(images: [Data]) async throws -> [String] {
        let files = images.enumerated().map { (field: "images", filename: "photo\($0.offset).jpg", mime: "image/jpeg", data: $0.element) }
        let r: UploadResponse = try await c.request(.POST, "upload/images", body: .multipart(files: files))
        return r.urls
    }
}
