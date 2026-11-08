import XCTest
@testable import VeloraCore

final class ChatModelsTests: XCTestCase {
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

    // MARK: Config (design §15)

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(ChatConfigDefaults.lotEndingLeadSec, 5 * 60)
        XCTAssertEqual(ChatConfigDefaults.payLeadSec, 2 * 60 * 60)
        XCTAssertEqual(ChatConfigDefaults.lotteryPayLeadSec, 30 * 60)
        XCTAssertEqual(ChatConfigDefaults.balanceLead24hSec, 24 * 60 * 60)
        XCTAssertEqual(ChatConfigDefaults.balanceLead2hSec, 2 * 60 * 60)
        XCTAssertEqual(ChatConfigDefaults.mergeSec, 60)
        XCTAssertEqual(ChatConfigDefaults.ratePerMin, 30)
        XCTAssertEqual(ChatConfigDefaults.maxText, 1_000)
        XCTAssertEqual(ChatConfigDefaults.imageMaxMB, 5)
        XCTAssertEqual(ChatConfigDefaults.retainYears, 3)
        XCTAssertEqual(ChatConfigDefaults.cardMinTapHeightPt, 44)
        XCTAssertEqual(ChatConfigDefaults.fiveContentKinds.count, 5)
        XCTAssertEqual(
            ChatConfigDefaults.fiveContentKinds.map(\.rawValue),
            ["text", "image", "listing_card", "order_card", "offer_card"]
        )
    }

    // MARK: Five message kinds + lot_card mapping (MSG-02 / §3)

    func testFiveContentKindsAndLegacyLotCardMapsToListing() {
        XCTAssertEqual(ChatMessageKind.normalize("text"), .text)
        XCTAssertEqual(ChatMessageKind.normalize("image"), .image)
        XCTAssertEqual(ChatMessageKind.normalize("listing_card"), .listingCard)
        XCTAssertEqual(ChatMessageKind.normalize("order_card"), .orderCard)
        XCTAssertEqual(ChatMessageKind.normalize("offer_card"), .offerCard)
        XCTAssertEqual(ChatMessageKind.normalize("lot_card"), .listingCard)
        XCTAssertEqual(ChatMessageKind.normalize("LOT_CARD"), .listingCard)
        XCTAssertTrue(ChatLogic.isLegacyLotCard("lot_card"))
        XCTAssertFalse(ChatLogic.isLegacyLotCard("listing_card"))
        XCTAssertEqual(ChatMessageKind.listingCard.wireValue, "listing_card")
        XCTAssertTrue(ChatLogic.isFiveContentKind(.listingCard))
        XCTAssertFalse(ChatLogic.isFiveContentKind(.system))
        XCTAssertFalse(ChatLogic.isFiveContentKind(.riskBanner))
    }

    func testClientMayNotForgeOfferCard() {
        XCTAssertNil(ChatLogic.validateClientSend(kind: .text))
        XCTAssertNil(ChatLogic.validateClientSend(kind: .image))
        XCTAssertNil(ChatLogic.validateClientSend(kind: .listingCard))
        XCTAssertNil(ChatLogic.validateClientSend(kind: .orderCard))
        XCTAssertEqual(ChatLogic.validateClientSend(kind: .offerCard), .invalidMessageType)
        XCTAssertEqual(ChatLogic.validateClientSend(kind: .system), .invalidMessageType)
        XCTAssertEqual(ChatLogic.validateClientSend(kind: .riskBanner), .invalidMessageType)
        XCTAssertTrue(ChatMessageKind.offerCard.skipsRiskLexicon)
        XCTAssertTrue(ChatMessageKind.listingCard.skipsRiskLexicon)
        XCTAssertFalse(ChatMessageKind.text.skipsRiskLexicon)
    }

    func testSubjectTypeNormalize() {
        XCTAssertEqual(ConversationSubjectType.normalize("lot"), .lot)
        XCTAssertEqual(ConversationSubjectType.normalize("listing"), .listing)
        XCTAssertEqual(ConversationSubjectType.normalize("order"), .order)
        XCTAssertEqual(ConversationSubjectType.normalize("拍品"), .lot)
        XCTAssertEqual(ConversationSubjectType.normalize("商品"), .listing)
        XCTAssertNil(ConversationSubjectType.normalize("chat"))
    }

    // MARK: Payloads

    func testListingOrderOfferPayloadDecode() throws {
        let listingJSON = """
        {"listing_id":11,"title":"RX-78","cover":"https://cdn/x.jpg","price":250000,"status":"on_sale"}
        """.data(using: .utf8)!
        let listing = try decoder.decode(ChatListingCardPayload.self, from: listingJSON)
        XCTAssertEqual(listing.listingId, 11)
        XCTAssertEqual(listing.price, 250_000)
        XCTAssertFalse(listing.isInactive)

        let inactive = ChatListingCardPayload(listingId: 1, title: "x", price: 1, status: "delisted")
        XCTAssertTrue(inactive.isInactive)

        let orderJSON = """
        {"order_id":99,"order_no":"O2026","amount":120000,"status":"paid","title":"订单商品"}
        """.data(using: .utf8)!
        let order = try decoder.decode(ChatOrderCardPayload.self, from: orderJSON)
        XCTAssertEqual(order.orderId, 99)
        XCTAssertEqual(order.orderNo, "O2026")
        XCTAssertEqual(order.amount, 120_000)

        let offerJSON = """
        {"offer_id":7,"price":90000,"round":2,"expires_at":"2026-11-05T12:00:00Z","status":"pending_seller"}
        """.data(using: .utf8)!
        let offer = try decoder.decode(ChatOfferCardPayload.self, from: offerJSON)
        XCTAssertEqual(offer.offerId, 7)
        XCTAssertEqual(offer.round, 2)
        let before = ISO8601DateFormatter().date(from: "2026-11-05T11:00:00Z")!
        let after = ISO8601DateFormatter().date(from: "2026-11-05T13:00:00Z")!
        XCTAssertFalse(offer.isExpired(serverNow: before))
        XCTAssertTrue(offer.isExpired(serverNow: after))
        XCTAssertTrue(ChatLogic.offerActionsEnabled(payload: offer, serverNow: before))
        XCTAssertFalse(ChatLogic.offerActionsEnabled(payload: offer, serverNow: after))
    }

    // MARK: Push collapse (N-23)

    func testPushCollapseWithin60sSuppressesAndIncrementsPending() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var state = PushCollapseState(conversationId: 1, recipientId: 2, lastPushAt: t0, pendingCount: 0)
        // Immediate second message within 60s → collapse
        let t30 = t0.addingTimeInterval(30)
        XCTAssertTrue(ChatLogic.shouldCollapsePush(lastPushAt: t0, now: t30))
        state = ChatLogic.nextCollapseState(current: state, now: t30, recipientOnline: false)
        XCTAssertEqual(state.pendingCount, 1)
        XCTAssertEqual(state.pendingUntil, t0.addingTimeInterval(60))

        // Fifth collapse → pending 5; merge body uses pending
        for i in 2...5 {
            state = ChatLogic.nextCollapseState(
                current: state,
                now: t0.addingTimeInterval(TimeInterval(10 * i)),
                recipientOnline: false
            )
        }
        XCTAssertEqual(state.pendingCount, 5)
        XCTAssertEqual(ChatLogic.mergePushBody(pendingCount: state.pendingCount), "你有 5 条未读消息")
        XCTAssertEqual(ChatCopy.mergePushBody(unreadCount: 1), "你有 1 条未读消息")
    }

    func testPushCollapseOnlineClearsPendingAndOpenClearsLocal() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_100)
        var state = PushCollapseState(
            conversationId: 3,
            recipientId: 9,
            lastPushAt: t0,
            pendingCount: 4,
            pendingUntil: t0.addingTimeInterval(60)
        )
        state = ChatLogic.nextCollapseState(current: state, now: t0.addingTimeInterval(10), recipientOnline: true)
        XCTAssertEqual(state.pendingCount, 0)
        XCTAssertNil(state.pendingUntil)

        state.pendingCount = 3
        state = ChatLogic.clearLocalPending(state)
        XCTAssertEqual(state.pendingCount, 0)
        XCTAssertFalse(state.hasPending)

        // After merge window, next push resets last_push_at
        let late = t0.addingTimeInterval(61)
        XCTAssertFalse(ChatLogic.shouldCollapsePush(lastPushAt: t0, now: late))
        state.lastPushAt = t0
        state = ChatLogic.nextCollapseState(current: state, now: late, recipientOnline: false)
        XCTAssertEqual(state.lastPushAt, late)
        XCTAssertEqual(state.pendingCount, 0)
    }

    // MARK: Reminder copy + T-04 sent_once

    func testReminderKindsLeadsAndCopy() {
        XCTAssertEqual(ReminderJobKind.lotEnding.notifyCode, "N-02")
        XCTAssertEqual(ReminderJobKind.payDeadline.notifyCode, "N-06")
        XCTAssertEqual(ReminderJobKind.lotteryPay.notifyCode, "N-12")
        XCTAssertEqual(ReminderJobKind.balanceDeadline24h.notifyCode, "N-15")
        XCTAssertEqual(ReminderJobKind.subscribeEnding.notifyCode, "N-28")
        XCTAssertTrue(ReminderJobKind.lotEnding.usesSentOnceKey)
        XCTAssertFalse(ReminderJobKind.payDeadline.usesSentOnceKey)
        XCTAssertEqual(ReminderJobKind.lotEnding.defaultLeadSec, 300)
        XCTAssertEqual(ReminderCopy.title(for: .lotEnding), ReminderCopy.lotEndingTitle)
        XCTAssertTrue(ReminderCopy.body(for: .payDeadline).contains("付款"))
        XCTAssertEqual(ReminderJobKind.normalize("N-02"), .lotEnding)
        XCTAssertEqual(ReminderJobKind.normalize("closing_remind"), .lotEnding)
    }

    func testSentOnceKeyPreventsRescheduleAfterSent() {
        let key = ChatLogic.sentOnceKey(userId: 42, lotId: 7)
        XCTAssertEqual(key, "lot_ending:42:7")
        XCTAssertFalse(ChatLogic.shouldInsertLotEnding(sentOnceOccupied: true))
        XCTAssertTrue(ChatLogic.shouldInsertLotEnding(sentOnceOccupied: false))
        XCTAssertFalse(ChatLogic.shouldRescheduleLotEnding(previousStatus: .scheduled, sentOnceOccupied: true))
        XCTAssertTrue(ChatLogic.shouldRescheduleLotEnding(previousStatus: .scheduled, sentOnceOccupied: false))
        XCTAssertTrue(ChatLogic.shouldRescheduleLotEnding(previousStatus: .cancelled, sentOnceOccupied: false))

        let end = Date(timeIntervalSince1970: 1_700_010_000)
        let fire = ChatLogic.fireAt(deadline: end, leadSec: ChatConfigDefaults.lotEndingLeadSec)
        XCTAssertEqual(fire.timeIntervalSince1970, end.timeIntervalSince1970 - 300)

        let uniq = ChatLogic.uniqueJobKey(
            kind: .lotEnding,
            userId: 1,
            refType: "lot",
            refId: "7",
            bindVersion: 3
        )
        XCTAssertEqual(uniq, "lot_ending:1:lot:7:3")
    }

    func testReminderSkipReasonNormalize() {
        XCTAssertEqual(ReminderSkipReason.normalize("state_mismatch"), .stateMismatch)
        XCTAssertEqual(ReminderSkipReason.normalize("already_sent"), .alreadySent)
        XCTAssertEqual(ReminderSkipReason.normalize("version_stale"), .versionStale)
        XCTAssertEqual(ReminderSkipReason.normalize("user_ineligible"), .userIneligible)
        XCTAssertEqual(ReminderSkipReason.normalize("sent_once"), .alreadySent)
        XCTAssertTrue(ReminderJobStatus.sent.isTerminal)
        XCTAssertFalse(ReminderJobStatus.scheduled.isTerminal)
    }

    func testReminderJobDecode() throws {
        let json = """
        {"id":1,"kind":"lot_ending","user_id":9,"ref_type":"lot","ref_id":"77",
         "fire_at":"2026-11-05T10:00:00Z","bind_version":2,"status":"skipped",
         "skip_reason":"already_sent","sent_once_key":"lot_ending:9:77"}
        """.data(using: .utf8)!
        let job = try decoder.decode(ReminderJob.self, from: json)
        XCTAssertEqual(job.kind, .lotEnding)
        XCTAssertEqual(job.bindVersion, 2)
        XCTAssertEqual(job.status, .skipped)
        XCTAssertEqual(job.skipReason, .alreadySent)
        XCTAssertEqual(job.sentOnceKey, "lot_ending:9:77")
    }

    // MARK: Copy / risk / errors (N-24 / §9)

    func testChatCopyAndRiskHelpers() {
        XCTAssertEqual(ChatCopy.emptyConversation, "问问成色或包浆")
        XCTAssertTrue(ChatCopy.riskBlockedSender.contains("未发送"))
        XCTAssertTrue(ChatCopy.riskHintBoth.contains("站外"))
        XCTAssertEqual(ChatCopy.learnProtection, "了解平台交易保护")
        XCTAssertEqual(ChatCopy.goRealName, "去实名")
        XCTAssertFalse(ChatLogic.riskBannerDismissible(level: .hint))
        XCTAssertFalse(ChatLogic.riskBannerDismissible(level: .block))
        XCTAssertTrue(ChatLogic.senderBubbleDimmed(blocked: true, riskLevel: nil))
        XCTAssertTrue(ChatLogic.senderBubbleDimmed(blocked: false, riskLevel: .block))
        XCTAssertFalse(ChatLogic.senderBubbleDimmed(blocked: false, riskLevel: .hint))
        XCTAssertTrue(ChatRiskLevel.hint.visibleToPeer)
        XCTAssertFalse(ChatRiskLevel.block.visibleToPeer)
    }

    func testErrorCodeNormalizeAndPureAmount() {
        XCTAssertEqual(ChatErrorCode.normalize("blocked_by_peer"), .blockedByPeer)
        XCTAssertEqual(ChatErrorCode.normalize("blocked_by_user"), .blockedByPeer)
        XCTAssertEqual(ChatErrorCode.normalize("risk_blocked"), .riskBlocked)
        XCTAssertEqual(ChatErrorCode.normalize("content_blocked"), .riskBlocked)
        XCTAssertEqual(ChatErrorCode.normalize("invalid_message_type"), .invalidMessageType)
        XCTAssertEqual(ChatErrorCode.normalize("real_name_required"), .realNameRequired)
        XCTAssertTrue(ChatErrorCode.riskHint.isSoftRiskHint)
        XCTAssertTrue(ChatLogic.looksLikePureAmount("2500"))
        XCTAssertTrue(ChatLogic.looksLikePureAmount("2500.50元"))
        XCTAssertFalse(ChatLogic.looksLikePureAmount("加微信"))
        XCTAssertFalse(ChatLogic.looksLikePureAmount("2000 转账"))
        XCTAssertNil(ChatLogic.validateTextLength("你好"))
        XCTAssertNotNil(ChatLogic.validateTextLength(""))
        XCTAssertNotNil(ChatLogic.validateTextLength(String(repeating: "a", count: 1001)))
        XCTAssertEqual(ChatLogic.validateImageSize(bytes: 6 * 1024 * 1024), .imageTooLarge)
        XCTAssertNil(ChatLogic.validateImageSize(bytes: 1024))
        XCTAssertEqual(
            ChatLogic.listPreview(kind: .image, content: ""),
            "[图片]"
        )
        XCTAssertTrue(ChatLogic.listPreview(kind: .orderCard, content: "O1").hasPrefix("[订单]"))
    }

    func testPushCollapseStateDecode() throws {
        let json = """
        {"conversation_id":5,"recipient_id":8,"last_push_at":"2026-11-05T09:00:00Z",
         "pending_count":3,"pending_until":"2026-11-05T09:01:00Z"}
        """.data(using: .utf8)!
        let row = try decoder.decode(PushCollapseState.self, from: json)
        XCTAssertEqual(row.conversationId, 5)
        XCTAssertEqual(row.pendingCount, 3)
        XCTAssertTrue(row.hasPending)
    }
}
