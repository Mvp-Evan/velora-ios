import XCTest
@testable import VeloraCore

final class IncomeModelsTests: XCTestCase {
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

    // MARK: Config

    func testConfigDefaultsMatchDesignB02() {
        XCTAssertEqual(IncomeConfigDefaults.meEntryKey, "profit")
        XCTAssertEqual(IncomeConfigDefaults.launchGateServiceFeeInvoice, "launch_gate.service_fee_invoice")
        XCTAssertEqual(IncomeConfigDefaults.personalFixedBp, 100)
        XCTAssertEqual(IncomeConfigDefaults.personalAuctionBp, 200)
        XCTAssertEqual(IncomeConfigDefaults.proxyTier1GmvFen, 100_000_000)
        XCTAssertEqual(IncomeConfigDefaults.proxyTier1Bp, 900)
        XCTAssertEqual(IncomeConfigDefaults.proxyTier2GmvFen, 500_000_000)
        XCTAssertEqual(IncomeConfigDefaults.proxyTier2Bp, 700)
        XCTAssertEqual(IncomeConfigDefaults.proxyTier3Bp, 500)
        XCTAssertEqual(IncomeConfigDefaults.brandDefaultBp, 300)
        XCTAssertEqual(IncomeConfigDefaults.channelBp, 60)
        XCTAssertEqual(IncomeConfigDefaults.channelBearer, .platform)
        XCTAssertEqual(IncomeConfigDefaults.costImportMaxRows, 500)
        XCTAssertFalse(IncomeConfigDefaults.serviceFeeInvoiceLaunchDefault)
        XCTAssertEqual(IncomeConfigDefaults.missingProfitDisplay, "—")
    }

    // MARK: Fee matrix quote (FIN-01)

    func testRoundHalfUpHalfFenGoesUp() {
        // 1 fen * 5000 bp = 0.5 fen → round half up → 1
        XCTAssertEqual(FeeMatrixQuoteLogic.platformFeeFen(amountFen: 1, rateBp: 5_000), 1)
        // Exact half via (amount*bp+5000)/10000: amount=1, bp=0 → 0
        XCTAssertEqual(FeeMatrixQuoteLogic.platformFeeFen(amountFen: 1, rateBp: 0), 0)
        // 15 fen * 1000 bp = 1.5 → 2
        XCTAssertEqual(FeeMatrixQuoteLogic.platformFeeFen(amountFen: 15, rateBp: 1_000), 2)
    }

    func testAcceptanceExample8_6() {
        let ex = IncomeProfitLogic.acceptanceExample()
        XCTAssertEqual(ex.quote.platformFeeFen, 10_000)
        XCTAssertEqual(ex.quote.sellerNetFen, 240_000)
        XCTAssertEqual(ex.quote.channelFeeFen, 1_500) // 250000 * 60bp
        XCTAssertEqual(ex.quote.platformNetFen, 8_500)
        XCTAssertEqual(ex.costPrice, 200_000)
        XCTAssertEqual(ex.actualShipping, 2_000)
        XCTAssertEqual(ex.profit, 38_000)
        XCTAssertEqual(ex.quote.channelFeeBearer, .platform)
    }

    func testSellerNetDoesNotDeductChannelWhenPlatformBears() {
        let q = FeeMatrixQuoteLogic.quote(
            amountFen: 100_000,
            rateBp: 100,
            buyerShippingFen: 0,
            channelBearer: .platform
        )
        XCTAssertEqual(q.platformFeeFen, 1_000)
        XCTAssertEqual(q.channelFeeFen, 600)
        XCTAssertEqual(q.sellerNetFen, 99_000)
        XCTAssertEqual(q.platformNetFen, 400)
    }

    func testSellerNetDeductsChannelWhenSellerBears() {
        let q = FeeMatrixQuoteLogic.quote(
            amountFen: 100_000,
            rateBp: 100,
            channelBearer: .seller
        )
        XCTAssertEqual(q.sellerNetFen, 99_000 - 600)
        XCTAssertEqual(q.platformNetFen, 1_000)
    }

    func testShippingExcludedFromFeeBase() {
        let feeOnlyGoods = FeeMatrixQuoteLogic.platformFeeFen(amountFen: 100_000, rateBp: 400)
        let q = FeeMatrixQuoteLogic.quote(
            amountFen: 100_000,
            rateBp: 400,
            buyerShippingFen: 2_000,
            payAmountFen: 102_000
        )
        XCTAssertEqual(q.platformFeeFen, feeOnlyGoods)
        XCTAssertEqual(q.sellerNetFen, 100_000 + 2_000 - feeOnlyGoods)
    }

    func testProxyTierByMonthlyGMV() {
        XCTAssertEqual(FeeMatrixQuoteLogic.proxyRateBp(gmvLastMonthFen: 0), 900)
        XCTAssertEqual(FeeMatrixQuoteLogic.proxyRateBp(gmvLastMonthFen: 99_999_999), 900)
        // 12 万 yuan = 12_000_000 fen? Wait: 10万 yuan = 100_000_000 fen (design)
        // 12 万 yuan = 120_000_000 fen → tier2 700
        XCTAssertEqual(FeeMatrixQuoteLogic.proxyRateBp(gmvLastMonthFen: 120_000_000), 700)
        XCTAssertEqual(FeeMatrixQuoteLogic.proxyRateBp(gmvLastMonthFen: 500_000_000), 500)
        XCTAssertEqual(FeeMatrixQuoteLogic.proxyRateBp(gmvLastMonthFen: 499_999_999), 700)
    }

    func testDefaultRateBpPersonalAndBrand() {
        XCTAssertEqual(FeeMatrixQuoteLogic.defaultRateBp(sellerType: "personal", tradeType: "fixed"), 100)
        XCTAssertEqual(FeeMatrixQuoteLogic.defaultRateBp(sellerType: "personal", tradeType: "auction"), 200)
        XCTAssertEqual(FeeMatrixQuoteLogic.defaultRateBp(sellerType: "brand", tradeType: "fixed"), 300)
        XCTAssertNil(FeeMatrixQuoteLogic.defaultRateBp(sellerType: "proxy_agent", tradeType: "auction"))
    }

    // MARK: Profit display

    func testProfitNullDisplaysEmDash() {
        XCTAssertNil(IncomeProfitLogic.profitFen(sellerNetFen: 100, actualShippingCostFen: 0, costPriceFen: nil))
        XCTAssertEqual(IncomeProfitLogic.profitDisplay(nil), "—")
        XCTAssertEqual(
            IncomeProfitLogic.profitFen(sellerNetFen: 240_000, actualShippingCostFen: 2_000, costPriceFen: 200_000),
            38_000
        )
        XCTAssertEqual(IncomeProfitLogic.profitDisplay(38_000), "¥380")
    }

    func testServiceFeeInvoiceGateHiddenByDefault() {
        XCTAssertFalse(IncomeProfitLogic.showsServiceFeeInvoiceEntry(launchGateOpen: false))
        XCTAssertTrue(IncomeProfitLogic.showsServiceFeeInvoiceEntry(launchGateOpen: true))
    }

    // MARK: Decode

    func testDecodeIncomePage() throws {
        let json = """
        {
          "period": "2026-11",
          "seller_type": "proxy_agent",
          "summary": {
            "gmv": 250000,
            "service_fee": 10000,
            "refund": 0,
            "shipping_fee": 0,
            "channel_fee": 1500,
            "seller_net": 240000,
            "profit": 38000,
            "orders_missing_cost": 1,
            "orders_with_cost": 1,
            "orders_count": 2
          },
          "items": [{
            "order_id": 9,
            "order_no": "P43001",
            "trade_type": "auction",
            "status": "settled",
            "amount": 250000,
            "shipping_fee": 0,
            "platform_fee": 10000,
            "channel_fee": 1500,
            "channel_fee_bearer": "platform",
            "refunded_amount": 0,
            "seller_net": 240000,
            "cost_price": 200000,
            "actual_shipping_cost": 2000,
            "profit": 38000,
            "fee_rule_snapshot": {
              "rule_id": "r1",
              "rate_bp": 400,
              "tier_basis": "monthly_gmv",
              "gmv_last_month": 120000000,
              "channel_fee_bearer": "platform",
              "channel_fee_bp": 60
            }
          }],
          "page": 1,
          "page_size": 20,
          "total": 1
        }
        """.data(using: .utf8)!
        let page = try decoder.decode(IncomePage.self, from: json)
        XCTAssertEqual(page.period, "2026-11")
        XCTAssertTrue(page.isProxyAgent)
        XCTAssertEqual(page.summary.profit, 38_000)
        XCTAssertEqual(page.summary.ordersMissingCost, 1)
        XCTAssertEqual(page.summary.missingCostHint, "1 单未填成本")
        let line = try XCTUnwrap(page.items.first)
        XCTAssertEqual(line.profitDisplay, "¥380")
        XCTAssertEqual(line.feeRuleSnapshot?.tierBasis, "monthly_gmv")
        XCTAssertEqual(line.feeRuleSnapshot?.gmvLastMonth, 120_000_000)
        XCTAssertEqual(line.bearer, .platform)
    }

    func testDecodeIncomeLineMissingCost() throws {
        let json = """
        {
          "order_id": 3,
          "amount": 10000,
          "shipping_fee": 0,
          "platform_fee": 100,
          "channel_fee": 60,
          "refunded_amount": 0,
          "seller_net": 9900,
          "cost_price": null,
          "profit": null
        }
        """.data(using: .utf8)!
        let line = try decoder.decode(IncomeOrderLine.self, from: json)
        XCTAssertFalse(line.hasCost)
        XCTAssertEqual(line.profitDisplay, "—")
    }

    func testDecodeOrderCost() throws {
        let json = """
        {"order_id":7,"cost_price":200000,"actual_shipping_cost":2000,"updated_by":1,"version":2}
        """.data(using: .utf8)!
        let cost = try decoder.decode(OrderCost.self, from: json)
        XCTAssertEqual(cost.orderId, 7)
        XCTAssertEqual(cost.costPrice, 200_000)
        XCTAssertEqual(cost.actualShippingCost, 2_000)
        XCTAssertTrue(cost.hasCostPrice)
    }

    func testFeeDealSnapshotStripsBuyerInternals() {
        let snap = FeeDealSnapshot(
            ruleId: "secret",
            rateBp: 700,
            tierBasis: "monthly_gmv",
            gmvLastMonth: 120_000_000,
            channelFeeBearer: "platform",
            platformFee: 10_000
        )
        let buyer = snap.strippedForBuyer()
        XCTAssertNil(buyer.ruleId)
        XCTAssertNil(buyer.tierBasis)
        XCTAssertNil(buyer.gmvLastMonth)
        XCTAssertEqual(buyer.rateBp, 700)
        XCTAssertEqual(buyer.platformFee, 10_000)
    }

    func testErrorCodeNormalize() {
        XCTAssertEqual(IncomeErrorCode.normalize("fee_rule_missing"), .feeRuleMissing)
        XCTAssertEqual(IncomeErrorCode.normalize("not_launched"), .notLaunched)
        XCTAssertEqual(IncomeErrorCode.normalize("launch_gate_closed"), .notLaunched)
        XCTAssertEqual(IncomeErrorCode.normalize("forbidden"), .forbidden)
        XCTAssertEqual(IncomeErrorCode.normalize("period_empty"), .periodEmpty)
        XCTAssertEqual(IncomeErrorCode.normalize("http_404"), .notFound)
    }

    func testOrderCostUpdateBody() {
        let req = OrderCostUpdateRequest(costPrice: 200_000, actualShippingCost: 2_000)
        XCTAssertEqual(req.body["cost_price"] as? Int64, 200_000)
        XCTAssertEqual(req.body["actual_shipping_cost"] as? Int64, 2_000)
    }

    func testServiceFeeInvoiceSubmitBody() {
        let body = ServiceFeeInvoiceSubmitBody(period: "2026-11", title: "毂毂", taxNo: "91110000", email: "a@b.c")
        XCTAssertEqual(body.body["kind"] as? String, "service_fee")
        XCTAssertEqual(body.body["tax_no"] as? String, "91110000")
    }

    func testCopyHighlights() {
        XCTAssertEqual(IncomeCopy.homeTitle, "收入与利润")
        XCTAssertTrue(IncomeCopy.formulaHint.contains("实收"))
        XCTAssertTrue(IncomeCopy.proxyPrivacy.contains("仅自己可见"))
        XCTAssertEqual(IncomeCopy.gmvNotRevenue, "非营收")
    }
}
