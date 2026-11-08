import XCTest
@testable import VeloraCore

final class NotificationModelsTests: XCTestCase {
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

    // MARK: Config (design §3 / §15)

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(NotifyConfigDefaults.dedupWindowSec, 600)
        XCTAssertEqual(NotifyConfigDefaults.onlinePongSec, 45)
        XCTAssertEqual(NotifyConfigDefaults.clientPingSec, 20)
        XCTAssertEqual(NotifyConfigDefaults.retainDays, 180)
        XCTAssertEqual(NotifyConfigDefaults.smsMaxPerMin, 2)
        XCTAssertEqual(NotifyConfigDefaults.smsRegionDefault, "CN_mainland")
        XCTAssertEqual(NotifyConfigDefaults.platformIOSAPNs, "ios_apns")
        XCTAssertEqual(NotifyConfigDefaults.deeplinkScheme, "paddock43")
        XCTAssertEqual(NotifyConfigDefaults.quietHoursTimezone, "Asia/Shanghai")
        XCTAssertEqual(NotifyConfigDefaults.quietHoursStartHour, 22)
        XCTAssertEqual(NotifyConfigDefaults.quietHoursEndHour, 8)
        XCTAssertEqual(NotifyConfigDefaults.pageSizeDefault, 20)
        XCTAssertEqual(NotifyConfigDefaults.pageSizeMax, 50)
        XCTAssertEqual(NotifyConfigDefaults.titleMaxLen, 64)
        XCTAssertEqual(NotifyConfigDefaults.bodyMaxLen, 256)
        XCTAssertFalse(NotifyConfigDefaults.marketingPushDefault)
        XCTAssertFalse(NotifyConfigDefaults.pushEvenWhenOnlineDefault)
        XCTAssertEqual(NotifyConfigDefaults.inboxTabsOrdered.count, 5)
    }

    // MARK: Five tabs (MSG-01)

    func testFiveInboxTabsOrderedAndLabels() {
        XCTAssertEqual(InboxTab.allCases.map(\.rawValue), [
            "trade", "follow", "auction", "chat", "system",
        ])
        XCTAssertEqual(InboxTab.trade.displayLabel, "交易")
        XCTAssertEqual(InboxTab.follow.displayLabel, "关注")
        XCTAssertEqual(InboxTab.auction.displayLabel, "竞拍")
        XCTAssertEqual(InboxTab.chat.displayLabel, "私聊")
        XCTAssertEqual(InboxTab.system.displayLabel, "系统")
        XCTAssertEqual(InboxTab.normalize("私聊"), .chat)
        XCTAssertEqual(InboxTab.normalize("messages"), .chat)
        XCTAssertTrue(InboxTab.chat.usesConversationsAPI)
        XCTAssertFalse(InboxTab.trade.usesConversationsAPI)
        XCTAssertEqual(InboxTab.trade.emptyMessage, NotifyCopy.emptyTrade)
        XCTAssertEqual(InboxTab.auction.emptyMessage, NotifyCopy.emptyAuction)
        XCTAssertEqual(InboxTab.follow.emptyMessage, NotifyCopy.emptyFollow)
        XCTAssertEqual(InboxTab.system.emptyMessage, NotifyCopy.emptySystem)
        XCTAssertNil(InboxTab.chat.apiCategory)
        XCTAssertEqual(InboxTab.trade.apiCategory, .trade)
    }

    func testNotificationCategoryNormalize() {
        XCTAssertEqual(NotificationCategory.normalize("trade"), .trade)
        XCTAssertEqual(NotificationCategory.normalize("竞拍"), .auction)
        XCTAssertNil(NotificationCategory.normalize("chat"))
        XCTAssertEqual(NotificationCategory.auction.inboxTab, .auction)
    }

    // MARK: Counters

    func testCountersSumEqualsTotal() {
        let c = InboxCounters(
            unreadTrade: 2,
            unreadFollow: 0,
            unreadAuction: 1,
            unreadChat: 3,
            unreadSystem: 0
        )
        XCTAssertEqual(c.unreadTotal, 6)
        XCTAssertEqual(c.recomputedTotal, 6)
        XCTAssertTrue(c.isConsistent)
        XCTAssertEqual(c.unread(for: .chat), 3)
        XCTAssertEqual(c.unread(for: .trade), 2)

        // Scenario: chat 3 + trade 2 → total 5 (design §7)
        let s = InboxCounters(unreadTrade: 2, unreadChat: 3)
        XCTAssertEqual(s.unreadTotal, 5)
        XCTAssertTrue(s.isConsistent)
    }

    func testCountersWSOverlayAndGuestZero() {
        let ws = InboxCounters.fromWSUnread([
            "trade": 1,
            "follow": 2,
            "auction": 0,
            "chat": 4,
            "system": 1,
            "total": 8,
        ])
        XCTAssertEqual(ws.unreadTotal, 8)
        XCTAssertTrue(ws.isConsistent)
        XCTAssertEqual(InboxCounters.guestZero.unreadTotal, 0)
        XCTAssertEqual(NotifyLogic.badgeTotal(isLoggedIn: false, counters: ws), 0)
        XCTAssertEqual(NotifyLogic.badgeTotal(isLoggedIn: true, counters: ws), 8)
    }

    func testCountersMarkReadRecalc() {
        var c = InboxCounters(unreadTrade: 2, unreadAuction: 1, unreadChat: 3)
        XCTAssertEqual(c.unreadTotal, 6)
        c = NotifyLogic.countersAfterMarking(c, tab: .trade, all: false)
        XCTAssertEqual(c.unread(for: .trade), 0)
        XCTAssertEqual(c.unreadTotal, 4)
        c = NotifyLogic.countersAfterMarking(c, tab: nil, all: true)
        XCTAssertEqual(c.unreadTotal, 0)
        XCTAssertTrue(c.isConsistent)
    }

    func testCountersDecodeSnakeCase() throws {
        let json = """
        {"unread_trade":2,"unread_follow":1,"unread_auction":0,"unread_chat":3,"unread_system":1,"unread_total":7}
        """.data(using: .utf8)!
        let c = try decoder.decode(InboxCounters.self, from: json)
        XCTAssertEqual(c.unreadTrade, 2)
        XCTAssertEqual(c.unreadChat, 3)
        XCTAssertEqual(c.unreadTotal, 7)
        XCTAssertTrue(c.isConsistent)
    }

    // MARK: Event matrix

    func testEventCodeCategoryAndChannelClass() {
        XCTAssertEqual(NotificationEventCode.n05.inboxTab, .trade)
        XCTAssertEqual(NotificationEventCode.n05.channelClass, .trade)
        XCTAssertEqual(NotificationEventCode.n01.inboxTab, .auction)
        XCTAssertEqual(NotificationEventCode.n10.inboxTab, .follow)
        XCTAssertEqual(NotificationEventCode.n10.channelClass, .subscribe)
        XCTAssertEqual(NotificationEventCode.n22.channelClass, .social)
        XCTAssertEqual(NotificationEventCode.n25.inboxTab, .system)
        XCTAssertEqual(NotificationEventCode.n25.channelClass, .account)
        XCTAssertEqual(NotificationEventCode.n23.inboxTab, .chat)
        XCTAssertTrue(NotificationEventCode.n23.skipsInboxTable)
        XCTAssertTrue(NotificationEventCode.n04.skipsInboxTable)
        XCTAssertTrue(NotificationEventCode.n02.lifetimeDedup)
        XCTAssertTrue(NotificationEventCode.n29.hasDailyCap)
        XCTAssertTrue(NotificationEventCode.n19.inboxOnlyDefault)
        XCTAssertTrue(NotificationEventCode.n05.smsRequiredByMatrix)
        XCTAssertEqual(NotificationEventCode.normalize("n05"), .n05)
        XCTAssertEqual(NotificationEventCode.normalize("N-05"), .n05)
        XCTAssertTrue(PushChannelClass.trade.inboxForcedOn)
        XCTAssertTrue(PushChannelClass.subscribe.respectsQuietHours)
        XCTAssertFalse(PushChannelClass.trade.respectsQuietHours)
    }

    // MARK: Push settings (MSG-05)

    func testTradeInboxCannotDisable() {
        let bad = PushSetting(eventCode: "N-05", inboxEnabled: false, pushEnabled: false, smsEnabled: true)
        XCTAssertEqual(NotifyLogic.validatePushSettingUpdate(bad), .tradeInboxCannotDisable)
        let ok = PushSetting(eventCode: "N-05", inboxEnabled: true, pushEnabled: false, smsEnabled: false)
        XCTAssertNil(NotifyLogic.validatePushSettingUpdate(ok))
        let normalized = NotifyLogic.normalizedSetting(bad)
        XCTAssertTrue(normalized.inboxEnabled)
        XCTAssertEqual(NotifyErrorCode.normalize("trade_inbox_cannot_disable"), .tradeInboxCannotDisable)
        XCTAssertTrue(NotifyErrorCode.tradeInboxCannotDisable.fallbackMessage.contains("无法关闭"))
    }

    func testSubscribeCanDisableInboxAndPush() {
        let s = PushSetting(eventCode: "N-10", inboxEnabled: false, pushEnabled: false, smsEnabled: false)
        XCTAssertNil(NotifyLogic.validatePushSettingUpdate(s))
        XCTAssertEqual(s.channelClass, .subscribe)
    }

    func testPushSettingsPayloadRoundTrip() throws {
        let json = """
        {"items":[{"event_code":"N-05","inbox_enabled":true,"push_enabled":false,"sms_enabled":true}],"push_even_when_online":false}
        """.data(using: .utf8)!
        let payload = try decoder.decode(PushSettingsPayload.self, from: json)
        XCTAssertEqual(payload.items.count, 1)
        XCTAssertEqual(payload.items[0].eventCode, "N-05")
        XCTAssertFalse(payload.items[0].pushEnabled)
        XCTAssertFalse(payload.pushEvenWhenOnline)
        XCTAssertEqual(payload.setting(for: .n05)?.smsEnabled, true)
    }

    // MARK: Push token (MSG-03 / T-09)

    func testOnlyIOSAPNsTokenAccepted() {
        XCTAssertEqual(PushTokenPlatform.normalize("ios_apns"), .iosAPNs)
        XCTAssertEqual(PushTokenPlatform.normalize("ios"), .iosAPNs)
        XCTAssertNil(PushTokenPlatform.normalize("android"))
        XCTAssertNil(PushTokenPlatform.normalize("xiaomi"))
        XCTAssertEqual(NotifyLogic.validatePushTokenPlatform("android"), .invalidPushToken)
        XCTAssertNil(NotifyLogic.validatePushTokenPlatform("ios_apns"))
        let reg = PushTokenRegistration(token: "abc", bundleId: "com.velora.app")
        XCTAssertTrue(reg.isValidPlatform)
        XCTAssertEqual(reg.body["platform"] as? String, "ios_apns")
    }

    // MARK: Quiet hours (design §9)

    func testQuietHoursShanghaiOvernightWindow() {
        let qh = QuietHours.shanghaiNight
        XCTAssertEqual(qh.timeZoneIdentifier, "Asia/Shanghai")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = qh.timeZone

        // 23:30 → inside
        var comps = DateComponents(year: 2026, month: 11, day: 5, hour: 23, minute: 30)
        let night = cal.date(from: comps)!
        XCTAssertTrue(qh.contains(night, calendar: cal))

        // 07:59 → inside
        comps.hour = 7; comps.minute = 59
        let early = cal.date(from: comps)!
        XCTAssertTrue(qh.contains(early, calendar: cal))

        // 08:00 → outside
        comps.hour = 8; comps.minute = 0
        let morning = cal.date(from: comps)!
        XCTAssertFalse(qh.contains(morning, calendar: cal))

        // 21:59 → outside
        comps.hour = 21; comps.minute = 59
        let evening = cal.date(from: comps)!
        XCTAssertFalse(qh.contains(evening, calendar: cal))

        // 22:00 → inside
        comps.hour = 22; comps.minute = 0
        let start = cal.date(from: comps)!
        XCTAssertTrue(qh.contains(start, calendar: cal))
    }

    func testQuietHoursMutesSubscribeNotTrade() {
        let qh = QuietHours.shanghaiNight
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = qh.timeZone
        let night = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23, minute: 0))!

        XCTAssertTrue(qh.shouldMuteSound(eventCode: .n10, at: night, calendar: cal))
        XCTAssertTrue(qh.shouldMuteSound(channelClass: .subscribe, at: night, calendar: cal))
        XCTAssertFalse(qh.shouldMuteSound(eventCode: .n05, at: night, calendar: cal))
        XCTAssertFalse(qh.shouldMuteSound(eventCode: .n01, at: night, calendar: cal))
        XCTAssertNil(NotifyLogic.apnsSound(eventCode: .n10, at: night, quietHours: qh))
        XCTAssertEqual(NotifyLogic.apnsSound(eventCode: .n05, at: night, quietHours: qh), "default")
    }

    func testQuietHoursDaytimeAllowsSubscribeSound() {
        let qh = QuietHours.shanghaiNight
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = qh.timeZone
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 15, minute: 0))!
        XCTAssertFalse(qh.shouldMuteSound(eventCode: .n10, at: day, calendar: cal))
        XCTAssertEqual(NotifyLogic.apnsSound(eventCode: .n10, at: day, quietHours: qh), "default")
    }

    // MARK: Deeplink / skip push / decode row

    func testDeeplinkWhitelist() {
        XCTAssertTrue(NotifyLogic.isDeeplinkAllowed("paddock43://orders/1"))
        XCTAssertTrue(NotifyLogic.isDeeplinkAllowed("https://paddock43.com/pay/balance/1"))
        XCTAssertFalse(NotifyLogic.isDeeplinkAllowed("javascript:alert(1)"))
        XCTAssertFalse(NotifyLogic.isDeeplinkAllowed("weixin://"))
        XCTAssertFalse(NotifyLogic.isDeeplinkAllowed(nil))
    }

    func testSkipSystemPushRules() {
        XCTAssertTrue(NotifyLogic.shouldSkipSystemPush(
            eventCode: .n19, pushEnabled: true, userOnline: false, pushEvenWhenOnline: false
        ))
        XCTAssertTrue(NotifyLogic.shouldSkipSystemPush(
            eventCode: .n05, pushEnabled: false, userOnline: false, pushEvenWhenOnline: false
        ))
        XCTAssertTrue(NotifyLogic.shouldSkipSystemPush(
            eventCode: .n05, pushEnabled: true, userOnline: true, pushEvenWhenOnline: false
        ))
        XCTAssertFalse(NotifyLogic.shouldSkipSystemPush(
            eventCode: .n05, pushEnabled: true, userOnline: true, pushEvenWhenOnline: true
        ))
        XCTAssertFalse(NotifyLogic.shouldSkipSystemPush(
            eventCode: .n05, pushEnabled: true, userOnline: false, pushEvenWhenOnline: false
        ))
    }

    func testValidateCategoryQuery() {
        XCTAssertNil(NotifyLogic.validateCategoryQuery(nil))
        XCTAssertNil(NotifyLogic.validateCategoryQuery("trade"))
        XCTAssertEqual(NotifyLogic.validateCategoryQuery("chat"), .invalidCategory)
        XCTAssertEqual(NotifyLogic.validateCategoryQuery("nope"), .invalidCategory)
        XCTAssertEqual(NotifyLogic.clampPageSize(100), 50)
        XCTAssertEqual(NotifyLogic.clampPageSize(0), 1)
    }

    func testNotificationRowDecode() throws {
        let json = """
        {
          "id": 42,
          "category": "auction",
          "event_code": "N-01",
          "title": "出价被超越",
          "body": "当前价 ¥1200",
          "ref_type": "lot",
          "ref_id": "9",
          "deeplink": "paddock43://lots/9",
          "read_at": null,
          "created_at": "2026-11-05T01:00:00Z",
          "push_status": "skipped_online",
          "sms_status": "none"
        }
        """.data(using: .utf8)!
        let row = try decoder.decode(InboxNotification.self, from: json)
        XCTAssertEqual(row.id, 42)
        XCTAssertEqual(row.category, .auction)
        XCTAssertTrue(row.isUnread)
        XCTAssertEqual(row.resolvedEvent, .n01)
        XCTAssertEqual(row.pushStatus, .skippedOnline)
        XCTAssertTrue(NotifyLogic.isDeeplinkAllowed(row.deeplink))
    }

    func testNotificationPushStatusSkippedQuietAndUnknownNil() throws {
        let quiet = """
        {
          "id": 7,
          "category": "follow",
          "event_code": "N-10",
          "title": "降价",
          "body": "订阅商品降价了",
          "push_status": "skipped_quiet",
          "sms_status": "none"
        }
        """.data(using: .utf8)!
        let row = try decoder.decode(InboxNotification.self, from: quiet)
        XCTAssertEqual(row.pushStatus, .skippedQuiet)
        XCTAssertEqual(NotificationPushStatus.normalize("skipped_user"), .skippedUser)
        XCTAssertEqual(NotificationPushStatus.normalize("dry_run"), .dryRun)
        XCTAssertEqual(NotificationPushStatus.normalize("skipped_inbox_only"), .skippedInboxOnly)

        let unknown = """
        {
          "id": 8,
          "category": "system",
          "event_code": "N-25",
          "title": "系统",
          "body": "x",
          "push_status": "totally_unknown_status",
          "sms_status": "also_unknown"
        }
        """.data(using: .utf8)!
        let soft = try decoder.decode(InboxNotification.self, from: unknown)
        XCTAssertNil(soft.pushStatus)
        XCTAssertNil(soft.smsStatus)
    }

    func testNotificationListPageSkipsBadRows() throws {
        let json = """
        {
          "items": [
            {
              "id": 1,
              "category": "trade",
              "event_code": "N-05",
              "title": "ok",
              "body": "ok",
              "push_status": "skipped_quiet"
            },
            {
              "id": 2,
              "category": "not_a_real_category",
              "event_code": "N-01",
              "title": "bad",
              "body": "bad"
            },
            {
              "id": 3,
              "category": "auction",
              "event_code": "N-01",
              "title": "also ok",
              "body": "also ok",
              "push_status": "sent"
            }
          ],
          "page": 1,
          "page_size": 20,
          "total": 3
        }
        """.data(using: .utf8)!
        let page = try decoder.decode(NotificationListPage.self, from: json)
        XCTAssertEqual(page.items.map(\.id), [1, 3])
        XCTAssertEqual(page.items.first?.pushStatus, .skippedQuiet)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.total, 3)
    }

    func testErrorCodeNormalize() {
        XCTAssertEqual(NotifyErrorCode.normalize("invalid_push_token"), .invalidPushToken)
        XCTAssertEqual(NotifyErrorCode.normalize("ref_gone"), .refGone)
        XCTAssertEqual(NotifyErrorCode.normalize("push_disabled_by_user"), .pushDisabledByUser)
        XCTAssertTrue(NotifyErrorCode.pushDisabledByUser.isSoftSkip)
        XCTAssertEqual(NotifyErrorCode.refGone.fallbackMessage, NotifyCopy.refGone)
        XCTAssertEqual(NotifyCopy.quietHoursHint.isEmpty, false)
        XCTAssertEqual(NotifyCopy.centerTitle, "消息")
    }

    func testDedupAndTruncate() {
        XCTAssertEqual(NotifyLogic.dedupKey(eventCode: "N-01", refStable: "lot:9"), "N-01:lot:9")
        let long = String(repeating: "啊", count: 80)
        XCTAssertEqual(NotifyLogic.truncateTitle(long).count, 64)
        XCTAssertEqual(NotifyLogic.truncateBody(String(repeating: "b", count: 300)).count, 256)
    }
}
