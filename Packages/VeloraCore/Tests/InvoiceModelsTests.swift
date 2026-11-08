import XCTest
@testable import VeloraCore

final class InvoiceModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dt = withFrac.date(from: s) { return dt }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let dt = plain.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    // MARK: Defaults / copy

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(InvoiceConfigDefaults.basis, .platformFee)
        XCTAssertEqual(InvoiceConfigDefaults.invoiceType, .vatESpecial)
        XCTAssertEqual(InvoiceConfigDefaults.taxRate, 0.06, accuracy: 1e-9)
        XCTAssertEqual(InvoiceConfigDefaults.dualReviewFen, 1_000_000)
        XCTAssertFalse(InvoiceConfigDefaults.allowWithdrawDefault)
        XCTAssertTrue(InvoiceConfigDefaults.allowZeroOffsetOnly)
        XCTAssertFalse(InvoiceConfigDefaults.allowIdAsTaxNoDefault)
        XCTAssertEqual(InvoiceConfigDefaults.maxTitlesPerSeller, 3)
        XCTAssertEqual(InvoiceConfigDefaults.maxOrdersPerRequest, 100)
        XCTAssertEqual(InvoiceConfigDefaults.fileURLTTLMinutes, 10)
        XCTAssertEqual(InvoiceConfigDefaults.launchGateKey, "launch_gate.proxy_invoice")
        XCTAssertEqual(InvoiceConfigDefaults.notifyIssuedCode, "N-34")
        XCTAssertEqual(InvoiceConfigDefaults.meEntryKey, "invoice")
        XCTAssertTrue(InvoiceConfigDefaults.fileNamePrefix.contains("发票"))
    }

    func testCopyIsPlainLanguageAndB04Safe() {
        XCTAssertTrue(InvoiceCopy.basisPlatformFee.contains("平台服务费"))
        XCTAssertTrue(InvoiceCopy.basisGMV.contains("成交额"))
        XCTAssertFalse(InvoiceCopy.basisPlatformFee.contains("委托人"))
        XCTAssertFalse(InvoiceCopy.emptyPoolHint.contains("委托人"))
        XCTAssertEqual(InvoiceCopy.gateClosed, "开票服务即将开通")
        XCTAssertTrue(InvoiceCopy.rejectNextStep.contains("抬头"))
        XCTAssertTrue(InvoiceCopy.offsetLinePrefix.contains("冲减"))
    }

    // MARK: Invoiceable amounts (§5.9)

    func testPlatformFeeInvoiceableExample() {
        // 成交价 2500 元，费率 6%，服务费 15000 分 → 可开票 15000
        let fen = InvoiceLogic.invoiceableAmount(
            basis: .platformFee,
            gmv: 250_000,
            platformFee: 15_000,
            refundedAmount: 0,
            alreadyInvoiced: 0,
            feeRateSnapshot: 0.06
        )
        XCTAssertEqual(fen, 15_000)
    }

    func testGMVInvoiceableExample() {
        let fen = InvoiceLogic.invoiceableAmount(
            basis: .gmv,
            gmv: 250_000,
            platformFee: 15_000,
            refundedAmount: 0,
            alreadyInvoiced: 0
        )
        XCTAssertEqual(fen, 250_000)
    }

    func testPartialRefundOffsets() {
        // 部分退 500 元货价：platform_fee 冲 round(50000×6%)=3000；gmv 冲 50000
        let fee = InvoiceLogic.invoiceableAmount(
            basis: .platformFee,
            gmv: 250_000,
            platformFee: 15_000,
            refundedAmount: 50_000,
            alreadyInvoiced: 0,
            feeRateSnapshot: 0.06
        )
        XCTAssertEqual(fee, 12_000)
        XCTAssertEqual(InvoiceLogic.refundFeeOffset(refundedGoodsFen: 50_000, feeRate: 0.06), 3_000)

        let gmv = InvoiceLogic.invoiceableAmount(
            basis: .gmv,
            gmv: 250_000,
            platformFee: 15_000,
            refundedAmount: 50_000,
            alreadyInvoiced: 0
        )
        XCTAssertEqual(gmv, 200_000)
    }

    func testPoolMinusPendingOffsetsAndZeroOffsetOnly() {
        let items = [
            InvoiceRequestItem(orderId: 1, invoiceableAmount: 10_000),
            InvoiceRequestItem(orderId: 2, invoiceableAmount: 5_000),
        ]
        let offsets = [
            InvoiceOffset(id: 1, amount: 20_000, status: .pending),
        ]
        let totals = InvoiceLogic.buildPreviewTotals(items: items, offsets: offsets)
        XCTAssertEqual(totals.amount, 0)
        XCTAssertTrue(totals.offsetOnly)
        XCTAssertEqual(totals.tax, 0)
        XCTAssertEqual(totals.total, 0)

        let positive = InvoiceLogic.buildPreviewTotals(
            items: items,
            offsets: [InvoiceOffset(id: 2, amount: 3_000, status: .pending)]
        )
        XCTAssertEqual(positive.amount, 12_000)
        XCTAssertEqual(positive.tax, InvoiceLogic.taxAmount(amountFen: 12_000))
        XCTAssertEqual(positive.total, 12_000 + positive.tax)
        XCTAssertFalse(positive.offsetOnly)
    }

    func testTaxExclusiveRounding() {
        XCTAssertEqual(InvoiceLogic.taxAmount(amountFen: 15_000, taxRate: 0.06), 900)
        XCTAssertEqual(InvoiceLogic.totalAmount(amountFen: 15_000, taxRate: 0.06), 15_900)
        XCTAssertEqual(InvoiceLogic.taxAmount(amountFen: 0), 0)
    }

    // MARK: Periods

    func testPreviousMonthPeriodShanghai() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = InvoiceLogic.shanghaiTimeZone()
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 5
        comps.hour = 3
        let now = cal.date(from: comps)!
        XCTAssertEqual(InvoiceLogic.previousMonthPeriod(now: now), "2026-10")
        XCTAssertEqual(InvoiceLogic.currentMonthPeriod(now: now), "2026-11")

        comps.month = 1
        let jan = cal.date(from: comps)!
        XCTAssertEqual(InvoiceLogic.previousMonthPeriod(now: jan), "2025-12")
    }

    func testPerOrderPeriodOrderIndependent() {
        let a = InvoiceLogic.perOrderPeriod(orderNos: ["B", "A", "C"])
        let b = InvoiceLogic.perOrderPeriod(orderNos: ["C", "A", "B"])
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("order:"))
        XCTAssertNotEqual(a, InvoiceLogic.perOrderPeriod(orderNos: ["A", "B"]))
    }

    func testSupplementPeriod() {
        XCTAssertEqual(InvoiceLogic.supplementPeriod(base: "2026-10", n: 1), "2026-10-supp-1")
        XCTAssertTrue(InvoiceLogic.isMonthlyPeriod("2026-10"))
        XCTAssertTrue(InvoiceLogic.isMonthlyPeriod("2026-10-supp-2"))
        XCTAssertFalse(InvoiceLogic.isMonthlyPeriod("order:abc"))
    }

    // MARK: Tax no / email

    func testUSCCValidation() {
        let valid = usccWithValidCheck("91110000MA0123456")
        XCTAssertTrue(InvoiceLogic.isValidUSCC(valid))
        XCTAssertEqual(valid, "91110000MA0123456P")
        XCTAssertFalse(InvoiceLogic.isValidUSCC("91110000MA0123456A"))
        XCTAssertFalse(InvoiceLogic.isValidUSCC("123"))
        XCTAssertEqual(InvoiceLogic.validateTaxNo("bad"), .taxNoInvalid)
    }

    func testMainlandIDOptional() {
        // 11010119900307893X check digit for demo — use algorithmically valid
        let id = mainlandIDWithValidCheck("11010119900307893")
        XCTAssertTrue(InvoiceLogic.isValidMainlandID(id))
        XCTAssertNil(InvoiceLogic.validateTaxNo(id, allowID: true))
        XCTAssertEqual(InvoiceLogic.validateTaxNo(id, allowID: false), .taxNoInvalid)
    }

    func testEmailValidation() {
        XCTAssertTrue(InvoiceLogic.isValidEmail("a@b.co"))
        XCTAssertTrue(InvoiceLogic.isValidEmail("finance@example.com"))
        XCTAssertFalse(InvoiceLogic.isValidEmail("no-at"))
        XCTAssertFalse(InvoiceLogic.isValidEmail("@x.com"))
        XCTAssertFalse(InvoiceLogic.isValidEmail("a@b"))
    }

    func testTitleFormAndCapacity() {
        let uscc = usccWithValidCheck("91110000MA0123456")
        XCTAssertNil(InvoiceLogic.validateTitleForm(title: "毂毂科技", taxNo: uscc, email: "a@b.co"))
        XCTAssertNotNil(InvoiceLogic.validateTitleForm(title: "", taxNo: uscc, email: "a@b.co"))
        XCTAssertTrue(InvoiceLogic.canAddTitle(existingCount: 2))
        XCTAssertFalse(InvoiceLogic.canAddTitle(existingCount: 3))
    }

    // MARK: State machine

    func testLegalAndIllegalTransitions() {
        XCTAssertTrue(InvoiceLogic.canTransition(from: .draft, to: .submitted))
        XCTAssertTrue(InvoiceLogic.canTransition(from: .submitted, to: .issuing))
        XCTAssertTrue(InvoiceLogic.canTransition(from: .submitted, to: .rejected))
        XCTAssertTrue(InvoiceLogic.canTransition(from: .issuing, to: .issued))
        XCTAssertTrue(InvoiceLogic.canTransition(from: .issuing, to: .submitted))
        XCTAssertTrue(InvoiceLogic.canTransition(from: .rejected, to: .submitted))

        XCTAssertFalse(InvoiceLogic.canTransition(from: .draft, to: .issued))
        XCTAssertFalse(InvoiceLogic.canTransition(from: .rejected, to: .issuing))
        XCTAssertFalse(InvoiceLogic.canTransition(from: .issued, to: .submitted))
        XCTAssertFalse(InvoiceLogic.canTransition(from: .issuing, to: .draft))
        XCTAssertFalse(InvoiceLogic.canTransition(from: .issued, to: .rejected))

        XCTAssertFalse(InvoiceLogic.canEditTitle(status: .issuing))
        XCTAssertTrue(InvoiceLogic.canEditTitle(status: .rejected))
        XCTAssertFalse(InvoiceLogic.canWithdraw(status: .submitted))
        XCTAssertTrue(InvoiceLogic.canWithdraw(status: .submitted, allowWithdraw: true))
    }

    func testDualReviewAndIssuingStall() {
        XCTAssertFalse(InvoiceLogic.requiresDualReview(amountFen: 999_999))
        XCTAssertTrue(InvoiceLogic.requiresDualReview(amountFen: 1_000_000))
        let entered = Date().addingTimeInterval(-2 * 3600)
        XCTAssertTrue(InvoiceLogic.showsIssuingStall(status: .issuing, enteredIssuingAt: entered))
        XCTAssertFalse(InvoiceLogic.showsIssuingStall(status: .submitted, enteredIssuingAt: entered))
    }

    func testTimelineAndDownload() {
        let issued = InvoiceLogic.timeline(for: .issued)
        XCTAssertEqual(issued.map(\.0), InvoiceTimelineStep.allCases)
        XCTAssertTrue(issued.allSatisfy(\.1))
        let submitted = InvoiceLogic.timeline(for: .submitted)
        XCTAssertEqual(submitted.first?.0, .submitted)
        XCTAssertTrue(submitted.first?.1 == true)
        XCTAssertFalse(submitted.last?.1 == true)

        let req = InvoiceRequest(
            id: 1,
            mode: .monthly,
            period: "2026-10",
            amount: 15_000,
            taxAmount: 900,
            status: .issued,
            invoiceNo: "FP202610001"
        )
        XCTAssertTrue(req.canDownload)
        XCTAssertEqual(req.fileDownloadName, "毂毂_发票_FP202610001.pdf")
        XCTAssertEqual(req.total, 15_900)

        let offsetOnly = InvoiceRequest(
            id: 2,
            mode: .monthly,
            period: "2026-10",
            amount: 0,
            status: .issued,
            offsetOnly: true
        )
        XCTAssertTrue(offsetOnly.isOffsetOnly)
        XCTAssertFalse(offsetOnly.canDownload)
    }

    func testSubmitGate() {
        XCTAssertEqual(
            InvoiceLogic.submitGate(
                isLoggedIn: false,
                isProxyAgent: true,
                canInvoiceService: true,
                launchGateOpen: true,
                accountFrozen: false
            ),
            .unauthorized
        )
        XCTAssertEqual(
            InvoiceLogic.submitGate(
                isLoggedIn: true,
                isProxyAgent: false,
                canInvoiceService: true,
                launchGateOpen: true,
                accountFrozen: false
            ),
            .forbidden
        )
        XCTAssertEqual(
            InvoiceLogic.submitGate(
                isLoggedIn: true,
                isProxyAgent: true,
                canInvoiceService: false,
                launchGateOpen: true,
                accountFrozen: false
            ),
            .capabilityDisabled
        )
        XCTAssertEqual(
            InvoiceLogic.submitGate(
                isLoggedIn: true,
                isProxyAgent: true,
                canInvoiceService: true,
                launchGateOpen: false,
                accountFrozen: false
            ),
            .launchGateClosed
        )
        XCTAssertNil(
            InvoiceLogic.submitGate(
                isLoggedIn: true,
                isProxyAgent: true,
                canInvoiceService: true,
                launchGateOpen: true,
                accountFrozen: false
            )
        )
    }

    func testPerOrderSelectionLimits() {
        XCTAssertNil(InvoiceLogic.validateSubmitSelection(mode: .monthly, orderIds: []))
        XCTAssertEqual(InvoiceLogic.validateSubmitSelection(mode: .perOrder, orderIds: []), .nothingToInvoice)
        XCTAssertNil(InvoiceLogic.validateSubmitSelection(mode: .perOrder, orderIds: [1, 2]))
        let tooMany = Array(1...101).map(Int64.init)
        XCTAssertEqual(InvoiceLogic.validateSubmitSelection(mode: .perOrder, orderIds: tooMany), .nothingToInvoice)
    }

    // MARK: Decoding

    func testPreviewDecodesSnakeCase() throws {
        let json = """
        {
          "mode": "monthly",
          "period": "2026-10",
          "basis": "platform_fee",
          "basis_label": "按平台服务费",
          "tax_rate": 0.06,
          "invoice_type": "vat_e_special",
          "items": [
            {
              "order_id": 9,
              "order_no": "O9",
              "gmv": 250000,
              "platform_fee": 15000,
              "refunded_amount": 0,
              "invoiceable_amount": 15000,
              "selectable": true
            }
          ],
          "offsets": [
            {"id": 1, "amount": 1000, "status": "pending", "source_order_id": 3}
          ],
          "amount": 14000,
          "tax_amount": 840,
          "total": 14840,
          "lock_warning": null,
          "launch_gate_open": true,
          "can_submit": true
        }
        """.data(using: .utf8)!
        let preview = try decoder.decode(InvoicePreview.self, from: json)
        XCTAssertEqual(preview.basis, .platformFee)
        XCTAssertEqual(preview.items.count, 1)
        XCTAssertEqual(preview.items[0].orderId, 9)
        XCTAssertEqual(preview.pendingOffsetTotal, 1_000)
        XCTAssertTrue(preview.allowsSubmit)
        XCTAssertEqual(preview.resolvedBasisLabel, "按平台服务费")
        XCTAssertFalse(preview.items[0].orderNo == nil)
        // B-04: no consignor fields on item payload keys we decode.
        XCTAssertNil(preview.items[0].blockReason)
    }

    func testRequestStatusLabels() {
        XCTAssertEqual(InvoiceRequestStatus.submitted.displayLabel, "待审核")
        XCTAssertEqual(InvoiceRequestStatus.issued.displayLabel, "已开具")
        XCTAssertTrue(InvoiceRequestStatus.submitted.locksPeriod)
        XCTAssertEqual(InvoiceMode.perOrder.displayLabel, "按单开票")
        XCTAssertEqual(InvoiceBasis.platformFee.plainExplanation, InvoiceCopy.basisPlatformFee)
    }

    func testMaskingHelpers() {
        XCTAssertEqual(InvoiceLogic.maskEmail("finance@example.com"), "f***@example.com")
        let masked = InvoiceLogic.maskTaxNo("91110000MA01234567")
        XCTAssertTrue(masked.hasPrefix("9111"))
        XCTAssertTrue(masked.hasSuffix("4567"))
        XCTAssertTrue(masked.contains("*"))
        XCTAssertEqual(InvoiceLogic.offsetLine(amountFen: 12_300), "上期退款冲减 -¥123")
    }

    // MARK: Helpers

    private func usccWithValidCheck(_ prefix17: String) -> String {
        let charset = Array("0123456789ABCDEFGHJKLMNPQRTUWXY")
        let weights = [1, 3, 9, 27, 81, 243, 729, 2187, 6561, 19683, 59049, 177147, 531441, 1594323, 4782969, 14348907, 43046721]
        let s = prefix17.uppercased()
        XCTAssertEqual(s.count, 17)
        var sum = 0
        for (i, ch) in s.enumerated() {
            let idx = charset.firstIndex(of: ch)!
            sum += idx * weights[i]
        }
        let mod = sum % 31
        let checkIdx = mod == 0 ? 0 : 31 - mod
        return s + String(charset[checkIdx])
    }

    private func mainlandIDWithValidCheck(_ prefix17: String) -> String {
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        var sum = 0
        for (i, ch) in prefix17.enumerated() {
            sum += ch.wholeNumberValue! * weights[i]
        }
        return prefix17 + String(checks[sum % 11])
    }
}
