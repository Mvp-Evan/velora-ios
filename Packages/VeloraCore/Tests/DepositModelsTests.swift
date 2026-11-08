import XCTest
@testable import VeloraCore

final class DepositModelsTests: XCTestCase {
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

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(DepositConfigDefaults.bidRateBp, 1_000)
        XCTAssertEqual(DepositConfigDefaults.bidMinFen, 5_000)
        XCTAssertEqual(DepositConfigDefaults.bidMaxFen, 200_000)
        XCTAssertEqual(DepositConfigDefaults.lotteryDefaultFen, 20_000)
        XCTAssertEqual(DepositConfigDefaults.sellerPersonalFen, 50_000)
        XCTAssertEqual(DepositConfigDefaults.sellerProxyFen, 500_000)
        XCTAssertEqual(DepositConfigDefaults.sellerBrandFen, 1_000_000)
        XCTAssertEqual(DepositConfigDefaults.sellerPresaleExtraFen, 500_000)
        XCTAssertEqual(DepositConfigDefaults.sellerExitDays, 30)
        XCTAssertEqual(DepositConfigDefaults.preauthEnabledKey, "payment.preauth.enabled")
        XCTAssertFalse(DepositConfigDefaults.preauthEnabledDefault)
        XCTAssertEqual(DepositConfigDefaults.penaltyObligeeBp, 8_000)
        XCTAssertEqual(DepositConfigDefaults.penaltyPlatformBp, 2_000)
        XCTAssertEqual(DepositConfigDefaults.notifyCode, "N-26")
        XCTAssertEqual(DepositConfigDefaults.meEntryKey, "deposit")
        XCTAssertEqual(DepositConfigDefaults.meSellerEntryKey, "seller_deposit")
        XCTAssertEqual(DepositConfigDefaults.creditBidFloor, 80)
    }

    // MARK: Status normalize / legacy

    func testStatusNormalizeLegacyMappings() {
        XCTAssertEqual(DepositStatus.normalize("pending"), .pending)
        XCTAssertEqual(DepositStatus.normalize("frozen"), .frozen)
        XCTAssertEqual(DepositStatus.normalize("held"), .frozen)
        XCTAssertEqual(DepositStatus.normalize("HOLDING"), .frozen)
        XCTAssertEqual(DepositStatus.normalize("released"), .released)
        XCTAssertEqual(DepositStatus.normalize("refunded"), .released)
        XCTAssertEqual(DepositStatus.normalize("applied"), .released)
        XCTAssertEqual(DepositStatus.normalize("legacy_applied_to_order"), .released)
        XCTAssertEqual(DepositStatus.normalize("deducted"), .deducted)
        XCTAssertEqual(DepositStatus.normalize("forfeited"), .deducted)
        XCTAssertEqual(DepositStatus.normalize("partially_deducted"), .partiallyDeducted)
        XCTAssertEqual(DepositStatus.normalize("deposit_pending"), .pending)
    }

    func testStatusAllowsBiddingOnlyWhenFrozen() {
        XCTAssertTrue(DepositStatus.frozen.allowsBidding)
        XCTAssertFalse(DepositStatus.pending.allowsBidding)
        XCTAssertFalse(DepositStatus.released.allowsBidding)
        XCTAssertFalse(DepositStatus.deducted.allowsBidding)
        XCTAssertTrue(DepositLogic.isFrozenEnoughForBid(statusRaw: "held"))
        XCTAssertTrue(DepositLogic.isFrozenEnoughForBid(statusRaw: "frozen"))
        XCTAssertFalse(DepositLogic.isFrozenEnoughForBid(statusRaw: "pending"))
        XCTAssertFalse(DepositLogic.isFrozenEnoughForBid(statusRaw: "applied"))
    }

    func testStatusDisplayLabels() {
        XCTAssertEqual(DepositStatus.pending.displayLabel, "处理中")
        XCTAssertEqual(DepositStatus.frozen.displayLabel, "已冻结")
        XCTAssertEqual(DepositStatus.released.displayLabel, "已解冻")
        XCTAssertEqual(DepositStatus.deducted.displayLabel, "已扣除")
        XCTAssertEqual(DepositStatus.partiallyDeducted.displayLabel, "部分扣除")
    }

    // MARK: Method unified copy

    func testMethodCopyIsUnifiedFreeze() {
        XCTAssertEqual(DepositMethod.preauth.userFacingVerb, "冻结保证金")
        XCTAssertEqual(DepositMethod.payment.userFacingVerb, "冻结保证金")
        XCTAssertEqual(DepositMethod.preauth.displayLabel, DepositMethod.payment.displayLabel)
        XCTAssertEqual(DepositLogic.methodUserCopy(.preauth), DepositCopy.freezeVerb)
        XCTAssertEqual(DepositLogic.methodUserCopy(.payment), DepositCopy.freezeVerb)
        XCTAssertEqual(DepositLogic.methodUserCopy(nil), DepositCopy.freezeVerb)
        XCTAssertEqual(DepositMethod.normalize("pre_auth"), .preauth)
        XCTAssertEqual(DepositMethod.normalize("escrow"), .payment)
        XCTAssertEqual(DepositPaymentKind.depositPreauth.displayLabel, "冻结保证金")
        XCTAssertEqual(DepositPaymentKind.deposit.displayLabel, "冻结保证金")
        XCTAssertEqual(DepositPaymentKind.sellerDeposit.displayLabel, "冻结保证金")
    }

    // MARK: Types

    func testDepositTypeLabelsAndAliases() {
        XCTAssertEqual(DepositType.bid.displayLabel, "参拍保证金")
        XCTAssertEqual(DepositType.lottery.displayLabel, "抽签保证金")
        XCTAssertEqual(DepositType.seller.displayLabel, "卖家保证金")
        XCTAssertEqual(DepositType.normalize("lot"), .bid)
        XCTAssertEqual(DepositType.normalize("draw"), .lottery)
        XCTAssertEqual(DepositType.normalize("seller_deposit"), .seller)
    }

    // MARK: Penalty labels

    func testPenaltyEventLabels() {
        XCTAssertEqual(PenaltyEventCode.buyerNonPayAuction.displayLabel, "拍卖逾期未付")
        XCTAssertEqual(PenaltyEventCode.buyerNonPayLottery.displayLabel, "抽签中签逾期未付")
        XCTAssertEqual(PenaltyEventCode.sellerRefuseShip.displayLabel, "卖家拒发/诱导线下")
        XCTAssertEqual(PenaltyEventCode.sellerConcealFlaw.displayLabel, "卖家隐瞒瑕疵")
        XCTAssertEqual(PenaltyEventCode.buyerMaliciousDamage.displayLabel, "买家恶意损毁")
        XCTAssertTrue(PenaltyEventCode.buyerNonPayAuction.noticeReason.contains("保证金"))
        XCTAssertFalse(PenaltyEventCode.buyerNonPayAuction.noticeReason.contains("80%"))
        XCTAssertEqual(PenaltyEventCode.normalize("buyer_non_pay"), .buyerNonPayAuction)
        XCTAssertEqual(PenaltyEventCode.normalize("refuse_ship"), .sellerRefuseShip)
        XCTAssertTrue(PenaltyEventCode.buyerNonPayAuction.deductsBuyer)
        XCTAssertFalse(PenaltyEventCode.sellerRefuseShip.deductsBuyer)
    }

    // MARK: Seller gap messaging

    func testSellerGapMessaging() {
        XCTAssertEqual(SellerDepositLogic.gapAmount(required: 50_000, held: 0), 50_000)
        XCTAssertEqual(SellerDepositLogic.gapAmount(required: 50_000, held: 50_000), 0)
        XCTAssertEqual(SellerDepositLogic.gapAmount(required: 50_000, held: 60_000), 0)
        XCTAssertTrue(SellerDepositLogic.blocksPublish(required: 50_000, held: 0))
        XCTAssertFalse(SellerDepositLogic.blocksPublish(required: 50_000, held: 50_000))

        let msg = SellerDepositLogic.gapMessage(required: 50_000, held: 0)
        XCTAssertTrue(msg.contains("补缴"))
        XCTAssertTrue(msg.contains("500"))
        XCTAssertEqual(SellerDepositLogic.gapMessage(required: 50_000, held: 50_000), DepositCopy.alreadySufficient)
        XCTAssertEqual(
            SellerDepositLogic.gapMessage(required: 1_500_000, held: 1_000_000, isPresaleExtra: true),
            DepositCopy.brandPresaleGap
        )

        XCTAssertEqual(SellerDepositTier.personal.requiredFen, 50_000)
        XCTAssertEqual(SellerDepositTier.proxyAgent.requiredFen, 500_000)
        XCTAssertEqual(SellerDepositTier.brand.requiredFen, 1_000_000)
        XCTAssertEqual(
            SellerDepositLogic.requiredFen(for: .brand, includePresaleExtra: true),
            1_500_000
        )
    }

    func testSellerExitCoolingCopy() {
        let due = Date().addingTimeInterval(3 * 86_400 + 3_600)
        let days = SellerDepositLogic.exitRemainingDays(exitDueAt: due)
        XCTAssertEqual(days, 4)
        XCTAssertTrue(SellerDepositLogic.exitCoolingMessage(remainingDays: 4).contains("4"))
        XCTAssertEqual(SellerDepositLogic.exitRemainingDays(exitDueAt: nil), nil)
    }

    // MARK: Error codes

    func testErrorFallbacks() {
        XCTAssertEqual(DepositErrorCode.depositNotFrozen.fallbackMessage, DepositCopy.needFreezeFirst)
        XCTAssertEqual(DepositErrorCode.sellerDepositInsufficient.fallbackMessage, DepositCopy.sellerGapTitle)
        XCTAssertTrue(DepositErrorCode.creditTooLow.fallbackMessage.contains("信用"))
        XCTAssertTrue(DepositErrorCode.depositNotFrozen.opensDepositSheet)
        XCTAssertTrue(DepositErrorCode.sellerDepositInsufficient.opensSellerDeposit)
        XCTAssertTrue(DepositErrorCode.creditTooLow.opensCreditHelp)
        XCTAssertEqual(DepositCopy.emptyTitle, "暂无冻结")
        XCTAssertTrue(DepositCopy.bidSheetHint.contains("未中拍"))
        XCTAssertTrue(DepositCopy.bidSheetHint.contains("货款另付"))
        XCTAssertFalse(DepositCopy.bidSheetHint.contains("抵扣"))
    }

    // MARK: Bid amount clamp (B-07)

    func testBidRequiredFenClamp() {
        // start 100 元 → floor 50 元
        XCTAssertEqual(DepositLogic.bidRequiredFen(startPriceFen: 10_000), 5_000)
        // start 5 万 → cap 2000 元
        XCTAssertEqual(DepositLogic.bidRequiredFen(startPriceFen: 5_000_000), 200_000)
        // start 800 → 80 元
        XCTAssertEqual(DepositLogic.bidRequiredFen(startPriceFen: 80_000), 8_000)
    }

    // MARK: Decode

    func testDecodeLotDepositInfoWithLegacyHeld() throws {
        let json = Data("""
        {
          "deposit": {
            "id": 9,
            "lot_id": 42,
            "buyer_id": 7,
            "amount": 5000,
            "status": "held",
            "method": "payment"
          },
          "required": true,
          "required_amount": 5000
        }
        """.utf8)
        let info = try decoder.decode(LotDepositInfo.self, from: json)
        XCTAssertEqual(info.deposit?.status, .frozen)
        XCTAssertTrue(info.isFrozen)
        XCTAssertEqual(info.resolvedAmount, 5_000)
        XCTAssertEqual(info.deposit?.methodUserLabel, "冻结保证金")
        XCTAssertEqual(info.deposit?.lotId, 42)
        XCTAssertEqual(info.deposit?.buyerId, 7)
    }

    func testDecodeMeDepositsAndSellerAccount() throws {
        let json = Data("""
        {
          "items": [
            {
              "id": 1,
              "type": "bid",
              "ref_id": 10,
              "amount": 8000,
              "method": "preauth",
              "status": "frozen",
              "title": "拍品 A"
            }
          ],
          "seller_account": {
            "user_id": 3,
            "required_amount": 50000,
            "held_amount": 20000,
            "seller_type": "personal",
            "status": "frozen"
          }
        }
        """.utf8)
        let resp = try decoder.decode(MeDepositsResponse.self, from: json)
        XCTAssertEqual(resp.items.count, 1)
        XCTAssertEqual(resp.items[0].type, .bid)
        XCTAssertEqual(resp.items[0].method, .preauth)
        XCTAssertEqual(resp.items[0].methodUserLabel, "冻结保证金")
        XCTAssertEqual(resp.sellerAccount?.gapAmount, 30_000)
        XCTAssertTrue(resp.sellerAccount?.blocksPublish == true)
        XCTAssertTrue(resp.sellerAccount?.gapMessage.contains("补缴") == true)
        XCTAssertEqual(resp.sellerAccount?.sellerType, .personal)
    }

    func testDecodeDepositsAliasKey() throws {
        let json = Data("""
        { "deposits": [ { "id": 2, "type": "lottery", "amount": 20000, "status": "released" } ] }
        """.utf8)
        let resp = try decoder.decode(MeDepositsResponse.self, from: json)
        XCTAssertEqual(resp.items.first?.type, .lottery)
        XCTAssertEqual(resp.items.first?.status, .released)
    }

    func testPenaltyRuleDisplay() {
        let rule = PenaltyRule(eventCode: .buyerNonPayAuction)
        XCTAssertEqual(rule.obligeeBp, 8_000)
        XCTAssertEqual(rule.platformBp, 2_000)
        XCTAssertEqual(rule.displayLabel, "拍卖逾期未付")
        XCTAssertEqual(rule.id, "buyer_non_pay_auction")
    }

    func testSellerDepositAccountComputedGap() throws {
        let json = Data("""
        { "required_amount": 500000, "held_amount": 100000, "seller_type": "proxy_agent" }
        """.utf8)
        let acct = try decoder.decode(SellerDepositAccount.self, from: json)
        XCTAssertEqual(acct.gapAmount, 400_000)
        XCTAssertEqual(acct.sellerType, .proxyAgent)
        XCTAssertTrue(acct.blocksPublish)
    }
}
