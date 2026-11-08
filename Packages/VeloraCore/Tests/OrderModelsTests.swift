import XCTest
@testable import VeloraCore

final class OrderModelsTests: XCTestCase {
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

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: Trade type six kinds

    func testTradeTypeSixKindsAndLabels() {
        let all = OrderTradeType.allCases
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(OrderTradeType.auction.displayLabel, "拍卖")
        XCTAssertEqual(OrderTradeType.fixed.displayLabel, "一口价")
        XCTAssertEqual(OrderTradeType.spot.displayLabel, "现货发售")
        XCTAssertEqual(OrderTradeType.lottery.displayLabel, "抽签")
        XCTAssertEqual(OrderTradeType.presaleDeposit.displayLabel, "预售定金")
        XCTAssertEqual(OrderTradeType.presaleBalance.displayLabel, "预售尾款")
    }

    func testTradeTypeLegacySpotReleaseMapsToSpot() {
        XCTAssertEqual(OrderTradeType(rawOrLegacy: "spot_release"), .spot)
        XCTAssertEqual(OrderTradeType(rawOrLegacy: "SPOT"), .spot)
        XCTAssertEqual(OrderTradeType(rawOrLegacy: "unknown_future"), .auction)
        XCTAssertEqual(OrderTradeType(rawOrLegacy: nil), .auction)
    }

    func testPayWindowDefaultsMatchDesign() {
        XCTAssertEqual(OrderTradeType.auction.defaultPayWindowSec, 86_400)
        XCTAssertEqual(OrderTradeType.fixed.defaultPayWindowSec, 900)
        XCTAssertEqual(OrderTradeType.spot.defaultPayWindowSec, 900)
        XCTAssertEqual(OrderTradeType.lottery.defaultPayWindowSec, 7_200)
        XCTAssertEqual(OrderTradeType.presaleDeposit.defaultPayWindowSec, 900)
        XCTAssertFalse(OrderTradeType.presaleDeposit.hasShipDeadline)
        XCTAssertTrue(OrderTradeType.auction.hasShipDeadline)
    }

    // MARK: Status machine

    func testStatusMachineHappyPath() {
        XCTAssertTrue(OrderLogic.canTransition(from: .pendingPayment, to: .paid))
        XCTAssertTrue(OrderLogic.canTransition(from: .paid, to: .shipped))
        XCTAssertTrue(OrderLogic.canTransition(from: .shipped, to: .completed))
        XCTAssertTrue(OrderLogic.canTransition(from: .completed, to: .settled))
        XCTAssertNil(OrderLogic.assertTransition(from: .pendingPayment, to: .paid))
    }

    func testStatusMachineIllegalTransitions() {
        XCTAssertFalse(OrderLogic.canTransition(from: .pendingPayment, to: .shipped))
        XCTAssertFalse(OrderLogic.canTransition(from: .completed, to: .paid))
        XCTAssertFalse(OrderLogic.canTransition(from: .cancelled, to: .paid))
        XCTAssertFalse(OrderLogic.canTransition(from: .refunded, to: .shipped))
        XCTAssertFalse(OrderLogic.canTransition(from: .settled, to: .completed))
        XCTAssertEqual(OrderLogic.assertTransition(from: .pendingPayment, to: .shipped), .invalidOrderTransition)
    }

    func testStatusMachineReentryAllowed() {
        XCTAssertTrue(OrderLogic.canTransition(from: .paid, to: .paid))
        XCTAssertTrue(OrderLogic.canTransition(from: .settled, to: .settled))
    }

    func testSettledIsTerminalAndListLabelCompleted() {
        XCTAssertTrue(OrderCenterStatus.settled.isTerminal)
        XCTAssertEqual(OrderCenterStatus.settled.listLabel, "已完成")
    }

    // MARK: After-sale badge

    func testAfterSaleBadgeProcessingIndependentOfMainStatus() {
        let badge = OrderLogic.afterSaleBadge(
            status: .shipped,
            afterSaleStatus: .processing,
            refundedAmount: 0
        )
        XCTAssertEqual(badge, .processing)
        XCTAssertEqual(badge.label, OrderCenterCopy.afterSaleBadge)
    }

    func testPartialRefundKeepsMainStatusBadge() {
        let badge = OrderLogic.afterSaleBadge(
            status: .completed,
            afterSaleStatus: .none,
            refundedAmount: 10_000
        )
        XCTAssertEqual(badge, .partialRefund)
        XCTAssertEqual(badge.label, OrderCenterCopy.partialRefundBadge)
    }

    func testAfterSaleTabMembership() {
        XCTAssertTrue(OrderLogic.matchesAfterSaleTab(status: .refunded, afterSaleStatus: .none))
        XCTAssertTrue(OrderLogic.matchesAfterSaleTab(status: .shipped, afterSaleStatus: .processing))
        XCTAssertFalse(OrderLogic.matchesAfterSaleTab(status: .paid, afterSaleStatus: .none))
    }

    // MARK: Remain secs from server_time

    func testRemainSecondsFromDeadlineAndServerNow() {
        let server = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = server.addingTimeInterval(3_600)
        XCTAssertEqual(OrderLogic.remainSeconds(deadline: deadline, serverNow: server), 3_600)
        XCTAssertEqual(OrderLogic.remainSeconds(deadline: deadline, serverNow: deadline), 0)
        XCTAssertEqual(OrderLogic.remainSeconds(deadline: nil, serverNow: server), 0)
    }

    func testRemainSecondsDecaysWithLocalElapsedIgnoringDeviceSkew() {
        let fetched = Date(timeIntervalSince1970: 1_000)
        let now = fetched.addingTimeInterval(45)
        XCTAssertEqual(
            OrderLogic.remainSeconds(serverRemainSec: 100, fetchedAtLocal: fetched, nowLocal: now),
            55
        )
        XCTAssertEqual(
            OrderLogic.remainSeconds(serverRemainSec: 10, fetchedAtLocal: fetched, nowLocal: now),
            0
        )
    }

    func testPayRemainPrefersDeadlinePlusServerTimeCalibration() {
        let serverTime = Date(timeIntervalSince1970: 5_000)
        let deadline = serverTime.addingTimeInterval(120)
        let fetched = Date(timeIntervalSince1970: 100)
        let now = fetched.addingTimeInterval(30) // 30s local elapsed → server now = 5030
        let remain = OrderLogic.payRemainSeconds(
            deadline: deadline,
            serverRemainSec: 999, // ignored when deadline+serverTime present
            serverTime: serverTime,
            fetchedAtLocal: fetched,
            nowLocal: now
        )
        XCTAssertEqual(remain, 90)
    }

    func testCountdownUrgentAndFormat() {
        XCTAssertTrue(OrderLogic.isCountdownUrgent(3_599))
        XCTAssertFalse(OrderLogic.isCountdownUrgent(3_600))
        XCTAssertFalse(OrderLogic.isCountdownUrgent(0))
        XCTAssertEqual(OrderLogic.formatCountdown(65), "00:01:05")
        XCTAssertEqual(OrderLogic.formatCountdown(86_400 + 1), "1天00:00:01")
    }

    // MARK: Address edit until shipped

    func testAddressEditableUntilShippedForBuyer() {
        XCTAssertTrue(OrderLogic.canEditAddress(status: .pendingPayment, isBuyer: true))
        XCTAssertTrue(OrderLogic.canEditAddress(status: .paid, isBuyer: true))
        XCTAssertFalse(OrderLogic.canEditAddress(status: .shipped, isBuyer: true))
        XCTAssertFalse(OrderLogic.canEditAddress(status: .paid, isBuyer: false))
        XCTAssertEqual(
            OrderLogic.addressEditBlockedReason(status: .shipped, isBuyer: true),
            .addressLocked
        )
    }

    func testAddressBookLimit() {
        XCTAssertFalse(OrderLogic.isAddressBookFull(count: 19))
        XCTAssertTrue(OrderLogic.isAddressBookFull(count: 20))
        XCTAssertEqual(OrderCenterConfigDefaults.addressMax, 20)
    }

    // MARK: Snapshots / list decode without fee internals

    func testItemAndAddressSnapshotDecode() throws {
        let itemJSON = """
        {"title":"MG Exia","condition":"全新","defect_summary":"无","cover_url":"https://cdn/x.jpg","category":"gunpla","brand":"Bandai","scale":"1/100"}
        """.data(using: .utf8)!
        let item = try decoder.decode(OrderItemSnapshot.self, from: itemJSON)
        XCTAssertEqual(item.title, "MG Exia")
        XCTAssertEqual(item.coverURL, "https://cdn/x.jpg")
        XCTAssertEqual(item.scale, "1/100")

        let addrJSON = """
        {"name":"张*","phone":"138****0000","province":"沪","city":"上海","district":"浦东","detail":"***","address_hash":"abc"}
        """.data(using: .utf8)!
        let addr = try decoder.decode(OrderAddressSnapshot.self, from: addrJSON)
        XCTAssertTrue(addr.hasContent)
        XCTAssertEqual(addr.addressHash, "abc")
        XCTAssertTrue(addr.oneLine.contains("浦东"))
    }

    func testFeeRuleSnapshotStripsBuyerInternals() {
        let fee = OrderFeeRuleSnapshot(
            sellerType: "personal",
            tradeType: "auction",
            rateBp: 500,
            tierBasis: "monthly_gmv",
            gmvLastMonth: 120_000_000,
            channelFeeBp: 60,
            ruleId: "r1",
            ruleVersion: "v3",
            priority: 9
        )
        let buyer = fee.strippedForBuyer()
        XCTAssertNil(buyer.priority)
        XCTAssertNil(buyer.ruleId)
        XCTAssertNil(buyer.tierBasis)
        XCTAssertNil(buyer.gmvLastMonth)
        XCTAssertEqual(buyer.rateBp, 500)
        XCTAssertEqual(buyer.channelFeeBp, 60)
    }

    func testListCardDecodeIgnoresFeeRuleSnapshot() throws {
        let json = """
        {
          "id": 42,
          "order_no": "P432024010100000001",
          "trade_type": "auction",
          "title": "MG",
          "cover_url": "https://cdn/c.jpg",
          "amount": 250000,
          "status": "pending_payment",
          "after_sale_status": "none",
          "pay_remain_sec": 800,
          "ship_remain_sec": null,
          "confirm_remain_sec": null,
          "server_time": "2024-01-01T00:00:00Z",
          "fee_rule_snapshot": {"rate_bp": 500, "priority": 1, "rule_id": "secret"},
          "buyer_id": 9,
          "phone": "13800138000"
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(OrderListCard.self, from: json)
        XCTAssertEqual(card.id, 42)
        XCTAssertEqual(card.tradeType, .auction)
        XCTAssertEqual(card.amount, 250_000)
        XCTAssertEqual(card.payRemainSec, 800)
        XCTAssertEqual(card.afterSaleStatus, .none)
        XCTAssertNotNil(card.serverTime)

        // Re-encode whitelist — must not emit fee_rule_snapshot
        let encoded = try encoder.encode(card)
        let obj = try JSONSerialization.jsonObject(with: encoded)
        XCTAssertFalse(OrderLogic.listPayloadContainsForbiddenFeeKeys(obj))
        let dict = try XCTUnwrap(obj as? [String: Any])
        XCTAssertNil(dict["fee_rule_snapshot"])
        XCTAssertNil(dict["priority"])
        XCTAssertNil(dict["rule_id"])
    }

    func testListCardLegacyTypeAndHammerPrice() throws {
        let json = """
        {"id":1,"order_no":"V1","type":"spot_release","hammer_price":9900,"status":"paid","lot":{"title":"Spot","cover":"c.png"}}
        """.data(using: .utf8)!
        let card = try decoder.decode(OrderListCard.self, from: json)
        XCTAssertEqual(card.tradeType, .spot)
        XCTAssertEqual(card.amount, 9_900)
        XCTAssertEqual(card.title, "Spot")
        XCTAssertEqual(card.coverURL, "c.png")
        XCTAssertEqual(card.status, .paid)
    }

    // MARK: Tabs / query

    func testBuyerSellerTabsTitles() {
        let titles = OrderCenterTab.allCases.map(\.title)
        XCTAssertEqual(titles, ["全部", "待付款", "待发货", "待收货", "待评价", "退款售后"])
    }

    func testTabListQuery() {
        XCTAssertEqual(OrderCenterTab.pendingPayment.listQuery.status, "pending_payment")
        XCTAssertEqual(OrderCenterTab.pendingShip.listQuery.status, "paid")
        XCTAssertEqual(OrderCenterTab.pendingReceive.listQuery.status, "shipped")
        XCTAssertEqual(OrderCenterTab.pendingReview.listQuery.status, "completed")
        XCTAssertEqual(OrderCenterTab.afterSale.listQuery.tab, "after_sale")
        XCTAssertNil(OrderCenterTab.all.listQuery.status)
    }

    func testTabFromInitialStatus() {
        XCTAssertEqual(OrderCenterTab.from(initialStatus: "paid"), .pendingShip)
        XCTAssertEqual(OrderCenterTab.from(initialStatus: "after_sale"), .afterSale)
        XCTAssertEqual(OrderCenterTab.from(initialStatus: nil), .all)
    }

    // MARK: Error codes

    func testErrorCodesIncludeDesignSet() {
        let codes = Set(OrderCenterErrorCode.allCases.map(\.rawValue))
        for needed in [
            "price_locked", "address_locked", "invalid_order_transition",
            "query_too_broad", "missing_idempotency_key", "forbidden", "address_limit",
        ] {
            XCTAssertTrue(codes.contains(needed), needed)
        }
        XCTAssertFalse(OrderCenterErrorCode.priceLocked.fallbackMessage.isEmpty)
    }

    func testFundStatusNotUsedAsMainCopy() {
        XCTAssertEqual(OrderFundStatus.unpaid.buyerDisplayLabel, "待支付")
        XCTAssertEqual(OrderFundStatus.held.buyerDisplayLabel, "已托管")
        XCTAssertNotEqual(OrderFundStatus.settled.buyerDisplayLabel, OrderCenterStatus.settled.displayLabel)
    }
}
