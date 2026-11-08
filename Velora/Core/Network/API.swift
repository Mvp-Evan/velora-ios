import Foundation

/// 按领域组织的类型化接口
enum API {
    private static var c: APIClient { .shared }

    // MARK: Auth (DES-v1.3-01)
    static func sendSms(phone: String, deviceId: String = DeviceID.current) async throws -> SendSmsResult {
        try await c.request(
            .POST, "auth/sms",
            body: .json(JSONDict(["phone": phone, "device_id": deviceId])),
            auth: false
        )
    }
    static func login(phone: String, code: String, inviteCode: String? = nil, deviceId: String = DeviceID.current) async throws -> TokenPair {
        var body: [String: Any?] = ["phone": phone, "code": code, "device_id": deviceId]
        if let inviteCode, !inviteCode.isBlank { body["invite_code"] = inviteCode }
        return try await c.request(.POST, "auth/login", body: .json(JSONDict(body)), auth: false)
    }
    static func refresh(_ token: String) async throws -> TokenPair {
        try await c.request(.POST, "auth/refresh", body: .json(JSONDict(["refresh_token": token])), auth: false, retry: false)
    }
    static func logout(_ token: String, all: Bool = false) async {
        _ = try? await c.request(
            .POST, "auth/logout",
            body: .json(JSONDict(["refresh_token": token, "all": all ? true : nil]))
        ) as Empty
    }

    /// Active refresh sessions (may 404 until server ships `/me/sessions`).
    static func sessions() async throws -> [DeviceSession] {
        let resp: SessionsListResponse = try await c.request(.GET, "me/sessions")
        return resp.items
    }
    static func revokeSession(_ id: String) async throws {
        _ = try await c.request(.DELETE, "me/sessions/\(id)") as Empty
    }

    static func deletionStatus() async throws -> DeletionStatusResponse {
        try await c.request(.GET, "me/deletion")
    }
    static func deletionPrecheck() async throws -> DeletionPrecheckResponse {
        try await c.request(.GET, "me/deletion/precheck")
    }
    static func requestDeletion(confirm: String = "注销") async throws -> DeletionStatusResponse {
        try await c.request(.POST, "me/deletion", body: .json(JSONDict(["confirm": confirm])))
    }
    static func cancelDeletion() async throws {
        _ = try await c.request(.POST, "me/deletion/cancel") as Empty
    }

    // MARK: Real-name / KYC (DES-v1.3-01-02)
    static func realNameStatus() async throws -> RealNameStatusResponse {
        try await c.request(.GET, "me/real-name")
    }
    static func createRealNameSession(channel: RealNameChannel) async throws -> RealNameSessionResponse {
        try await c.request(
            .POST, "me/real-name/sessions",
            body: .json(JSONDict(["channel": channel.rawValue]))
        )
    }
    static func completeRealNameSession(id: String, code: String) async throws -> RealNameStatusResponse {
        try await c.request(
            .POST, "me/real-name/sessions/\(id)/complete",
            body: .json(JSONDict(["code": code]))
        )
    }

    // MARK: Seller onboarding
    static func sellerOnboarding() async throws -> SellerOnboardingResponse {
        try await c.request(.GET, "me/seller")
    }
    static func sellerAction(action: String, protocolCode: String? = nil, protocolVersion: String? = nil, scrollEnd: Bool? = nil) async throws -> SellerOnboardingResponse {
        var body: [String: Any?] = ["action": action]
        if let protocolCode { body["protocol_code"] = protocolCode }
        if let protocolVersion { body["protocol_version"] = protocolVersion }
        if let scrollEnd { body["scroll_end"] = scrollEnd }
        return try await c.request(.POST, "me/seller", body: .json(JSONDict(body)))
    }
    static func freezeSellerDeposit() async throws -> SellerDepositResponse {
        try await c.request(.POST, "me/seller/deposit", body: .json(JSONDict([:] as [String: Any?])))
    }

    // MARK: Sub-merchant / profit-sharing onboarding (DES-v1.3-08-01 / D29)
    /// GET `/api/v1/me/sub-merchant` — status + fail reason (design §6).
    static func subMerchant() async throws -> SubMerchant {
        try await c.request(.GET, "me/sub-merchant")
    }
    /// POST `/api/v1/me/sub-merchant` — submit / resubmit materials (idempotent).
    static func submitSubMerchant(
        _ body: SubMerchantSubmitRequest,
        idempotencyKey: String? = nil
    ) async throws -> SubMerchant {
        try await c.request(
            .POST,
            "me/sub-merchant",
            body: .json(body),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: B-side merchant applications
    static func myMerchantApplication() async throws -> MerchantApplicationResponse? {
        try await c.requestOptional(.GET, "merchant-applications/me")
    }
    static func createMerchantApplication(inviteCode: String, applyType: String, docs: [String] = []) async throws -> MerchantApplicationResponse {
        try await c.request(
            .POST, "merchant-applications",
            body: .json(JSONDict([
                "invite_code": inviteCode,
                "apply_type": applyType,
                "docs": docs
            ]))
        )
    }

    // MARK: Proxy agent profile + assessment (DES-v1.3-05-01)
    /// Seller profile projection with `badge` / `assessment_level` (design §6).
    static func proxySellerProfile() async throws -> ProxySellerProfile {
        try await c.request(.GET, "me/seller/profile")
    }
    /// Monthly assessment reports (App path; mirrors merchant assessments).
    static func proxyAssessments() async throws -> ProxyAssessmentListResponse {
        try await c.request(.GET, "me/assessments")
    }

    // MARK: Brand store + follow (DES-v1.3-05-03 BRD-02 / D21; COM-01 brand path DES-v1.3-12-03)
    /// Public store aggregate; Bearer sent when present so `viewer_following` / `viewer_vip` hydrate.
    static func brandStore(_ id: Int64) async throws -> BrandStorePage {
        try await c.request(.GET, "brands/\(id)")
    }
    static func brandStoreReleases(_ id: Int64) async throws -> BrandReleaseCalendarResponse {
        try await c.request(.GET, "brands/\(id)/releases")
    }
    /// Buyer VIP at this brand (DES-v1.3-05-04 / D22). 401 when guest; store aggregate stays 200 without `viewer_vip`.
    static func brandStoreVIP(_ id: Int64) async throws -> BrandBuyerVIP {
        try await c.request(.GET, "brands/\(id)/me/vip")
    }
    /// Idempotent follow — 200 + `already_following=true` on repeat (design §6).
    static func followBrandStore(_ id: Int64, idempotencyKey: String? = nil) async throws -> BrandFollowResponse {
        try await c.request(
            .POST, "brands/\(id)/follow",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }
    static func unfollowBrandStore(_ id: Int64, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(
            .DELETE, "brands/\(id)/follow",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        ) as Empty
    }

    // MARK: Community follow + public profile (DES-v1.3-12-03 COM-01 / D41)
    /// Public homepage — no phone/address (design §5.1). Bearer (when present) hydrates `viewer_following`.
    static func userProfile(_ id: Int64) async throws -> PublicUserProfile {
        try await c.request(.GET, "users/\(id)")
    }
    /// Idempotent `POST /users/{id}/follow` (design §6).
    static func followUser(_ id: Int64, idempotencyKey: String? = nil) async throws -> CommunityFollowResponse {
        try await c.request(
            .POST, "users/\(id)/follow",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }
    static func unfollowUser(_ id: Int64, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(
            .DELETE, "users/\(id)/follow",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        ) as Empty
    }
    /// Phase 2 news feed; Phase 1 returns empty page (design §5.2). Guests OK.
    static func newsFeed(page: Int = 1, type: String? = nil) async throws -> NewsFeedResponse {
        var q: [String: String?] = ["page": "\(page)", "page_size": "\(CommunityConfigDefaults.newsPageSize)"]
        if let type { q["type"] = type }
        return try await c.request(.GET, "feeds/news", query: q)
    }

    // MARK: Product library / cabinet / curve (DES-v1.3-12-04 LIB-01～06 / D42)
    /// SKU index — guests OK; Phase 3 may return empty (design §5.1 / §9「产品库建设中」).
    static func listSKUs(cursor: String? = nil, pageSize: Int = LibraryConfigDefaults.skuListPageSize) async throws -> SkuListResponse {
        var q: [String: String?] = ["page_size": "\(pageSize)"]
        if let cursor { q["cursor"] = cursor }
        return try await c.request(.GET, "skus", query: q)
    }
    static func skuDetail(_ id: Int64) async throws -> ProductSKU {
        try await c.request(.GET, "skus/\(id)")
    }
    /// Curve points only — never listing_id. Flag off / sample gate → `curve_not_ready` / `library_not_enabled` (design §6).
    static func skuCurve(_ id: Int64) async throws -> SkuCurveResponse {
        try await c.request(.GET, "skus/\(id)/curve")
    }
    static func setWishlist(skuId: Int64, kind: WishlistKind, maxPrice: Int64? = nil, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(
            .POST, "skus/\(skuId)/wishlist",
            body: .json(JSONDict(WishlistWriteBody(kind: kind, maxPrice: maxPrice).body)),
            idempotencyKey: idempotencyKey
        ) as Empty
    }
    static func removeWishlist(skuId: Int64, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(
            .DELETE, "skus/\(skuId)/wishlist",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        ) as Empty
    }
    /// Public cabinet wall; privacy off → `cabinet_private` for visitors (design §5.4 / §5.9).
    static func userCabinet(userId: Int64, cursor: String? = nil, pageSize: Int = LibraryConfigDefaults.cabinetPageSize) async throws -> CabinetWallResponse {
        var q: [String: String?] = ["page_size": "\(pageSize)"]
        if let cursor { q["cursor"] = cursor }
        return try await c.request(.GET, "users/\(userId)/cabinet", query: q)
    }
    static func addManualCabinet(skuId: Int64, note: String? = nil, slotNo: Int? = nil, idempotencyKey: String? = nil) async throws -> CabinetItem {
        try await c.request(
            .POST, "me/cabinet",
            body: .json(JSONDict(ManualCabinetBody(skuId: skuId, note: note, slotNo: slotNo).body)),
            idempotencyKey: idempotencyKey
        )
    }
    static func meBadges() async throws -> [SeriesBadge] {
        try await c.request(.GET, "me/badges")
    }
    /// Completion + valuation; client must render disclaimer (design §5.6 / §5.8).
    static func meCabinetSummary() async throws -> CabinetSummaryResponse {
        try await c.request(.GET, "me/cabinet/summary")
    }

    /// Active authorizations for publish brand dropdown (App mirror of `/merchant/v1/authorizations`, design §6).
    static func merchantAuthorizations(status: String = "active") async throws -> BrandAuthorizationListResponse {
        try await c.request(.GET, "me/authorizations", query: ["status": status])
    }

    // MARK: Spot release / rush (DES-v1.3-06-01 REL-01/10/12 / D23)
    /// Public release detail; Bearer hydrates eligibility / reserved (design §6).
    static func spotRelease(_ id: Int64) async throws -> SpotReleaseDetail {
        try await c.request(.GET, "releases/\(id)")
    }
    /// Idempotent reserve remind — repeat returns existing (design §5.2).
    static func reserveSpotRelease(_ id: Int64, idempotencyKey: String? = nil) async throws -> SpotReleaseReserveResult {
        try await c.request(
            .POST,
            "releases/\(id)/reserve",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }
    /// Redis hold + pending_pay order. Requires Idempotency-Key (design §5.4 / §6).
    static func createSpotReleaseOrder(
        _ id: Int64,
        skuId: Int64,
        qty: Int = 1,
        addressId: Int64? = nil,
        idempotencyKey: String? = nil
    ) async throws -> SpotReleaseOrderResult {
        var body: [String: Any?] = ["sku_id": skuId, "qty": qty]
        if let addressId { body["address_id"] = addressId }
        return try await c.request(
            .POST,
            "releases/\(id)/orders",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey
        )
    }
    /// Exclusive deposit preauth / T-08 payment stub (design §5.5).
    static func spotReleaseExclusiveDeposit(
        _ id: Int64,
        idempotencyKey: String? = nil
    ) async throws -> SpotReleaseExclusiveDepositResult {
        try await c.request(
            .POST,
            "releases/\(id)/exclusive-deposit",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Lottery enroll / draw-proof (DES-v1.3-06-02 REL-02/03/04/05 / D24)
    /// Lottery release detail (same path as spot; mode=lottery fields).
    static func lotteryRelease(_ id: Int64) async throws -> LotteryReleaseDetail {
        try await c.request(.GET, "releases/\(id)")
    }
    /// Enroll with Idempotency-Key + device attestation (design §5.2 / §6).
    static func createLotteryEntry(
        _ releaseId: Int64,
        addressId: Int64,
        deviceAttestation: LotteryDeviceAttestation,
        idempotencyKey: String? = nil
    ) async throws -> LotteryEntryCreateResult {
        try await c.request(
            .POST,
            "releases/\(releaseId)/lottery-entries",
            body: .json(LotteryEntryCreateBody(
                addressId: addressId,
                deviceAttestation: deviceAttestation
            )),
            idempotencyKey: idempotencyKey
        )
    }
    /// My lottery entries; optional status filter (design §6 / §9).
    static func myLotteryEntries(
        status: LotteryEntryStatus? = nil,
        page: Int = 1
    ) async throws -> Page<LotteryEntry> {
        var q: [String: String?] = ["page": "\(page)"]
        if let status { q["status"] = status.rawValue }
        return try await c.request(.GET, "me/lottery-entries", query: q)
    }
    /// Public draw-proof (guest OK). `draw_not_ready` when not published (design §5.6 / §6).
    static func lotteryDrawProof(_ releaseId: Int64) async throws -> LotteryDrawProof {
        try await c.request(.GET, "releases/\(releaseId)/draw-proof", auth: false)
    }

    // MARK: Presale lifecycle / balance pay (DES-v1.3-06-03 REL-06/07/08/14/15 / D25)
    /// Presale release detail (same path as spot; mode=presale fields).
    static func presaleRelease(_ id: Int64) async throws -> PresaleReleaseDetail {
        try await c.request(.GET, "releases/\(id)")
    }
    /// Create deposit hold + pending deposit order. Requires Idempotency-Key (design §5.2 / §6).
    static func createPresaleOrder(
        _ releaseId: Int64,
        skuId: Int64,
        qty: Int = 1,
        addressId: Int64? = nil,
        idempotencyKey: String? = nil
    ) async throws -> PresaleOrderCreateResult {
        try await c.request(
            .POST,
            "releases/\(releaseId)/presale-orders",
            body: .json(PresaleOrderCreateBody(skuId: skuId, qty: qty, addressId: addressId)),
            idempotencyKey: idempotencyKey
        )
    }
    /// My补款 list; optional biz_status filter (design §5.10).
    static func myPresaleOrders(
        bizStatus: PresaleBizStatus? = nil,
        page: Int = 1
    ) async throws -> Page<PresaleOrderSummary> {
        var q: [String: String?] = ["page": "\(page)"]
        if let bizStatus { q["biz_status"] = bizStatus.rawValue }
        return try await c.request(.GET, "me/presale-orders", query: q)
    }
    static func presaleOrder(_ id: Int64) async throws -> PresaleOrderDetail {
        try await c.request(.GET, "presale-orders/\(id)")
    }
    /// Universal Link landing probe (design §5.3 / §6). Token optional; pay still requires Bearer.
    static func balancePayLanding(
        orderId: Int64,
        token: String? = nil
    ) async throws -> BalancePayLanding {
        var q: [String: String?] = [:]
        if let token, !token.isEmpty { q["t"] = token }
        return try await c.request(.GET, "pay/balance/\(orderId)", query: q, auth: false)
    }
    /// Create balance (tail) payment for order.type=presale_balance (design §6).
    static func createBalancePayment(
        orderId: Int64,
        provider: String,
        idempotencyKey: String? = nil
    ) async throws -> Payment {
        try await c.request(
            .POST,
            "orders/\(orderId)/balance-payments",
            body: .json(BalancePaymentCreateBody(provider: provider)),
            idempotencyKey: idempotencyKey
        )
    }
    /// Delay-notice buyer refund deposit choice (design §5.7 / §6).
    static func refundPresaleDeposit(
        _ presaleOrderId: Int64,
        idempotencyKey: String? = nil
    ) async throws -> PresaleRefundDepositResult {
        try await c.request(
            .POST,
            "presale-orders/\(presaleOrderId)/refund-deposit",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Proxy invoice (DES-v1.3-05-02 PXY-04 / D20)
    static func invoicePreview(
        mode: InvoiceMode,
        period: String,
        orderIds: [Int64] = []
    ) async throws -> InvoicePreview {
        var q: [String: String?] = [
            "mode": mode.rawValue,
            "period": period,
        ]
        if !orderIds.isEmpty {
            q["order_ids"] = orderIds.map(String.init).joined(separator: ",")
        }
        return try await c.request(.GET, "me/invoice-requests/preview", query: q)
    }

    static func invoiceRequests(page: Int = 1) async throws -> Page<InvoiceRequest> {
        try await c.request(.GET, "me/invoice-requests", query: ["page": "\(page)"])
    }

    static func invoiceRequest(_ id: Int64) async throws -> InvoiceRequest {
        try await c.request(.GET, "me/invoice-requests/\(id)")
    }

    static func submitInvoiceRequest(
        _ body: InvoiceSubmitBody,
        idempotencyKey: String? = nil
    ) async throws -> InvoiceRequest {
        try await c.request(
            .POST, "me/invoice-requests",
            body: .json(body),
            idempotencyKey: idempotencyKey
        )
    }

    static func invoiceFile(_ id: Int64) async throws -> InvoiceFileResponse {
        try await c.request(.GET, "me/invoice-requests/\(id)/file")
    }

    static func invoiceTitles() async throws -> [InvoiceTitle] {
        try await c.request(.GET, "me/invoice-titles")
    }

    static func upsertInvoiceTitle(
        _ body: InvoiceTitleUpsertBody,
        idempotencyKey: String? = nil
    ) async throws -> InvoiceTitle {
        try await c.request(
            .PUT, "me/invoice-titles",
            body: .json(body),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Me
    /// GET `/me` projection (DES-v1.3-00-02 / freeze doc §5.7).
    struct MeResponse: Decodable {
        let user: User
        let unread: Int
        let status: String?
        let restrictions: [AccountRestrictionItem]?

        enum CodingKeys: String, CodingKey {
            case user, unread, status, restrictions
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            user = try c.decode(User.self, forKey: .user)
            unread = try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0
            status = try c.decodeIfPresent(String.self, forKey: .status)
            restrictions = try c.decodeIfPresent([AccountRestrictionItem].self, forKey: .restrictions)
        }
    }
    static func me() async throws -> MeResponse { try await c.request(.GET, "me") }
    /// Optional auth — drives nav_schema / publish_actions / capabilities (DES-v1.3-00-02).
    /// Sends Bearer when present; guests still get a public schema.
    static func meBootstrap() async throws -> MeBootstrap {
        try await c.request(.GET, "me/bootstrap")
    }
    static func updateMe(_ fields: JSONDict) async throws -> User { try await c.request(.PATCH, "me", body: .json(fields)) }
    /// Legacy alias — prefer `userProfile` (COM-01 public card, no phone).
    static func user(_ id: Int64) async throws -> PublicUserProfile { try await userProfile(id) }

    // MARK: Me overview / prefs / history / settings (DES-v1.3-12-01 / D39)

    /// GET `/me/overview` — buyer/seller entries + badges (ME-01～05).
    static func meOverview() async throws -> MeOverviewResponse {
        try await c.request(.GET, "me/overview")
    }

    /// PUT `/me/prefs` — `me_view` / `save_browse_history` (idempotent).
    static func updateMePrefs(meView: String? = nil, saveBrowseHistory: Bool? = nil) async throws -> MePrefsUpdateResponse {
        try await c.request(
            .PUT,
            "me/prefs",
            body: .json(JSONDict(MePrefsUpdateRequest(meView: meView, saveBrowseHistory: saveBrowseHistory).body))
        )
    }

    /// GET `/me/history` — 90-day browse footprint (ME-06).
    static func meHistory(cursor: String? = nil, pageSize: Int = MeConfigDefaults.historyPageSize) async throws -> BrowseHistoryListResponse {
        var q: [String: String?] = ["page_size": "\(pageSize)"]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await c.request(.GET, "me/history", query: q)
    }

    /// POST `/me/history` — record listing view (server ignores client viewed_at; 30s throttle).
    static func recordMeHistory(listingId: Int64) async throws {
        _ = try await c.request(
            .POST,
            "me/history",
            body: .json(JSONDict(BrowseHistoryRecordRequest(listingId: listingId).body))
        ) as Empty
    }

    /// DELETE `/me/history/{id}`
    static func deleteMeHistory(id: Int64) async throws {
        _ = try await c.request(.DELETE, "me/history/\(id)") as Empty
    }

    /// DELETE `/me/history` — clear all (idempotent).
    static func clearMeHistory() async throws {
        _ = try await c.request(.DELETE, "me/history") as Empty
    }

    /// GET `/me/settings` — real-name projection, protocols, licenses, save-history flag (ME-07).
    static func meSettings() async throws -> MeSettingsResponse {
        try await c.request(.GET, "me/settings")
    }

    /// GET `/legal/licenses` — public资质公示 (NFR-08); guests OK.
    static func legalLicenses() async throws -> LegalLicensesResponse {
        try await c.request(.GET, "legal/licenses", auth: false)
    }

    /// GET `/legal/sdks` — third-party SDK list (DES-v1.3-14-02 / NFR-07).
    static func legalSDKs() async throws -> LegalSDKsResponse {
        try await c.request(.GET, "legal/sdks", auth: false)
    }

    /// Typed ME-07 precheck with count/hint blockers (same path as ACC-07).
    static func meDeletionPrecheck() async throws -> MeDeletionPrecheck {
        try await c.request(.GET, "me/deletion/precheck")
    }

    // MARK: Reviews & credit (DES-v1.3-12-02 / D40)

    /// POST `/orders/{id}/reviews` — submit mutual review (CRD-01).
    static func submitOrderReview(
        orderId: Int64,
        rating: ReviewRating,
        content: String? = nil,
        imageIds: [String] = [],
        idempotencyKey: String? = nil
    ) async throws -> OrderReview {
        try await c.request(
            .POST,
            "orders/\(orderId)/reviews",
            body: .json(JSONDict(SubmitOrderReviewRequest(rating: rating, content: content, imageIds: imageIds).body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// GET `/orders/{id}/reviews` — both sides for parties / public summary.
    static func orderReviews(orderId: Int64) async throws -> OrderReviewsResponse {
        try await c.request(.GET, "orders/\(orderId)/reviews")
    }

    /// GET `/users/{id}/reviews` — paginated public reviews (incl. arbitration_tag).
    static func userReviews(
        userId: Int64,
        cursor: String? = nil,
        pageSize: Int = ReviewCreditConfigDefaults.reviewsPageSize
    ) async throws -> UserReviewsListResponse {
        var q: [String: String?] = ["page_size": "\(pageSize)"]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await c.request(.GET, "users/\(userId)/reviews", query: q)
    }

    /// GET `/me/credit` — score, month_plus_used/cap, thresholds, last 90d logs.
    static func meCredit() async throws -> MeCreditResponse {
        try await c.request(.GET, "me/credit")
    }

    /// GET `/users/{id}/seller-card` — score + CRD-03 metrics (guest OK).
    static func sellerCard(userId: Int64) async throws -> SellerCardMetrics {
        try await c.request(.GET, "users/\(userId)/seller-card", auth: false)
    }

    static func myLots(status: String = "all", page: Int = 1) async throws -> Page<Lot> {
        try await c.request(.GET, "me/lots", query: ["status": status, "page": "\(page)"])
    }
    static func myBids(page: Int = 1) async throws -> Page<Lot> { try await c.request(.GET, "me/bids", query: ["page": "\(page)"]) }
    static func myFollows(page: Int = 1) async throws -> Page<Lot> { try await c.request(.GET, "me/follows", query: ["page": "\(page)"]) }
    /// Unified order center list (DES-v1.3-07-01 / D27). `role=buyer|seller`.
    static func myOrders(
        role: String,
        status: String? = nil,
        tradeType: String? = nil,
        afterSaleStatus: String? = nil,
        tab: String? = nil,
        page: Int = 1,
        pageSize: Int = OrderCenterConfigDefaults.listPageSizeDefault
    ) async throws -> Page<Order> {
        let q = OrderListQuery(
            role: role == "seller" || role == "sell" ? "sell" : "buy",
            status: status,
            tradeType: tradeType,
            afterSaleStatus: afterSaleStatus,
            tab: tab,
            page: page,
            pageSize: pageSize
        )
        // Server accepts role=buyer|seller historically; also buy|sell per design §6.
        var query = q.asQueryItems
        query["role"] = role
        return try await c.request(.GET, "me/orders", query: query)
    }

    // MARK: Addresses (DES-v1.3-07-01 ORD-03 — max 20)
    static func addresses() async throws -> [Address] { try await c.request(.GET, "me/addresses") }
    static func createAddress(_ a: Address, idempotencyKey: String? = nil) async throws -> Address {
        try await c.request(.POST, "me/addresses", body: .json(a), idempotencyKey: idempotencyKey)
    }
    static func updateAddress(_ a: Address, idempotencyKey: String? = nil) async throws -> Address {
        try await c.request(.PUT, "me/addresses/\(a.id)", body: .json(a), idempotencyKey: idempotencyKey)
    }
    static func deleteAddress(_ id: Int64, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(.DELETE, "me/addresses/\(id)", idempotencyKey: idempotencyKey) as Empty
    }

    // MARK: Purchase home (DES-v1.3-02-01)
    /// Anonymous OK for hot/new; follow requires login (`login_required`). Bearer sent when present.
    static func homeFeed(
        tab: String = HomeFeedTab.hot.rawValue,
        cursor: String? = nil,
        pageSize: Int = 20,
        tradeType: String? = nil,
        status: String? = nil,
        releaseMode: String? = nil
    ) async throws -> HomeFeedResponse {
        try await c.request(
            .GET, "home/feed",
            query: [
                "tab": tab,
                "cursor": cursor,
                "page_size": "\(min(max(pageSize, 1), 50))",
                "trade_type": tradeType,
                "status": status,
                "release_mode": releaseMode,
            ]
        )
    }
    static func homeSlots() async throws -> HomeSlotsResponse {
        try await c.request(.GET, "home/slots")
    }
    static func reportHomeExposures(requestId: String, events: [HomeExposureEvent], deviceId: String = DeviceID.current) async throws {
        _ = try await c.request(
            .POST, "home/exposures",
            body: .json(HomeExposuresRequest(requestId: requestId, events: events, deviceId: deviceId))
        ) as Empty
    }

    // MARK: Meta
    static func filters() async throws -> Filters { try await c.request(.GET, "meta/filters", auth: false) }
    /// Current bid-increment ladder (DES-v1.3-03-01 AUC-03). Falls back to client defaults on failure.
    static func bidIncrements() async throws -> BidIncrementTiersResponse {
        try await c.request(.GET, "meta/bid-increments", auth: false)
    }
    /// Legacy category estimate (wallet / older screens). Prefer `estimateFeeQuote` for publish (PUB-06).
    static func estimateFee(category: String, price: Money) async throws -> FeeBreakdown {
        try await c.request(.POST, "fees/estimate", body: .json(JSONDict(["category": category, "price": price])), auth: false)
    }
    /// Publish fee quote — returns `fee_quote_id` (DES-v1.3-02-05 PUB-06). Client must not multiply rates locally.
    static func estimateFeeQuote(tradeType: String, price: Money, shippingFee: Money = 0) async throws -> FeeQuoteEstimate {
        try await c.request(
            .POST, "fees/estimate",
            body: .json(JSONDict([
                "trade_type": tradeType,
                "price": price,
                "shipping_fee": shippingFee,
            ]))
        )
    }

    // MARK: Search / listings (DES-v1.3-02-02)
    /// Anonymous OK. Prefer over `/lots` for discovery filters (ending_within / sold / leak).
    static func listings(_ q: ListingSearchQuery) async throws -> SearchListingsPage {
        try await c.request(.GET, "listings", query: q.queryItems)
    }

    // MARK: Direct zone + buy-now (DES-v1.3-04-01)
    /// Zone config: sections / filters / featured slots / `config_version`.
    static func directZone() async throws -> DirectZoneConfig {
        try await c.request(.GET, "direct-zone", auth: false)
    }
    /// `trade_type=fixed` listings for a zone section (cursor page).
    static func directZoneListings(_ q: DirectZoneListingsQuery) async throws -> DirectZoneListingsPage {
        try await c.request(.GET, "listings", query: q.queryItems, auth: false)
    }
    /// Server-priced confirm page; client must not compute totals locally.
    static func fixedOrderPreview(
        _ listingId: Int64,
        qty: Int,
        addressId: Int64,
        expectedPriceFen: Int64? = nil
    ) async throws -> FixedOrderPreview {
        var body: [String: Any?] = ["qty": qty, "address_id": addressId]
        if let expectedPriceFen { body["expected_price_fen"] = expectedPriceFen }
        return try await c.request(
            .POST,
            "listings/\(listingId)/order-preview",
            body: .json(JSONDict(body))
        )
    }
    /// Lock stock + create pending_payment order (15 min). Requires Idempotency-Key.
    static func createFixedOrder(
        _ listingId: Int64,
        qty: Int,
        addressId: Int64,
        source: DirectOrderSource,
        expectedPriceFen: Int64? = nil,
        idempotencyKey: String? = nil
    ) async throws -> FixedOrderCreateResult {
        var body: [String: Any?] = [
            "qty": qty,
            "address_id": addressId,
            "source": source.rawValue,
        ]
        if let expectedPriceFen { body["expected_price_fen"] = expectedPriceFen }
        return try await c.request(
            .POST,
            "listings/\(listingId)/orders",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey
        )
    }
    /// Buyer cancel pending fixed-price order → release stock.
    static func cancelFixedOrder(_ id: Int64) async throws -> Order {
        try await c.request(.POST, "orders/\(id)/cancel", body: .json(JSONDict([:] as [String: Any?])))
    }
    static func offShelfListing(_ id: Int64, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(
            .POST,
            "listings/\(id)/off-shelf",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        ) as Empty
    }

    // MARK: Structured offer + price-drop (DES-v1.3-04-02 DIR-03/05)
    static func createOffer(
        _ listingId: Int64,
        price: Int64,
        idempotencyKey: String? = nil
    ) async throws -> CreateOfferResponse {
        try await c.request(
            .POST,
            "listings/\(listingId)/offers",
            body: .json(JSONDict(["price": price])),
            idempotencyKey: idempotencyKey
        )
    }
    static func acceptOffer(_ offerId: Int64, idempotencyKey: String? = nil) async throws -> AcceptOfferResponse {
        try await c.request(
            .POST,
            "offers/\(offerId)/accept",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }
    static func rejectOffer(
        _ offerId: Int64,
        reason: OfferRejectReasonCode,
        note: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> RejectOfferResponse {
        var body: [String: Any?] = ["reason": reason.rawValue]
        if let note, !note.isBlank { body["note"] = note }
        return try await c.request(
            .POST,
            "offers/\(offerId)/reject",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey
        )
    }
    static func counterOffer(
        _ offerId: Int64,
        price: Int64,
        idempotencyKey: String? = nil
    ) async throws -> CounterOfferResponse {
        try await c.request(
            .POST,
            "offers/\(offerId)/counter",
            body: .json(JSONDict(["price": price])),
            idempotencyKey: idempotencyKey
        )
    }
    static func cancelOffer(_ offerId: Int64, idempotencyKey: String? = nil) async throws -> CancelOfferResponse {
        try await c.request(
            .POST,
            "offers/\(offerId)/cancel",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }
    static func myListingOffer(_ listingId: Int64) async throws -> Offer? {
        try await c.requestOptional(.GET, "listings/\(listingId)/offers/mine")
    }
    static func myOffers(role: OfferRole, cursor: String? = nil) async throws -> OfferListPage {
        var q: [String: String?] = ["role": role.rawValue]
        if let cursor { q["cursor"] = cursor }
        return try await c.request(.GET, "me/offers", query: q)
    }

    // MARK: Listing detail / Q&A / 补图 (DES-v1.3-02-04)
    /// Anonymous OK. Buyer path must not expose `reserve_price` (DES §6 / ITEM-03).
    static func listing(_ id: Int64) async throws -> ListingDetail {
        try await c.request(.GET, "listings/\(id)", auth: false)
    }
    /// Favorite writes `price_snapshot`; unfavorite does not reset price-drop cooldown (DIR-05).
    @discardableResult
    static func favoriteListing(_ id: Int64, _ on: Bool) async throws -> FavoriteListingResult? {
        if on {
            return try await c.request(.POST, "listings/\(id)/favorite") as FavoriteListingResult
        }
        _ = try await c.request(.DELETE, "listings/\(id)/favorite") as Empty
        return nil
    }
    static func listingQuestions(_ id: Int64, page: Int = 1) async throws -> ListingQuestionsPage {
        try await c.request(
            .GET, "listings/\(id)/questions",
            query: ["page": "\(page)", "page_size": "\(ListingDetailLimits.questionsPageSize)"],
            auth: false
        )
    }
    static func postListingQuestion(_ id: Int64, content: String) async throws -> ListingQuestion {
        try await c.request(
            .POST, "listings/\(id)/questions",
            body: .json(JSONDict(["content": content]))
        )
    }
    static func answerListingQuestion(_ questionId: Int64, answer: String) async throws -> ListingQuestion {
        try await c.request(
            .POST, "questions/\(questionId)/answer",
            body: .json(JSONDict(["answer": answer]))
        )
    }
    static func deleteListingQuestion(_ questionId: Int64) async throws {
        _ = try await c.request(.DELETE, "questions/\(questionId)") as Empty
    }
    static func postPhotoRequest(_ listingId: Int64, part: PhotoRequestPart) async throws -> PhotoRequestRow {
        try await c.request(
            .POST, "listings/\(listingId)/photo-requests",
            body: .json(JSONDict(["part": part.rawValue]))
        )
    }
    /// Seller 补图 — `source` must be in-app camera (DES §5.6).
    static func postSupplementPhoto(
        listingId: Int64,
        imageId: String,
        source: String = ListingDetailLimits.photoSourceInAppCamera
    ) async throws -> ListingImage {
        try await c.request(
            .POST, "listings/\(listingId)/photos",
            body: .json(JSONDict([
                "image_id": imageId,
                "role": ListingImageRole.supplement.rawValue,
                "source": source
            ]))
        )
    }
    static func deleteListingPhoto(listingId: Int64, photoId: Int64) async throws {
        _ = try await c.request(.DELETE, "listings/\(listingId)/photos/\(photoId)") as Empty
    }
    static func hotWords() async throws -> HotWordsResponse {
        try await c.request(.GET, "search/hot-words", auth: false)
    }
    static func myShortcuts() async throws -> UserShortcutsResponse {
        try await c.request(.GET, "me/shortcuts")
    }
    static func putShortcuts(_ words: [UserShortcutWord]) async throws -> UserShortcutsResponse {
        try await c.request(.PUT, "me/shortcuts", body: .json(PutShortcutsRequest(words: words)))
    }
    static func savedSearches() async throws -> SavedSearchesResponse {
        try await c.request(.GET, "me/saved-searches")
    }
    static func createSavedSearch(query: String?, filters: [String: String], notifyTypes: [SavedSearchNotifyType]) async throws -> SavedSearch {
        try await c.request(
            .POST, "me/saved-searches",
            body: .json(CreateSavedSearchRequest(query: query, filters: filters, notifyTypes: notifyTypes))
        )
    }
    static func deleteSavedSearch(_ id: Int64) async throws {
        _ = try await c.request(.DELETE, "me/saved-searches/\(id)") as Empty
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
    static func lotBids(_ id: Int64, page: Int = 1, afterSeq: Int64? = nil) async throws -> Page<Bid> {
        var q: [String: String?] = ["page": "\(page)"]
        if let afterSeq { q["after_seq"] = "\(afterSeq)" }
        return try await c.request(.GET, "lots/\(id)/bids", query: q)
    }
    static func createLot(_ body: JSONDict) async throws -> Lot { try await c.request(.POST, "lots", body: .json(body)) }
    /// Auction publish with moderation / fee_quote (DES-v1.3-02-05).
    /// `PublishSubmitResult` also decodes legacy Lot `{id,status}` payloads.
    static func createLotPublish(_ body: JSONDict) async throws -> PublishSubmitResult {
        try await c.request(.POST, "lots", body: .json(body))
    }
    /// Fixed-price / draft publish (DES-v1.3-02-05).
    static func createListing(_ body: JSONDict) async throws -> PublishSubmitResult {
        try await c.request(.POST, "listings", body: .json(body))
    }
    static func myPublishDrafts(tradeType: String? = nil, page: Int = 1) async throws -> Page<CloudPublishDraft> {
        var q: [String: String?] = ["status": "draft", "page": "\(page)", "page_size": "20"]
        if let tradeType { q["trade_type"] = tradeType }
        return try await c.request(.GET, "me/listings", query: q)
    }
    static func patchPublishDraft(id: Int64, body: JSONDict) async throws -> PublishSubmitResult {
        try await c.request(.PATCH, "listings/\(id)", body: .json(body))
    }
    static func cancelLot(_ id: Int64) async throws -> Lot { try await c.request(.POST, "lots/\(id)/cancel") }

    /// Relist an unsold/cancelled lot (DES-v1.3-03-05 AUC-11). Idempotent.
    static func relistLot(_ id: Int64, body: RelistLotRequest, idempotencyKey: String? = nil) async throws -> RelistLotResponse {
        let key = idempotencyKey ?? "relist-\(id)-\(Int(Date().timeIntervalSince1970))"
        return try await c.request(
            .POST,
            "lots/\(id)/relist",
            body: .json(body),
            idempotencyKey: key
        )
    }

    static func follow(_ id: Int64, _ on: Bool) async throws { _ = try await c.request(on ? .POST : .DELETE, "lots/\(id)/follow") as [String: AnyCodable] }

    /// Subscribe closing remind (DES-v1.3-03-03 AUC-13); idempotent 200.
    @discardableResult
    static func remindLot(_ id: Int64) async throws -> LotRemindResponse {
        try await c.request(.POST, "lots/\(id)/remind")
    }

    /// Weekly auction-session calendar (DES-v1.3-03-03 §5.5 / §6).
    static func auctionSessions(weekStart: String? = nil) async throws -> AuctionSessionCalendarResponse {
        var q: [String: String?] = [:]
        if let weekStart { q["week_start"] = weekStart }
        return try await c.request(.GET, "auction-sessions", query: q)
    }

    static func auctionSession(_ id: Int64) async throws -> AuctionSessionDetailResponse {
        try await c.request(.GET, "auction-sessions/\(id)")
    }

    @discardableResult
    static func subscribeAuctionSession(_ id: Int64) async throws -> LotRemindResponse {
        try await c.request(.POST, "auction-sessions/\(id)/subscribe")
    }

    /// PlaceBid response (DES-v1.3-03-02 §6): lot + bid + seq / min_next_bid / end_at / extended.
    struct BidResponse: Decodable {
        let lot: Lot
        let bid: Bid
        let seq: Int64?
        let minNextBid: Money?
        let endAt: Date?
        let extended: Bool?

        enum CodingKeys: String, CodingKey {
            case lot, bid, seq, minNextBid, endAt, extended
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lot = try c.decode(Lot.self, forKey: .lot)
            bid = try c.decode(Bid.self, forKey: .bid)
            seq = try c.decodeIfPresent(Int64.self, forKey: .seq) ?? bid.seq ?? lot.seq
            minNextBid = try c.decodeIfPresent(Money.self, forKey: .minNextBid)
            endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
            extended = try c.decodeIfPresent(Bool.self, forKey: .extended)
        }

        var effectiveSeq: Int64? { seq ?? bid.seq ?? lot.seq }
    }

    /// Place a bid with an explicit sticky `Idempotency-Key` (AUC-07).
    static func bid(_ lotId: Int64, amount: Money, idempotencyKey: String) async throws -> BidResponse {
        try await c.request(
            .POST,
            "lots/\(lotId)/bids",
            body: .json(JSONDict(["amount": amount])),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Proxy bid (DES-v1.3-03-04 AUC-14)

    /// GET own proxy; `nil` when 404 / none (design §6 — never empty 200 for probing).
    static func proxyBid(_ lotId: Int64) async throws -> ProxyBidState? {
        do {
            return try await c.request(.GET, "lots/\(lotId)/proxy-bid") as ProxyBidState
        } catch let e as APIError where e.status == 404 || e.code.hasPrefix("http_404") || e.code == "not_found" {
            return nil
        }
    }

    /// PUT set / raise max (Idempotency-Key sticky across deposit retries).
    static func putProxyBid(
        _ lotId: Int64,
        maxAmount: Money,
        version: Int64? = nil,
        idempotencyKey: String
    ) async throws -> ProxyBidState {
        var body: [String: Any?] = ["max_amount": maxAmount]
        if let version { body["version"] = version }
        return try await c.request(
            .PUT,
            "lots/\(lotId)/proxy-bid",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey
        )
    }

    /// DELETE cancel; historical bids retained (design §5.1).
    static func deleteProxyBid(_ lotId: Int64, version: Int64? = nil, idempotencyKey: String? = nil) async throws {
        var body: RequestBody = .none
        if let version {
            body = .json(JSONDict(["version": version]))
        }
        let _: Empty = try await c.request(
            .DELETE,
            "lots/\(lotId)/proxy-bid",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Deposits (DES-v1.3-08-02 / D30)

    /// GET `/lots/{id}/deposit` — required amount + status/method (design §6).
    static func lotDeposit(_ lotId: Int64) async throws -> LotDepositInfo {
        try await c.request(.GET, "lots/\(lotId)/deposit")
    }

    /// POST `/lots/{id}/deposit/payments` — freeze (preauth or payment; UX「冻结保证金」).
    static func createDepositPayment(
        lotId: Int64,
        provider: String,
        idempotencyKey: String? = nil
    ) async throws -> Payment {
        try await c.request(
            .POST,
            "lots/\(lotId)/deposit/payments",
            body: .json(JSONDict(["provider": provider])),
            idempotencyKey: idempotencyKey
        )
    }

    /// GET `/me/deposits` — optional `type` = bid|lottery|seller.
    static func myDeposits(type: String? = nil, cursor: String? = nil) async throws -> MeDepositsResponse {
        var q: [String: String?] = [:]
        if let type, !type.isEmpty { q["type"] = type }
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await c.request(.GET, "me/deposits", query: q)
    }

    /// POST `/me/seller-deposit/payments` — top-up when gap_amount > 0 (design §5.8 / §6).
    static func createSellerDepositPayment(
        amount: Money? = nil,
        provider: String,
        idempotencyKey: String? = nil
    ) async throws -> Payment {
        var body: [String: Any?] = ["provider": provider]
        if let amount { body["amount"] = amount }
        return try await c.request(
            .POST,
            "me/seller-deposit/payments",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey
        )
    }

    /// POST `/me/seller-deposit/exit` — start 30-day cooling (design §5.3 / §6).
    static func exitSellerDeposit(idempotencyKey: String? = nil) async throws -> SellerDepositExitResponse {
        try await c.request(
            .POST,
            "me/seller-deposit/exit",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Orders / Payments (DES-v1.3-07-01)
    static func order(_ id: Int64) async throws -> OrderDetail { try await c.request(.GET, "orders/\(id)") }
    /// PUT address — requires Idempotency-Key (design §5.3 / §6). Editable until shipped.
    static func setOrderAddress(_ id: Int64, addressId: Int64, idempotencyKey: String? = nil) async throws -> Order {
        try await c.request(
            .PUT,
            "orders/\(id)/address",
            body: .json(JSONDict(["address_id": addressId])),
            idempotencyKey: idempotencyKey
        )
    }
    /// Buyer cancel of pending auction order — same as AUC-10 default (design §5.2).
    static func cancelAuctionOrder(_ id: Int64, confirm: String = CancelAuctionOrderRequest.confirmPhrase) async throws -> Order {
        try await c.request(
            .POST,
            "orders/\(id)/cancel",
            body: .json(CancelAuctionOrderRequest(confirm: confirm))
        )
    }
    /// Seller ship — carrier / tracking / optional insured (DES-v1.3-07-02 ORD-04/09).
    static func ship(
        _ id: Int64,
        carrier: String,
        trackingNo: String,
        insured: Bool? = nil,
        insuredAmount: Int64? = nil,
        idempotencyKey: String? = nil
    ) async throws -> Order {
        var body: [String: Any?] = [
            "carrier": carrier,
            "tracking_no": ShipmentLogic.normalizeTrackingNo(trackingNo),
        ]
        if let insured { body["insured"] = insured }
        if let insuredAmount { body["insured_amount"] = insuredAmount }
        return try await c.request(
            .POST,
            "orders/\(id)/ship",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Evidence capture / fingerprint (DES-v1.3-09-01 AFS-01～03 / D33)

    /// POST `/orders/{id}/evidence/sessions` — open capture session (ship/unbox).
    static func openEvidenceSession(
        orderId: Int64,
        kindGroup: EvidenceKindGroup,
        idempotencyKey: String? = nil
    ) async throws -> EvidenceCaptureSession {
        try await c.request(
            .POST,
            "orders/\(orderId)/evidence/sessions",
            body: .json(JSONDict(["kind_group": kindGroup.rawValue])),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// GET `/orders/{id}/evidence` — slot completion + fingerprint status.
    static func orderEvidence(_ orderId: Int64) async throws -> OrderEvidenceState {
        try await c.request(.GET, "orders/\(orderId)/evidence")
    }

    /// GET `/orders/{id}/evidence/summary` — dispute hint for 09-02.
    static func orderEvidenceSummary(_ orderId: Int64) async throws -> EvidenceSummary {
        try await c.request(.GET, "orders/\(orderId)/evidence/summary")
    }

    /// POST `/orders/{id}/evidence/photos` — multipart camera JPEG (no album).
    static func uploadEvidencePhoto(
        orderId: Int64,
        sessionId: String,
        slot: String,
        jpegData: Data,
        captureToken: String,
        deviceId: String,
        idempotencyKey: String? = nil
    ) async throws -> EvidencePhotoUploadResult {
        let key = idempotencyKey ?? EvidenceLogic.photoIdempotencyKey(sessionId: sessionId, slot: slot)
        return try await c.request(
            .POST,
            "orders/\(orderId)/evidence/photos",
            body: .multipart(
                files: [(
                    field: "file",
                    filename: "\(slot).jpg",
                    mime: "image/jpeg",
                    data: jpegData
                )],
                fields: [
                    "session_id": sessionId,
                    "slot": slot,
                    "source": EvidenceConfigDefaults.photoSourceAppCamera,
                    "capture_token": captureToken,
                    "device_id": deviceId,
                ]
            ),
            idempotencyKey: key
        )
    }

    /// POST `/orders/{id}/evidence/video-fingerprints` — SHA-256 + duration only (no binary).
    static func submitEvidenceVideoFingerprint(
        orderId: Int64,
        request: EvidenceVideoFingerprintRequest,
        idempotencyKey: String? = nil
    ) async throws -> EvidenceVideoFingerprintResult {
        try await c.request(
            .POST,
            "orders/\(orderId)/evidence/video-fingerprints",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// Buyer confirm receipt (ORD-06). Rejected with `after_sale_active` while processing.
    static func confirm(_ id: Int64, idempotencyKey: String? = nil) async throws -> Order {
        try await c.request(
            .POST,
            "orders/\(id)/confirm",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }

    /// Logistics timeline (ORD-05). Visible to buyer and seller.
    static func orderTracking(_ id: Int64) async throws -> TrackingResult {
        try await c.request(.GET, "orders/\(id)/tracking")
    }

    /// Buyer cancel after ship deadline + grace (ORD-04). Error `ship_not_overdue` inside grace.
    static func cancelUnshipped(_ id: Int64, idempotencyKey: String? = nil) async throws -> Order {
        try await c.request(
            .POST,
            "orders/\(id)/cancel-unshipped",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey
        )
    }

    /// Merge-pay checkout group stub (ORD-10). Feature-flagged server-side.
    static func createCheckoutGroup(
        listingIds: [Int64],
        addressId: Int64,
        idempotencyKey: String? = nil
    ) async throws -> CheckoutGroup {
        try await c.request(
            .POST,
            "checkout-groups",
            body: .json(JSONDict([
                "listing_ids": listingIds,
                "address_id": addressId,
            ])),
            idempotencyKey: idempotencyKey
        )
    }

    static func paymentMethods() async throws -> [PaymentMethod] { try await c.request(.GET, "payments/methods", auth: false) }
    static func createPayment(orderId: Int64, provider: String) async throws -> Payment {
        try await c.request(.POST, "orders/\(orderId)/payments", body: .json(JSONDict(["provider": provider])))
    }
    static func payment(_ id: Int64) async throws -> Payment { try await c.request(.GET, "payments/\(id)") }
    static func syncPayment(_ id: Int64) async throws -> Payment { try await c.request(.POST, "payments/\(id)/sync") }
    static func mockConfirm(_ id: Int64, success: Bool) async throws -> Payment {
        try await c.request(.POST, "payments/\(id)/mock-confirm", body: .json(JSONDict(["success": success])))
    }

    // MARK: Wallet / Tax (DES-v1.3-08-03 / D31 — channel projection + withdraw)
    /// GET `/me/wallet` — channel pending/available projection (not platform-held balance).
    static func wallet() async throws -> WalletProjection { try await c.request(.GET, "me/wallet") }
    /// GET `/me/wallet/ledger` — channel fund-event mirror with optional `order_no`.
    static func ledger(page: Int = 1) async throws -> Page<WalletLedgerEntry> {
        try await c.request(.GET, "me/wallet/ledger", query: ["page": "\(page)"])
    }
    static func withdrawals() async throws -> [WithdrawalRequest] { try await c.request(.GET, "me/withdrawals") }
    /// POST `/me/withdrawals` — channel withdraw; requires Idempotency-Key (design §5.1 / §6).
    /// Bank fields are ignored by the projection-only path; kept optional for legacy dual-write servers.
    static func requestWithdrawal(
        amount: Money,
        idempotencyKey: String? = nil,
        bankName: String? = nil,
        accountName: String? = nil,
        accountNo: String? = nil
    ) async throws -> WithdrawalRequest {
        var body: [String: Any?] = ["amount": amount]
        if let bankName, !bankName.isEmpty { body["bank_name"] = bankName }
        if let accountName, !accountName.isEmpty { body["account_name"] = accountName }
        if let accountNo, !accountNo.isEmpty { body["account_no"] = accountNo }
        return try await c.request(
            .POST,
            "me/withdrawals",
            body: .json(JSONDict(body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }
    /// POST `/orders/{id}/refunds` — two-phase refund (share return then channel refund).
    static func createOrderRefund(
        orderId: Int64,
        amount: Money,
        reason: String? = nil,
        refundShipping: Bool = WalletConfigDefaults.refundShippingDefault,
        idempotencyKey: String? = nil
    ) async throws -> RefundProgress {
        let req = CreateRefundRequest(amount: amount, reason: reason, refundShipping: refundShipping)
        return try await c.request(
            .POST,
            "orders/\(orderId)/refunds",
            body: .json(JSONDict(req.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }
    /// GET `/orders/{id}/refunds` — latest refund progress for buyer UI (optional; empty → nil).
    static func orderRefunds(orderId: Int64) async throws -> [RefundProgress] {
        try await c.request(.GET, "orders/\(orderId)/refunds")
    }
    static func taxProfile() async throws -> TaxProfile? { try await c.requestOptional(.GET, "me/tax-profile") }
    static func putTaxProfile(_ body: JSONDict) async throws -> TaxProfile { try await c.request(.PUT, "me/tax-profile", body: .json(body)) }
    static func taxRecords(period: String? = nil, page: Int = 1) async throws -> Page<TaxRecord> {
        try await c.request(.GET, "me/tax-records", query: ["period": period, "page": "\(page)"])
    }
    static func taxReports() async throws -> [TaxReport] { try await c.request(.GET, "me/tax-reports") }
    static func exportTaxReport(_ id: Int64) async throws -> Data { try await c.download("me/tax-reports/\(id)/export") }

    // MARK: Income / Profit / Fee costs (DES-v1.3-08-04 FIN-01/02/03 / D32)
    /// GET `/me/income?period=` — seller summary + lines; buyer → `forbidden`.
    static func sellerIncome(period: String, page: Int = 1, pageSize: Int = 20) async throws -> IncomePage {
        try await c.request(
            .GET,
            "me/income",
            query: ["period": period, "page": "\(page)", "page_size": "\(pageSize)"]
        )
    }
    /// PUT `/orders/{id}/cost` — seller-private cost; non-seller → 404 (design §5.9 / §8).
    static func updateOrderCost(
        orderId: Int64,
        costPrice: Money,
        actualShippingCost: Money,
        idempotencyKey: String? = nil
    ) async throws -> OrderCost {
        let req = OrderCostUpdateRequest(costPrice: costPrice, actualShippingCost: actualShippingCost)
        return try await c.request(
            .PUT,
            "orders/\(orderId)/cost",
            body: .json(JSONDict(req.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }
    /// POST `/me/costs/import` — CSV/xlsx rows `order_no,cost_price_yuan` (≤500).
    static func importOrderCosts(fileData: Data, filename: String = "costs.csv") async throws -> CostImportResult {
        try await c.request(
            .POST,
            "me/costs/import",
            body: .multipart(
                files: [(
                    field: "file",
                    filename: filename,
                    mime: filename.hasSuffix(".xlsx")
                        ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        : "text/csv",
                    data: fileData
                )],
                fields: [:]
            ),
            idempotencyKey: APIClient.shared.idempotencyKey()
        )
    }
    /// POST `/me/income/export` — async job; file expires in 7 days (FIN-03).
    static func exportSellerIncome(period: String, format: String = "xlsx") async throws -> IncomeExportJob {
        let req = IncomeExportRequest(period: period, format: format)
        return try await c.request(
            .POST,
            "me/income/export",
            body: .json(JSONDict(req.body)),
            idempotencyKey: APIClient.shared.idempotencyKey()
        )
    }
    /// POST `/me/invoice-requests` with `kind=service_fee` — Phase 3; gate `launch_gate.service_fee_invoice`.
    static func submitServiceFeeInvoice(
        period: String,
        title: String,
        taxNo: String,
        email: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> ServiceFeeInvoiceRequest {
        let body = ServiceFeeInvoiceSubmitBody(period: period, title: title, taxNo: taxNo, email: email)
        return try await c.request(
            .POST,
            "me/invoice-requests",
            body: .json(JSONDict(body.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    // MARK: After-sale / small court (DES-v1.3-09-02 AFS-04～10 / D34)

    /// POST `/orders/{id}/after-sales`
    static func createAfterSale(
        orderId: Int64,
        request: CreateAfterSaleRequest,
        idempotencyKey: String? = nil
    ) async throws -> AfterSale {
        try await c.request(
            .POST,
            "orders/\(orderId)/after-sales",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// GET `/after-sales/{id}`
    static func afterSale(_ id: Int64) async throws -> AfterSale {
        try await c.request(.GET, "after-sales/\(id)")
    }

    /// GET `/orders/{id}/after-sales/current` — active or latest case for order party.
    static func afterSaleForOrder(_ orderId: Int64) async throws -> AfterSale {
        try await c.request(.GET, "orders/\(orderId)/after-sales/current")
    }

    /// POST `/after-sales/{id}/respond` — seller agree/reject/offer.
    static func respondAfterSale(
        id: Int64,
        request: SellerRespondRequest,
        idempotencyKey: String? = nil
    ) async throws -> AfterSale {
        try await c.request(
            .POST,
            "after-sales/\(id)/respond",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// POST `/after-sales/{id}/withdraw`
    static func withdrawAfterSale(id: Int64, idempotencyKey: String? = nil) async throws -> AfterSale {
        try await c.request(
            .POST,
            "after-sales/\(id)/withdraw",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// POST `/after-sales/{id}/escalate`
    static func escalateAfterSale(id: Int64, idempotencyKey: String? = nil) async throws -> Arbitration {
        try await c.request(
            .POST,
            "after-sales/\(id)/escalate",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// POST `/after-sales/{id}/accept-offer`
    static func acceptAfterSaleOffer(id: Int64, idempotencyKey: String? = nil) async throws -> AfterSale {
        try await c.request(
            .POST,
            "after-sales/\(id)/accept-offer",
            body: .json(JSONDict([:] as [String: Any?])),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// POST `/after-sales/{id}/return-tracking`
    static func submitReturnTracking(
        id: Int64,
        trackingNo: String,
        idempotencyKey: String? = nil
    ) async throws -> AfterSale {
        try await c.request(
            .POST,
            "after-sales/\(id)/return-tracking",
            body: .json(JSONDict(["return_tracking": trackingNo])),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// GET `/arbitrations/{id}`
    static func arbitration(_ id: Int64) async throws -> Arbitration {
        try await c.request(.GET, "arbitrations/\(id)")
    }

    /// POST `/arbitrations/{id}/evidence`
    static func submitArbitrationEvidence(
        id: Int64,
        request: ArbitrationEvidenceRequest,
        idempotencyKey: String? = nil
    ) async throws -> Arbitration {
        try await c.request(
            .POST,
            "arbitrations/\(id)/evidence",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// POST `/arbitrations/{id}/appeal`
    static func appealArbitration(
        id: Int64,
        request: ArbitrationAppealRequest,
        idempotencyKey: String? = nil
    ) async throws -> Arbitration {
        try await c.request(
            .POST,
            "arbitrations/\(id)/appeal",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    // MARK: Reports / blocks (DES-v1.3-10-02 RISK-04/07 / D36)

    /// POST `/reports`
    static func createReport(
        _ request: CreateReportRequest,
        idempotencyKey: String? = nil
    ) async throws -> Report {
        try await c.request(
            .POST,
            "reports",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// GET `/me/reports`
    static func myReports(cursor: String? = nil) async throws -> ReportListPage {
        var q: [String: String?] = [:]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await c.request(.GET, "me/reports", query: q)
    }

    /// POST `/me/blocks`
    static func blockUser(_ userId: Int64, idempotencyKey: String? = nil) async throws -> UserBlock {
        try await c.request(
            .POST,
            "me/blocks",
            body: .json(JSONDict(CreateBlockRequest(userId: userId).body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// DELETE `/me/blocks/{user_id}`
    static func unblockUser(_ userId: Int64, idempotencyKey: String? = nil) async throws {
        _ = try await c.request(
            .DELETE,
            "me/blocks/\(userId)",
            idempotencyKey: idempotencyKey
        ) as Empty
    }

    /// GET `/me/blocks`
    static func myBlocks(cursor: String? = nil, page: Int? = nil) async throws -> UserBlockPage {
        var q: [String: String?] = [:]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        if let page { q["page"] = String(page) }
        return try await c.request(.GET, "me/blocks", query: q)
    }

    // MARK: Notifications / push (DES-v1.3-11-01 MSG-01/03/05 / D37)

    /// GET `/notifications?category=&page=&page_size=`
    static func notifications(
        category: String? = nil,
        page: Int = 1,
        pageSize: Int = NotifyConfigDefaults.pageSizeDefault
    ) async throws -> NotificationListPage {
        var q: [String: String?] = [
            "page": "\(page)",
            "page_size": "\(NotifyLogic.clampPageSize(pageSize))",
        ]
        if let category, !category.isEmpty { q["category"] = category }
        return try await c.request(.GET, "notifications", query: q)
    }

    /// GET `/notifications/unread` — five tabs + total from `inbox_counters`.
    static func notificationUnread() async throws -> InboxCounters {
        try await c.request(.GET, "notifications/unread")
    }

    /// POST `/notifications/read` — ids / category / all (Idempotency-Key).
    static func markNotificationsRead(
        _ request: MarkNotificationsReadRequest,
        idempotencyKey: String? = nil
    ) async throws -> MarkNotificationsReadResponse {
        try await c.request(
            .POST,
            "notifications/read",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    /// DELETE `/notifications/{id}`
    static func deleteNotification(_ id: Int64) async throws {
        _ = try await c.request(.DELETE, "notifications/\(id)") as Empty
    }

    /// PUT `/me/push-tokens` — iOS APNs only.
    static func registerPushToken(
        _ registration: PushTokenRegistration,
        idempotencyKey: String? = nil
    ) async throws {
        if let err = NotifyLogic.validatePushTokenPlatform(registration.platform) {
            throw APIError(code: err.rawValue, message: err.fallbackMessage, status: 400)
        }
        _ = try await c.request(
            .PUT,
            "me/push-tokens",
            body: .json(JSONDict(registration.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        ) as Empty
    }

    /// DELETE `/me/push-tokens`
    static func deletePushToken(_ token: String) async throws {
        _ = try await c.request(
            .DELETE,
            "me/push-tokens",
            body: .json(JSONDict(["token": token]))
        ) as Empty
    }

    /// GET `/me/push-settings`
    static func pushSettings() async throws -> PushSettingsPayload {
        try await c.request(.GET, "me/push-settings")
    }

    /// PUT `/me/push-settings`
    static func updatePushSettings(
        _ request: UpdatePushSettingsRequest,
        idempotencyKey: String? = nil
    ) async throws -> PushSettingsPayload {
        if let err = NotifyLogic.validatePushSettingsUpdate(request.items) {
            throw APIError(code: err.rawValue, message: err.fallbackMessage, status: 400)
        }
        return try await c.request(
            .PUT,
            "me/push-settings",
            body: .json(JSONDict(request.body)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    // MARK: Chat (DES-v1.3-11-02 MSG-02 / D38)
    static func conversations() async throws -> [Conversation] { try await c.request(.GET, "conversations") }
    /// Open / reuse conversation by subject (design §5.1 / §6). Legacy `lot_id` still accepted by server.
    static func openConversation(
        subjectType: ConversationSubjectType,
        subjectId: Int64,
        idempotencyKey: String? = nil
    ) async throws -> Conversation {
        try await c.request(
            .POST,
            "conversations",
            body: .json(JSONDict([
                "subject_type": subjectType.rawValue,
                "subject_id": subjectId,
                // Dual-write during migration window (design §13).
                "lot_id": subjectType == .lot ? subjectId : 0,
            ])),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }
    static func openConversation(lotId: Int64) async throws -> Conversation {
        try await openConversation(subjectType: .lot, subjectId: lotId)
    }
    static func openConversation(listingId: Int64) async throws -> Conversation {
        try await openConversation(subjectType: .listing, subjectId: listingId)
    }
    static func openConversation(orderId: Int64) async throws -> Conversation {
        try await openConversation(subjectType: .order, subjectId: orderId)
    }
    static func markAllConversationsRead() async throws {
        _ = try await c.request(.POST, "conversations/read-all") as Empty
    }
    static func markConversationRead(_ convId: Int64, lastMessageId: Int64? = nil) async throws {
        var body: [String: Any?] = [:]
        if let lastMessageId { body["last_message_id"] = lastMessageId }
        _ = try await c.request(
            .POST,
            "conversations/\(convId)/read",
            body: .json(JSONDict(body))
        ) as Empty
    }
    static func messages(_ convId: Int64, before: Int64? = nil) async throws -> [Message] {
        try await c.request(.GET, "conversations/\(convId)/messages", query: ["before": before.map(String.init), "limit": "50"])
    }
    static func send(
        _ convId: Int64,
        type: MessageType,
        content: String,
        payload: [String: Any]? = nil,
        listingId: Int64? = nil,
        orderId: Int64? = nil,
        idempotencyKey: String? = nil
    ) async throws -> Message {
        if let err = ChatLogic.validateClientSend(kind: type.chatKind) {
            throw APIError(code: err.rawValue, message: err.fallbackMessage, status: 400)
        }
        var dict: [String: Any?] = [
            "type": type.rawValue,
            "content": content,
        ]
        if let payload { dict["payload"] = payload }
        if let listingId { dict["listing_id"] = listingId }
        if let orderId { dict["order_id"] = orderId }
        return try await c.request(
            .POST,
            "conversations/\(convId)/messages",
            body: .json(JSONDict(dict)),
            idempotencyKey: idempotencyKey ?? APIClient.shared.idempotencyKey()
        )
    }

    // MARK: Upload
    struct UploadResponse: Decodable {
        let urls: [String]?
        let images: [UploadImageItem]?
    }
    struct UploadImageItem: Decodable {
        let imageId: String?
        let url: String?
        let id: String?
    }
    struct PublishUploadItem {
        let imageId: String?
        let url: String?
    }
    static func upload(images: [Data]) async throws -> [String] {
        let items = try await uploadPublishImages(images)
        return items.compactMap(\.url)
    }
    /// Publish upload — prefers `image_id` when server returns it (DES §5.4 / §6).
    static func uploadPublishImages(_ images: [Data]) async throws -> [PublishUploadItem] {
        let files = images.enumerated().map { (field: "images", filename: "photo\($0.offset).jpg", mime: "image/jpeg", data: $0.element) }
        let r: UploadResponse = try await c.request(.POST, "upload/images", body: .multipart(files: files, fields: [:]))
        if let images = r.images, !images.isEmpty {
            return images.map {
                PublishUploadItem(imageId: $0.imageId ?? $0.id, url: $0.url)
            }
        }
        return (r.urls ?? []).map { PublishUploadItem(imageId: nil, url: $0) }
    }
}
