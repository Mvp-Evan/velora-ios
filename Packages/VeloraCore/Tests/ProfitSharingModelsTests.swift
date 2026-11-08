import XCTest
@testable import VeloraCore

final class ProfitSharingModelsTests: XCTestCase {
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

    // MARK: Defaults

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(ProfitSharingConfigDefaults.launchGateKey, "launch_gate.profit_sharing")
        XCTAssertEqual(ProfitSharingConfigDefaults.signedByKey, "gate.profit_sharing.signed_by")
        XCTAssertEqual(ProfitSharingConfigDefaults.shareRetryMax, 3)
        XCTAssertEqual(ProfitSharingConfigDefaults.shareRetryBackoffSec, [60, 300, 1_800])
        XCTAssertEqual(ProfitSharingConfigDefaults.settleModeDefault, .onConfirm)
        XCTAssertEqual(ProfitSharingConfigDefaults.paymentStalePayingSec, 120)
        XCTAssertEqual(ProfitSharingConfigDefaults.onboardingSignTimeoutDays, 7)
        XCTAssertEqual(ProfitSharingConfigDefaults.shareQueryAfterSec, 60)
        XCTAssertEqual(ProfitSharingConfigDefaults.notifySettledCode, "N-20")
        XCTAssertEqual(ProfitSharingConfigDefaults.meEntryKey, "sub_merchant")
        XCTAssertTrue(ProfitSharingConfigDefaults.platformFeeDescription.contains("平台服务费"))
    }

    // MARK: Status machine / progress

    func testStatusNormalizeAliases() {
        XCTAssertEqual(SubMerchantStatus.normalize("channel_reviewing"), .channelReviewing)
        XCTAssertEqual(SubMerchantStatus.normalize("reviewing"), .channelReviewing)
        XCTAssertEqual(SubMerchantStatus.normalize("applying"), .channelReviewing)
        XCTAssertEqual(SubMerchantStatus.normalize("pending_sign"), .toSign)
        XCTAssertEqual(SubMerchantStatus.normalize("to_sign"), .toSign)
        XCTAssertEqual(SubMerchantStatus.normalize("finished"), .finished)
        XCTAssertEqual(SubMerchantStatus.normalize("failed"), .failed)
        XCTAssertEqual(SubMerchantStatus.normalize("draft"), .draft)
        XCTAssertEqual(SubMerchantStatus.normalize("submitted"), .submitted)
    }

    func testProgressStepsDraftToFinished() {
        let order: [SubMerchantStatus] = [.draft, .submitted, .channelReviewing, .toSign, .finished]
        XCTAssertEqual(order.map(\.displayLabel), ["未提交", "已提交", "审核中", "待签约", "已完成"])
        XCTAssertEqual(SubMerchantProgressStep.allCases.map(\.title), ["提交", "审核", "待签约", "完成"])

        XCTAssertEqual(SubMerchantProgressLogic.currentIndex(status: .draft), 0)
        XCTAssertEqual(SubMerchantProgressLogic.currentIndex(status: .submitted), 0)
        XCTAssertEqual(SubMerchantProgressLogic.currentIndex(status: .channelReviewing), 1)
        XCTAssertEqual(SubMerchantProgressLogic.currentIndex(status: .toSign), 2)
        XCTAssertEqual(SubMerchantProgressLogic.currentIndex(status: .finished), 3)

        XCTAssertTrue(SubMerchantProgressLogic.isStepComplete(.submit, status: .channelReviewing))
        XCTAssertTrue(SubMerchantProgressLogic.isStepCurrent(.review, status: .channelReviewing))
        XCTAssertFalse(SubMerchantProgressLogic.isStepComplete(.sign, status: .channelReviewing))
        XCTAssertTrue(SubMerchantStatus.finished.blocksPublish == false)
        XCTAssertTrue(SubMerchantStatus.toSign.blocksPublish)
        XCTAssertTrue(SubMerchantStatus.toSign.needsChannelSign)
    }

    func testFailedAllowsResubmit() {
        XCTAssertTrue(SubMerchantStatus.failed.allowsResubmit)
        XCTAssertTrue(SubMerchantStatus.draft.allowsResubmit)
        XCTAssertFalse(SubMerchantStatus.channelReviewing.allowsResubmit)
    }

    // MARK: Fail reasons

    func testFailReasonsAreHumanReadable() {
        XCTAssertEqual(SubMerchantFailReason.blurryDocs.displayMessage, "资料不清晰，请重新拍摄后提交")
        XCTAssertTrue(SubMerchantFailReason.nameMismatch.displayMessage.contains("不符"))
        XCTAssertTrue(SubMerchantFailReason.signTimeout.displayMessage.contains("协议"))
        XCTAssertEqual(SubMerchantFailReason.onboardingFailed.nextStepHint, ProfitSharingCopy.modifyMaterials)
        XCTAssertEqual(SubMerchantFailReason.normalize("blurry_docs"), .blurryDocs)
        XCTAssertEqual(SubMerchantFailReason.normalize("资料模糊"), .blurryDocs)
        XCTAssertEqual(SubMerchantFailReason.normalize("名称不符"), .nameMismatch)
        XCTAssertEqual(SubMerchantFailReason.normalize("id_no_conflict"), .idNoConflict)
    }

    // MARK: Gate messaging

    func testPublishGateMessaging() {
        XCTAssertTrue(ProfitSharingGate.publishBlocked(status: nil))
        XCTAssertTrue(ProfitSharingGate.publishBlocked(status: .draft))
        XCTAssertTrue(ProfitSharingGate.publishBlocked(status: .toSign))
        XCTAssertFalse(ProfitSharingGate.publishBlocked(status: .finished))
        XCTAssertEqual(ProfitSharingCopy.publishGateTitle, "完成收款开户")
        XCTAssertTrue(ProfitSharingGate.publishBlockMessage(status: .draft).contains("进件"))
        XCTAssertEqual(
            ProfitSharingErrorCode.subMerchantRequired.fallbackMessage,
            ProfitSharingCopy.publishGateTitle
        )
        XCTAssertTrue(ProfitSharingErrorCode.subMerchantRequired.opensSubMerchantProgress)
    }

    func testLaunchGateRequiresSignedBy() {
        XCTAssertFalse(ProfitSharingGate.realFundsAllowed(launchGateOpen: true, signedBy: nil))
        XCTAssertFalse(ProfitSharingGate.realFundsAllowed(launchGateOpen: true, signedBy: "  "))
        XCTAssertFalse(ProfitSharingGate.realFundsAllowed(launchGateOpen: false, signedBy: "cfo"))
        XCTAssertTrue(ProfitSharingGate.realFundsAllowed(launchGateOpen: true, signedBy: "cfo"))
        XCTAssertEqual(
            ProfitSharingGate.paymentGateError(launchGateOpen: false, signedBy: "cfo"),
            .launchGateClosed
        )
        XCTAssertNil(ProfitSharingGate.paymentGateError(launchGateOpen: true, signedBy: "cfo"))
        XCTAssertEqual(ProfitSharingErrorCode.launchGateClosed.fallbackMessage, ProfitSharingCopy.gateClosed)
    }

    // MARK: Profit-share seller labels

    func testProfitShareSellerLabelsHidePartialFailure() {
        XCTAssertEqual(ProfitShareStatus.processing.sellerLabel, "结算中")
        XCTAssertEqual(ProfitShareStatus.partial.sellerLabel, "结算中")
        XCTAssertEqual(ProfitShareStatus.pending.sellerLabel, "结算中")
        XCTAssertEqual(ProfitShareStatus.succeeded.sellerLabel, "已到账")
        XCTAssertEqual(ProfitShareStatus.failed.sellerLabel, "结算处理中，无需重试")
        XCTAssertEqual(
            ProfitShareStatus.partial.sellerLabel(inReconcileDesk: true),
            "结算处理中，无需重试"
        )
        XCTAssertFalse(ProfitShareStatus.partial.exposesReceiverFailureToSeller)
        XCTAssertFalse(ProfitShareStatus.failed.exposesReceiverFailureToSeller)
        XCTAssertEqual(ProfitShareSellerLogic.label(statusRaw: "partial"), "结算中")
        XCTAssertEqual(ProfitShareSellerLogic.label(statusRaw: "failed"), "结算处理中，无需重试")
    }

    func testConfirmOrderResultSellerLabel() {
        let result = ConfirmOrderResult(status: "completed", profitShareId: "ps1", profitShareStatus: "processing")
        XCTAssertEqual(result.sellerProfitShareLabel, "结算中")
        let done = ConfirmOrderResult(profitShareStatus: "succeeded")
        XCTAssertEqual(done.sellerProfitShareLabel, "已到账")
    }

    // MARK: Decode GET /me/sub-merchant

    func testDecodeSubMerchantPayload() throws {
        let json = """
        {
          "status": "to_sign",
          "merchant_type": "personal",
          "channel": "wechatpay",
          "channel_sub_mch_id": "sm_1001",
          "sign_url": "https://pay.example/sign",
          "name_masked": "张*",
          "updated_at": "2024-06-01T12:00:00Z"
        }
        """.data(using: .utf8)!
        let sm = try decoder.decode(SubMerchant.self, from: json)
        XCTAssertEqual(sm.status, .toSign)
        XCTAssertEqual(sm.merchantType, .personal)
        XCTAssertEqual(sm.channelSubMchId, "sm_1001")
        XCTAssertEqual(sm.effectiveSignURL?.absoluteString, "https://pay.example/sign")
        XCTAssertTrue(sm.status.needsChannelSign)
        XCTAssertEqual(sm.statusHint, ProfitSharingCopy.toSignHint)
    }

    func testDecodeFailedSubMerchantUsesHumanReason() throws {
        let json = """
        {
          "status": "failed",
          "fail_reason_code": "blurry_docs",
          "fail_reason": "internal_wx_CODE_99"
        }
        """.data(using: .utf8)!
        let sm = try decoder.decode(SubMerchant.self, from: json)
        XCTAssertEqual(sm.status, .failed)
        XCTAssertEqual(sm.resolvedFailReason, .blurryDocs)
        XCTAssertEqual(sm.failDisplayMessage, SubMerchantFailReason.blurryDocs.displayMessage)
        XCTAssertFalse(sm.failDisplayMessage?.contains("CODE_99") == true)
    }

    func testDecodeChannelReviewingAlias() throws {
        let json = #"{"status":"reviewing"}"#.data(using: .utf8)!
        let sm = try decoder.decode(SubMerchant.self, from: json)
        XCTAssertEqual(sm.status, .channelReviewing)
        XCTAssertTrue(sm.status.blocksPublish)
    }

    func testSubmitRequestBody() {
        let req = SubMerchantSubmitRequest(
            merchantType: .sole,
            channel: "alipay",
            bankCardLast4: "1234",
            bankName: "招行",
            licenseNo: "91xxxxx",
            imageKeys: ["img1"]
        )
        let body = req.body
        XCTAssertEqual(body["merchant_type"] as? String, "sole")
        XCTAssertEqual(body["bank_card_last4"] as? String, "1234")
        XCTAssertEqual(body["image_keys"] as? [String], ["img1"])
    }

    func testProfitShareSummarySellerLabel() {
        let s = ProfitShareSummary(
            shareId: "1",
            status: .partial,
            sellerAmount: 240_000,
            inReconcileDesk: false
        )
        XCTAssertEqual(s.sellerStatusLabel, "结算中")
        let desk = ProfitShareSummary(shareId: "2", status: .failed, inReconcileDesk: true)
        XCTAssertEqual(desk.sellerStatusLabel, "结算处理中，无需重试")
    }
}
