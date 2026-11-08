import Foundation
import SwiftUI

/// Publish wizard state: local autosave + optional cloud draft (DES-v1.3-02-05 PUB-04 / DES-v1.3-03-01).
@MainActor
final class PublishWizardModel: ObservableObject {
    @Published var draft: PublishDraftPayload
    @Published var feeQuote: FeeQuoteEstimate?
    @Published var feeLoading = false
    @Published var feeFailed = false
    @Published var uploading = false
    @Published var submitting = false
    @Published var syncingCloud = false
    @Published var conflictCloud: CloudPublishDraft?
    @Published var showConflict = false
    @Published var compressProgress: String?
    /// Live bid-increment ladder from `GET /meta/bid-increments` (defaults until loaded).
    @Published var bidTiers: BidIncrementTiersResponse = BidIncrementLadder.defaultResponse
    /// Present sub-merchant half-sheet when publish returns `sub_merchant_required` (DES-v1.3-08-01 §9).
    var onSubMerchantRequired: (() -> Void)?
    /// Present seller deposit page when publish returns `seller_deposit_insufficient` (DES-v1.3-08-02 §9).
    var onSellerDepositRequired: (() -> Void)?

    let tradeType: PublishTradeType
    private var feeTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private let localKey: String

    init(tradeType: PublishTradeType) {
        self.tradeType = tradeType
        self.localKey = "publish_draft_v3_\(tradeType.rawValue)"
        if let loaded = Self.loadLocal(key: localKey), loaded.tradeType == tradeType {
            draft = loaded
        } else {
            draft = PublishDraftPayload(tradeType: tradeType)
        }
        applySellerAuctionKindDefaults()
    }

    var sellerTypeRaw: String? {
        SessionStore.shared.bootstrap?.seller?.sellerType
            ?? SessionStore.shared.bootstrap?.me?.sellerType
    }

    var auctionSellerType: AuctionSellerType {
        AuctionSellerType(raw: sellerTypeRaw)
    }

    var allowedAuctionKinds: [AuctionKind] {
        auctionSellerType.allowedAuctionKinds
    }

    var resolvedAuctionKind: AuctionKind {
        AuctionKindResolver.resolve(sellerTypeRaw: sellerTypeRaw, preferred: draft.auctionKind)
    }

    var liveTips: PublishAuctionLiveTips {
        PublishAuctionLiveTips.make(
            startPriceFen: draft.priceFen,
            incrementFen: PublishDraftPayload.yuanToFen(draft.incrementYuan),
            depositFen: PublishDraftPayload.yuanToFen(draft.depositYuan),
            durationDays: draft.durationDays,
            useCustomEndAt: draft.useCustomEndAt,
            endAt: draft.endAt,
            auctionKind: resolvedAuctionKind,
            tiers: bidTiers.tiers
        )
    }

    func applySellerAuctionKindDefaults() {
        guard tradeType == .auction else { return }
        let kind = AuctionKindResolver.resolve(sellerTypeRaw: sellerTypeRaw, preferred: draft.auctionKind)
        draft.auctionKind = kind.rawValue
    }

    func loadBidIncrements() async {
        do {
            bidTiers = try await API.bidIncrements()
            if bidTiers.tiers.isEmpty {
                bidTiers = BidIncrementLadder.defaultResponse
            }
        } catch {
            bidTiers = BidIncrementLadder.defaultResponse
        }
        syncIncrementFloor()
    }

    // MARK: Persistence

    private static func loadLocal(key: String) -> PublishDraftPayload? {
        guard let raw = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PublishDraftPayload.self, from: raw)
    }

    func saveLocal() {
        draft.touch()
        if let raw = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(raw, forKey: localKey)
        }
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveLocal()
        }
    }

    func reset() {
        draft = PublishDraftPayload(tradeType: tradeType)
        feeQuote = nil
        feeFailed = false
        UserDefaults.standard.removeObject(forKey: localKey)
    }

    // MARK: Cloud draft

    func reconcileCloudOnAppear() async {
        guard SessionStore.shared.isLoggedIn else { return }
        syncingCloud = true
        defer { syncingCloud = false }
        do {
            let page = try await API.myPublishDrafts(tradeType: tradeType.rawValue)
            guard let remote = page.items.first else { return }
            let preferCloud = PublishDraftSync.preferCloud(local: draft.updatedAt, cloud: remote.updatedAt)
            if preferCloud, remote.payload != nil || remote.id != draft.cloudListingId {
                conflictCloud = remote
                showConflict = true
            }
        } catch {
            // Offline: keep local; cloud sync is best-effort.
        }
    }

    func resolveConflict(_ resolution: PublishDraftConflictResolution) {
        defer {
            showConflict = false
            conflictCloud = nil
        }
        guard let cloud = conflictCloud else { return }
        switch resolution {
        case .keepLocal:
            break
        case .useCloud:
            if var payload = cloud.payload {
                payload.cloudListingId = cloud.id
                payload.tradeType = tradeType
                draft = payload
                saveLocal()
            } else {
                draft.cloudListingId = cloud.id
            }
        }
    }

    func saveCloudDraft() async throws {
        draft.touch()
        let body = draftBody(status: .draft)
        let result: PublishSubmitResult
        if let id = draft.cloudListingId {
            result = try await API.patchPublishDraft(id: id, body: body)
        } else {
            result = try await API.createListing(body)
            draft.cloudListingId = result.listingId
        }
        saveLocal()
        _ = result
    }

    // MARK: Fee

    func scheduleFeeEstimate() {
        feeTask?.cancel()
        guard let price = draft.priceFen, price >= PublishLimits.minPriceFen else {
            feeQuote = nil
            feeFailed = false
            return
        }
        feeTask = Task {
            try? await Task.sleep(for: .milliseconds(PublishLimits.feeDebounceMs))
            guard !Task.isCancelled else { return }
            await refreshFee(price: price)
        }
    }

    private func refreshFee(price: Int64) async {
        feeLoading = true
        defer { feeLoading = false }
        do {
            let quote = try await API.estimateFeeQuote(
                tradeType: tradeType.rawValue,
                price: price,
                shippingFee: draft.shippingFeeFen
            )
            feeQuote = quote
            draft.feeQuoteId = quote.feeQuoteId
            feeFailed = false
            scheduleAutosave()
        } catch {
            feeFailed = true
            // Keep last quote for weak network (DES §9).
        }
    }

    // MARK: Images

    func importProductPhotos(_ datas: [Data]) async {
        await importPhotos(datas, asFlaw: false)
    }

    func importFlawPhotos(_ datas: [Data]) async {
        await importPhotos(datas, asFlaw: true)
    }

    private func importPhotos(_ datas: [Data], asFlaw: Bool) async {
        guard !datas.isEmpty else { return }
        uploading = true
        defer {
            uploading = false
            compressProgress = nil
        }
        var prepared: [(Data, String)] = []
        for (i, raw) in datas.enumerated() {
            compressProgress = "压缩 \(i + 1)/\(datas.count)"
            do {
                let r = try PublishImageProcessor.process(raw)
                prepared.append((r.jpeg, r.sha256))
            } catch PublishImageProcessor.ProcessError.tooLargeBeforeCompress {
                ToastCenter.shared.show(PublishErrorCode.imageTooLarge.fallbackMessage, .error)
            } catch {
                ToastCenter.shared.show("图片处理失败", .error)
            }
        }
        guard !prepared.isEmpty else { return }

        let maxCount = asFlaw ? PublishLimits.flawImageMax : PublishLimits.productImageMax
        let current = asFlaw ? draft.flawImages.count : draft.productImages.count
        let room = max(0, maxCount - current)
        let slice = Array(prepared.prefix(room))
        guard !slice.isEmpty else { return }

        do {
            let uploaded = try await API.uploadPublishImages(slice.map(\.0))
            for (idx, up) in uploaded.enumerated() {
                let sha = slice[idx].1
                let role: PublishImageRole
                if asFlaw {
                    role = .flaw
                } else {
                    role = (draft.productImages.isEmpty && idx == 0) ? .cover : .gallery
                }
                let slot = PublishImageSlot(
                    imageId: up.imageId,
                    url: up.url,
                    sha256: sha,
                    role: role
                )
                if asFlaw {
                    draft.flawImages.append(slot)
                } else {
                    draft.productImages.append(slot)
                    if draft.productImages.count == 1 {
                        draft.productImages[0].role = .cover
                    }
                }
            }
            normalizeCover()
            scheduleAutosave()
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func removeProductImage(at index: Int) {
        guard draft.productImages.indices.contains(index) else { return }
        draft.productImages.remove(at: index)
        normalizeCover()
        scheduleAutosave()
    }

    func removeFlawImage(at index: Int) {
        guard draft.flawImages.indices.contains(index) else { return }
        draft.flawImages.remove(at: index)
        scheduleAutosave()
    }

    func moveProductImage(from: IndexSet, to: Int) {
        draft.productImages.move(fromOffsets: from, toOffset: to)
        normalizeCover()
        scheduleAutosave()
    }

    private func normalizeCover() {
        for i in draft.productImages.indices {
            draft.productImages[i].role = i == 0 ? .cover : .gallery
        }
    }

    func syncDepositDefault() {
        guard tradeType == .auction, let start = draft.priceFen else { return }
        let floor = PublishDeposit.defaultAmount(startPriceFen: start)
        let yuan = String(format: "%.0f", Double(floor) / 100)
        if let current = PublishDraftPayload.yuanToFen(draft.depositYuan), current >= floor {
            return
        }
        draft.depositYuan = yuan
    }

    /// Raise locked-in increment to the ladder floor for the current start price (seller may set higher).
    func syncIncrementFloor() {
        guard tradeType == .auction, let start = draft.priceFen, start > 0 else { return }
        let floor = BidIncrementLadder.minIncrement(forPriceFen: start, tiers: bidTiers.tiers)
        let yuan = String(format: "%.0f", Double(floor) / 100)
        if let current = PublishDraftPayload.yuanToFen(draft.incrementYuan), current >= floor {
            return
        }
        draft.incrementYuan = yuan
    }

    func setAuctionKind(_ kind: AuctionKind) {
        guard allowedAuctionKinds.contains(kind) else { return }
        draft.auctionKind = kind.rawValue
        scheduleAutosave()
    }

    // MARK: Validation / submit

    var enabledScales: [String] {
        let f = FiltersStore.shared.filters
        return f.effectiveScales.isEmpty ? [PublishLimits.defaultScale] : f.effectiveScales
    }

    var canSubmit: Bool {
        PublishValidator.validateTitle(draft.title)
            && PublishValidator.validate(draft, enabledScales: enabledScales, requireFeeQuote: true) == nil
            && !feeFailed
    }

    var validationMessage: String? {
        if !PublishValidator.validateTitle(draft.title) {
            return "标题需 \(PublishLimits.titleMin)–\(PublishLimits.titleMax) 字"
        }
        if let err = PublishValidator.validate(draft, enabledScales: enabledScales, requireFeeQuote: true) {
            return err.fallbackMessage
        }
        if feeFailed { return PublishErrorCode.feeUnavailable.fallbackMessage }
        return nil
    }

    func submit() async -> PublishSubmitResult? {
        guard canSubmit else {
            if let msg = validationMessage { ToastCenter.shared.show(msg, .error) }
            return nil
        }
        submitting = true
        defer { submitting = false }
        do {
            let body = draftBody(status: nil)
            let result: PublishSubmitResult
            switch tradeType {
            case .fixed:
                result = try await API.createListing(body)
            case .auction:
                result = try await API.createLotPublish(body)
            }
            reset()
            return result
        } catch let e as APIError {
            handleSubmitError(e)
            return nil
        } catch {
            ToastCenter.shared.error(error)
            return nil
        }
    }

    private func handleSubmitError(_ e: APIError) {
        if e.code == PublishErrorCode.subMerchantRequired.rawValue
            || e.code == ProfitSharingErrorCode.subMerchantRequired.rawValue
            || e.code == ProfitSharingErrorCode.onboardingFailed.rawValue {
            onSubMerchantRequired?()
            return
        }
        if e.code == PublishErrorCode.sellerDepositInsufficient.rawValue
            || e.code == DepositErrorCode.sellerDepositInsufficient.rawValue {
            ToastCenter.shared.show(
                e.message.isEmpty ? DepositCopy.sellerGapTitle : e.message,
                .info
            )
            onSellerDepositRequired?()
            return
        }
        if let code = PublishErrorCode(rawValue: e.code) {
            ToastCenter.shared.show(e.message.isEmpty ? code.fallbackMessage : e.message, .error)
            return
        }
        if e.trustCode == .realNameRequired {
            ToastCenter.shared.show(e.trustMessage, .info)
            AppRouterProxy.openRealName()
            return
        }
        if e.trustCode == .sellerOnboarding {
            ToastCenter.shared.show(e.trustMessage, .info)
            AppRouterProxy.openSellerOnboarding()
            return
        }
        if e.restrictionCode == .publishForbidden {
            ToastCenter.shared.show(e.restrictionMessage, .info)
            return
        }
        if ReviewCreditErrorCode.normalize(e.code)?.isCreditBlock == true {
            let score = SessionStore.shared.bootstrap?.me?.creditScore ?? SessionStore.shared.user?.creditScore
            AppRouterProxy.presentCreditBlock(code: e.code, score: score, action: "发布")
            return
        }
        ToastCenter.shared.error(e)
    }

    private func draftBody(status: PublishListingStatus?) -> JSONDict {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var map: [String: Any?] = [
            "trade_type": tradeType.rawValue,
            "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": draft.description,
            "brand": draft.brand.isEmpty ? nil : draft.brand,
            "custom_brand": draft.customBrand,
            "series": draft.series.isEmpty ? nil : draft.series,
            "custom_series": draft.customSeries,
            "model": draft.model.isEmpty ? nil : draft.model,
            "custom_model": draft.customModel,
            "scale": draft.scale.isEmpty ? PublishLimits.defaultScale : draft.scale,
            "color": draft.color.isEmpty ? nil : draft.color,
            "material": draft.material.isEmpty ? nil : draft.material,
            "custom_material": draft.customMaterial,
            "limited_no": draft.limitedNo.isEmpty ? nil : draft.limitedNo,
            "condition": draft.condition,
            "flaw_desc": draft.flawDesc.isEmpty ? nil : draft.flawDesc,
            "image_ids": draft.productImages.compactMap(\.imageId),
            "images": draft.productImages.compactMap(\.url),
            "flaw_image_ids": draft.flawImages.compactMap(\.imageId),
            "flaw_images": draft.flawImages.compactMap(\.url),
            "free_shipping": draft.freeShipping,
            "shipping_fee": draft.freeShipping ? 0 : draft.shippingFeeFen,
            "ship_province": draft.shipProvince.isEmpty ? nil : draft.shipProvince,
            "ship_city": draft.shipCity.isEmpty ? nil : draft.shipCity,
            "cost_price": PublishDraftPayload.yuanToFen(draft.costPriceYuan),
            "fee_quote_id": draft.feeQuoteId,
        ]
        if let status {
            map["status"] = status.rawValue
        }
        switch tradeType {
        case .fixed:
            map["price"] = draft.priceFen
            map["stock"] = draft.stock
            map["negotiable"] = draft.negotiable
        case .auction:
            let start = draft.priceFen
            let kind = resolvedAuctionKind
            map["start_price"] = start
            map["auction_kind"] = kind.rawValue
            map["bid_increment"] = PublishDraftPayload.yuanToFen(draft.incrementYuan)
            map["reserve_price"] = PublishDraftPayload.yuanToFen(draft.reservePriceYuan)
            let deposit = PublishDraftPayload.yuanToFen(draft.depositYuan)
                ?? (start.map { PublishDeposit.defaultAmount(startPriceFen: $0) })
            map["deposit_amount"] = deposit
            if kind.requiresEditionNo {
                map["edition_no"] = draft.limitedNo.isEmpty ? nil : draft.limitedNo
            }
            map["start_at"] = draft.startNow ? nil : iso.string(from: draft.startAt)
            if kind == .proxySession {
                // Session lots are scheduled by ops — omit free-end schedule fields.
                map["end_at"] = nil
                map["duration_code"] = nil
            } else if draft.useCustomEndAt {
                map["end_at"] = iso.string(from: draft.endAt)
            } else if let code = PublishAuctionDuration.durationCode(days: draft.durationDays) {
                map["duration_code"] = code
                map["duration_days"] = draft.durationDays
                map["duration_seconds"] = draft.durationDays * 86400
            } else {
                map["duration_days"] = draft.durationDays
                map["duration_seconds"] = draft.durationDays * 86400
            }
        }
        return JSONDict(map)
    }
}

/// Avoid retain cycles on router from model without EnvironmentObject.
@MainActor
enum AppRouterProxy {
    static weak var router: AppRouter?
    static func openRealName() { router?.openRealName() }
    static func openSellerOnboarding() { router?.openSellerOnboarding() }
    static func openSubMerchantProgress() { router?.openSubMerchantProgress() }
    static func presentCreditBlock(code: String?, score: Int? = nil, action: String = ReviewCreditCopy.defaultBlockedAction) {
        router?.presentCreditBlock(code: code, score: score, action: action)
    }
}
