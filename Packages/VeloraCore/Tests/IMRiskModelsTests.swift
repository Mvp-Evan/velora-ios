import XCTest
@testable import VeloraCore

final class IMRiskModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let s = try? c.decode(String.self) {
                let withFrac = ISO8601DateFormatter()
                withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let dt = withFrac.date(from: s) { return dt }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let dt = plain.date(from: s) { return dt }
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            if let ms = try? c.decode(Int64.self) {
                return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date"))
        }
        return d
    }()

    // MARK: Config (design §3)

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(IMRiskConfigDefaults.interceptWindowDays, 7)
        XCTAssertEqual(IMRiskConfigDefaults.interceptThreshold, 3)
        XCTAssertEqual(IMRiskConfigDefaults.muteHours, 72)
        XCTAssertEqual(IMRiskConfigDefaults.pureAmountRegex, #"^[¥￥]?\d{1,8}([.．]\d{1,2})?[元块]?$"#)
        XCTAssertEqual(IMRiskConfigDefaults.imageScanEnabledKey, "risk.image_scan.enabled")
        XCTAssertFalse(IMRiskConfigDefaults.imageScanEnabledDefault)
        XCTAssertEqual(IMRiskConfigDefaults.warnBannerDedupeMinutes, 10)
        XCTAssertEqual(IMRiskConfigDefaults.notifyCode, "N-24")
        XCTAssertEqual(IMRiskConfigDefaults.creditReasonMute, "im_sensitive_mute")
        XCTAssertEqual(IMRiskConfigDefaults.creditDeltaMute, -5)
        XCTAssertTrue(IMRiskConfigDefaults.whitelistMessageTypes.contains("offer_card"))
        XCTAssertTrue(IMRiskConfigDefaults.whitelistMessageTypes.contains("listing_card"))
        XCTAssertTrue(IMRiskConfigDefaults.whitelistMessageTypes.contains("order_card"))
    }

    // MARK: Error codes / actions

    func testFilterInterceptErrorCodes() {
        XCTAssertEqual(IMRiskErrorCode.contentBlocked.rawValue, "content_blocked")
        XCTAssertEqual(IMRiskErrorCode.imMuted.rawValue, "im_muted")
        XCTAssertEqual(IMRiskErrorCode.blockedByUser.rawValue, "blocked_by_user")
        XCTAssertEqual(IMRiskErrorCode.contentReviewPending.rawValue, "content_review_pending")
        XCTAssertEqual(IMRiskErrorCode.featureDisabled.rawValue, "feature_disabled")
        XCTAssertEqual(IMRiskErrorCode.normalize("message_blocked"), .contentBlocked)
        XCTAssertEqual(IMRiskErrorCode.normalize("MUTED"), .imMuted)
        XCTAssertTrue(IMRiskErrorCode.contentBlocked.showsInterceptBanner)
        XCTAssertTrue(IMRiskErrorCode.imMuted.showsMuteComposer)
        XCTAssertTrue(IMRiskErrorCode.contentBlocked.preservesDraft)
        XCTAssertTrue(IMRiskErrorCode.contentBlocked.fallbackMessage.contains("未发送"))
        XCTAssertFalse(IMRiskErrorCode.contentBlocked.fallbackMessage.contains("微信"))
    }

    func testRiskActionSeverityAndDecision() {
        XCTAssertEqual(RiskAction.stricter(.warn, .block), .block)
        XCTAssertEqual(RiskAction.stricter(.log, .warn), .warn)
        XCTAssertEqual(RiskAction.normalize("intercept"), .block)
        XCTAssertEqual(RiskAction.block.filterDecision, .drop)
        XCTAssertEqual(RiskAction.warn.filterDecision, .allowWithWarn)
        XCTAssertEqual(RiskFilterDecision.normalize("allow_with_warn"), .allowWithWarn)
        XCTAssertTrue(RiskAction.warn.showsWarnBanner)
        XCTAssertTrue(RiskAction.block.showsSenderInterceptBanner)
        XCTAssertFalse(RiskAction.log.showsUI)
    }

    func testRiskCategoryNormalize() {
        XCTAssertEqual(RiskCategory.normalize("induce_pay"), .inducePay)
        XCTAssertEqual(RiskCategory.normalize("amount-only"), .amountOnly)
        XCTAssertEqual(RiskCategory.contact.displayLabel, "联系方式")
    }

    // MARK: Mute state

    func testMuteStateLifecycle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(IMRiskLogic.muteState(until: nil, now: now), .none)
        XCTAssertEqual(IMRiskLogic.muteState(until: now.addingTimeInterval(3600), now: now), .muted)
        XCTAssertEqual(IMRiskLogic.muteState(until: now.addingTimeInterval(-1), now: now), .expired)
        XCTAssertFalse(IMMuteState.muted.canSendIM)
        XCTAssertTrue(IMMuteState.muted.composerDisabled)
        XCTAssertTrue(IMMuteState.none.canSendIM)
        XCTAssertEqual(IMMuteState.normalize("im_muted"), .muted)
    }

    func testUserIMMuteDecodeAndComposer() throws {
        let json = """
        {"until":"2026-11-08T12:00:00Z","source":"lexicon_block","window_hit_count":3}
        """.data(using: .utf8)!
        let mute = try decoder.decode(UserIMMute.self, from: json)
        XCTAssertEqual(mute.windowHitCount, 3)
        XCTAssertEqual(mute.source, "lexicon_block")
        let before = Date(timeIntervalSince1970: 1_794_000_000) // ~2026-11-05
        XCTAssertEqual(mute.state(now: before), .muted)
        let composer = IMRiskLogic.composerState(muteUntil: mute.until, serverNow: before)
        XCTAssertFalse(composer.isEnabled)
        XCTAssertTrue(composer.placeholder.hasPrefix("禁言至"))
        XCTAssertEqual(composer.mute, .muted)
    }

    func testComposerEnabledWhenMuteExpired() {
        let until = Date(timeIntervalSince1970: 1_700_000_000)
        let now = until.addingTimeInterval(10)
        let composer = IMRiskLogic.composerState(muteUntil: until, serverNow: now)
        XCTAssertTrue(composer.isEnabled)
        XCTAssertEqual(composer.placeholder, "说点什么…")
    }

    // MARK: Offer card whitelist UX copy (T-07)

    func testOfferCardWhitelistSkipsLexiconAndCopy() {
        XCTAssertTrue(IMRiskLogic.shouldSkipLexicon(messageType: "offer_card"))
        XCTAssertTrue(IMRiskLogic.shouldSkipLexicon(messageType: "offer"))
        XCTAssertTrue(IMRiskLogic.isWhitelistMessageType("listing_card"))
        XCTAssertTrue(IMRiskLogic.isWhitelistMessageType("ORDER_CARD"))
        XCTAssertFalse(IMRiskLogic.shouldSkipLexicon(messageType: "text"))
        XCTAssertFalse(IMRiskLogic.shouldSkipLexicon(messageType: "image"))
        let copy = IMRiskLogic.offerWhitelistCopy(messageType: OfferConfigDefaults.messageTypeOfferCard)
        XCTAssertEqual(copy, IMRiskCopy.offerWhitelistHint)
        XCTAssertTrue(IMRiskCopy.offerWhitelistHint.contains("报价卡片"))
        XCTAssertTrue(IMRiskCopy.offerWhitelistSkipNote.contains("白名单"))
        XCTAssertEqual(OfferConfigDefaults.messageTypeOfferCard, "offer_card")
    }

    func testPureAmountLooksLikeRegexButDoesNotImplyLocalBlock() {
        XCTAssertTrue(IMRiskLogic.looksLikePureAmount("2500元"))
        XCTAssertTrue(IMRiskLogic.looksLikePureAmount("¥2500"))
        XCTAssertTrue(IMRiskLogic.looksLikePureAmount("2500.50块"))
        XCTAssertFalse(IMRiskLogic.looksLikePureAmount("微2500"))
        XCTAssertFalse(IMRiskLogic.looksLikePureAmount("2500 加v"))
        XCTAssertTrue(IMRiskCopy.pureAmountHint.contains("可发送"))
    }

    // MARK: Banners / N-24

    func testInterceptAndWarnBannerCopy() {
        let block = IMRiskLogic.interceptBanner()
        XCTAssertEqual(block.kind, .intercept)
        XCTAssertTrue(block.showsOfferCTA)
        XCTAssertTrue(block.text.contains("未发送"))
        XCTAssertTrue(block.text.contains("报价卡片"))
        XCTAssertEqual(block.accessibilityLabel, "风险提示")

        let warn = IMRiskLogic.warnBanner(category: .abuse)
        XCTAssertEqual(warn.kind, .warn)
        XCTAssertEqual(warn.text, IMRiskCopy.warnBanner)
        XCTAssertEqual(warn.category, .abuse)

        let fromRisk = IMRiskLogic.banner(for: MessageRiskInfo(action: .warn, notice: "请勿站外交易，平台无法保护", category: .abuse))
        XCTAssertEqual(fromRisk?.kind, .warn)
        XCTAssertNil(IMRiskLogic.banner(for: MessageRiskInfo(action: .log)))
    }

    func testWarnBannerDedupeTenMinutes() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(IMRiskLogic.shouldShowWarnBanner(category: .abuse, lastShownCategory: nil, lastShownAt: nil, now: t0))
        XCTAssertFalse(IMRiskLogic.shouldShowWarnBanner(
            category: .abuse,
            lastShownCategory: .abuse,
            lastShownAt: t0,
            now: t0.addingTimeInterval(5 * 60)
        ))
        XCTAssertTrue(IMRiskLogic.shouldShowWarnBanner(
            category: .abuse,
            lastShownCategory: .abuse,
            lastShownAt: t0,
            now: t0.addingTimeInterval(10 * 60)
        ))
        XCTAssertTrue(IMRiskLogic.shouldShowWarnBanner(
            category: .contact,
            lastShownCategory: .abuse,
            lastShownAt: t0,
            now: t0.addingTimeInterval(60)
        ))
    }

    func testMessageRiskInfoDecode() throws {
        let json = """
        {"action":"warn","notice":"请勿站外交易，平台无法保护","category":"abuse"}
        """.data(using: .utf8)!
        let risk = try decoder.decode(MessageRiskInfo.self, from: json)
        XCTAssertEqual(risk.action, .warn)
        XCTAssertEqual(risk.category, .abuse)
        XCTAssertEqual(risk.displayNotice, IMRiskCopy.warnBanner)

        let blockJSON = #"{"action":"block","message":"该内容疑似诱导站外交易，未发送"}"#.data(using: .utf8)!
        let blocked = try decoder.decode(MessageRiskInfo.self, from: blockJSON)
        XCTAssertEqual(blocked.action, .block)
        XCTAssertEqual(blocked.notice, IMRiskCopy.blockedNotice)
    }

    func testErrorBannerMapping() {
        let intercept = IMRiskLogic.banner(forErrorCode: .contentBlocked)
        XCTAssertEqual(intercept?.kind, .intercept)
        let until = Date(timeIntervalSince1970: 1_794_139_200)
        let mute = IMRiskLogic.banner(forErrorCode: .imMuted, muteUntil: until, serverNow: Date(timeIntervalSince1970: 1_794_000_000))
        XCTAssertEqual(mute?.kind, .mute)
        XCTAssertTrue(mute?.text.contains("禁言至") == true)
        XCTAssertTrue(mute?.text.contains("客服") == true)
        XCTAssertNil(IMRiskLogic.banner(forErrorCode: .blockedByUser))
    }

    // MARK: Image scan placeholder (RISK-03)

    func testImageScanFeatureDisabledPlaceholder() {
        let off = IMRiskLogic.imageScanPlaceholder(enabled: false)
        XCTAssertEqual(off.status, .skipped)
        XCTAssertTrue(off.isFeatureDisabledPlaceholder)
        XCTAssertEqual(off.errorCode, "feature_disabled")
        XCTAssertEqual(IMRiskCopy.imageScanFeatureDisabled, IMRiskErrorCode.featureDisabled.fallbackMessage)

        let on = IMRiskLogic.imageScanPlaceholder(enabled: true)
        XCTAssertEqual(on.status, .pending)
        XCTAssertFalse(on.isFeatureDisabledPlaceholder)
        XCTAssertEqual(RiskImageScanStatus.normalize("feature_disabled"), .skipped)
    }

    func testTruncateAndParseMuteUntil() {
        let long = String(repeating: "a", count: 2_100)
        XCTAssertEqual(IMRiskLogic.truncateForFilter(long).count, 2_000)
        let iso = "禁言至 2026-11-08T12:00:00Z 解除"
        let parsed = IMRiskLogic.parseMuteUntil(from: iso)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(IMRiskLogic.parseMuteUntil(from: "1794139200000")?.timeIntervalSince1970, 1_794_139_200)
    }
}
