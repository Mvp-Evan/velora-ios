import XCTest
@testable import VeloraCore

final class LotteryModelsTests: XCTestCase {
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
                return Date(timeIntervalSince1970: Double(ms) / 1000)
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date"))
        }
        return d
    }()

    private let t0 = ISO8601DateFormatter().date(from: "2026-11-05T04:00:00Z")!

    // MARK: Defaults / statuses / dedup codes

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(LotteryConfigDefaults.payWindowSec, 7_200)
        XCTAssertEqual(LotteryConfigDefaults.payWindowMinSec, 1_800)
        XCTAssertEqual(LotteryConfigDefaults.payWindowMaxSec, 86_400)
        XCTAssertEqual(LotteryConfigDefaults.depositDefaultFen, 20_000)
        XCTAssertEqual(LotteryConfigDefaults.creditMin, 80)
        XCTAssertEqual(LotteryConfigDefaults.n12RemindSec, 1_800)
        XCTAssertEqual(LotteryConfigDefaults.algorithmVersion, "fy-sha256-v1")
        XCTAssertEqual(LotteryConfigDefaults.orderType, "lottery")
        XCTAssertEqual(LotteryConfigDefaults.depositType, "lottery")
        XCTAssertEqual(LotteryConfigDefaults.meEntryKey, "lottery")
        XCTAssertEqual(LotteryConfigDefaults.seedPrefixLength, 8)
    }

    func testEntryStatusesAndTransitionsLabels() {
        XCTAssertEqual(LotteryEntryStatus.allCases.map(\.rawValue), [
            "registered", "won", "waitlisted", "lost", "paid", "forfeited",
        ])
        XCTAssertEqual(LotteryEntryStatus.won.displayLabel, "中签待付")
        XCTAssertEqual(LotteryEntryStatus.waitlisted.displayLabel, "候补")
        XCTAssertTrue(LotteryEntryStatus.forfeited.isTerminal)
        XCTAssertTrue(LotteryEntryStatus.won.showsPayCTA)
        XCTAssertTrue(LotteryEntryStatus.lost.showsDepositReleasedHint)
        XCTAssertFalse(LotteryEntryStatus.forfeited.showsPayCTA)
    }

    func testReleaseStatuses() {
        XCTAssertEqual(LotteryReleaseStatus.enrolling.displayLabel, "报名中")
        XCTAssertTrue(LotteryReleaseStatus.enrolling.allowsEnroll)
        XCTAssertTrue(LotteryReleaseStatus.drawing.isDrawingInProgress)
        XCTAssertFalse(LotteryReleaseStatus.drawn.allowsEnroll)
    }

    func testDedupErrorCodes() {
        XCTAssertEqual(LotteryErrorCode.duplicateIdNo.rawValue, "duplicate_id_no")
        XCTAssertEqual(LotteryErrorCode.duplicateDevice.rawValue, "duplicate_device")
        XCTAssertEqual(LotteryErrorCode.duplicateAddress.rawValue, "duplicate_address")
        XCTAssertEqual(LotteryErrorCode.duplicatePayAccount.rawValue, "duplicate_pay_account")
        XCTAssertTrue(LotteryErrorCode.duplicateIdNo.isDedupConflict)
        XCTAssertEqual(LotteryErrorCode.duplicateIdNo.fallbackMessage, LotteryCopy.duplicateGeneric)
        XCTAssertEqual(LotteryErrorCode.duplicateAddress.fallbackMessage, LotteryCopy.duplicateAddress)
        XCTAssertTrue(LotteryErrorCode.depositNotFrozen.opensDeposit)
        XCTAssertTrue(LotteryErrorCode.realNameRequired.opensRealName)
        XCTAssertTrue(LotteryErrorCode.authRequired.opensLogin)
        XCTAssertEqual(LotteryErrorCode.creditTooLow.fallbackMessage, LotteryCopy.creditTooLow)
        XCTAssertEqual(LotteryErrorCode.drawNotReady.rawValue, "draw_not_ready")
    }

    // MARK: Seed formula (fy-sha256-v1 display helpers)

    func testSeedFormulaConcatOrderAndHex() {
        // seed = SHA-256(entries_hash_hex || UTF-8(external_random)), no separator.
        let hash = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
        let random = "20261105-01-02-03-04-05-06-07"
        let seed = LotteryLogic.computeSeed(entriesHashHex: hash.uppercased(), externalRandom: random)
        XCTAssertEqual(seed.count, 64)
        XCTAssertEqual(seed, seed.lowercased())
        // Uppercase hash input must normalize to lowercase before hash.
        let seed2 = LotteryLogic.computeSeed(entriesHashHex: hash, externalRandom: random)
        XCTAssertEqual(seed, seed2)
        // Changing concat order must change seed.
        let swapped = LotteryLogic.computeSeed(entriesHashHex: random, externalRandom: hash)
        XCTAssertNotEqual(seed, swapped)
        XCTAssertEqual(LotteryLogic.seedPrefix(seed), String(seed.prefix(8)))
        XCTAssertEqual(
            LotteryLogic.previewSeedPrefix(entriesHashHex: hash, externalRandom: random),
            String(seed.prefix(8))
        )
    }

    func testExternalRandomValidation() {
        XCTAssertTrue(LotteryLogic.isValidExternalRandom("期号24001 01 02 03 04 05 06 07"))
        XCTAssertFalse(LotteryLogic.isValidExternalRandom(""))
        XCTAssertFalse(LotteryLogic.isValidExternalRandom(String(repeating: "a", count: 513)))
        XCTAssertFalse(LotteryLogic.isValidExternalRandom("bad\nline"))
        XCTAssertFalse(LotteryLogic.isValidExternalRandom("has\u{0000}null"))
    }

    // MARK: Decode release / entry / proof

    func testDecodeLotteryReleaseDetail() throws {
        let json = """
        {
          "id": 88,
          "title": "GT3 抽签",
          "mode": "lottery",
          "status": "enrolling",
          "enroll_start_at": "2026-11-05T02:00:00Z",
          "enroll_end_at": "2026-11-05T10:00:00Z",
          "draw_at": "2026-11-05T12:00:00Z",
          "quota_n": 10,
          "waitlist_m": 10,
          "pay_window_sec": 7200,
          "deposit_fen": 20000,
          "price_fen": 259900,
          "algorithm_version": "fy-sha256-v1",
          "legal_review_required": true,
          "user_eligibility": {
            "real_named": true,
            "deposit_frozen": false,
            "credit_ok": true,
            "credit_score": 92,
            "vip_level": 1,
            "vip_ok": true,
            "already_entered": false,
            "address_ready": true
          },
          "server_now": "2026-11-05T04:00:00Z"
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(LotteryReleaseDetail.self, from: json)
        XCTAssertEqual(detail.id, 88)
        XCTAssertTrue(detail.isLotteryMode)
        XCTAssertEqual(detail.status, .enrolling)
        XCTAssertEqual(detail.resolvedQuotaN, 10)
        XCTAssertEqual(detail.resolvedWaitlistM, 10)
        XCTAssertEqual(detail.resolvedDepositFen, 20_000)
        XCTAssertEqual(detail.resolvedPayWindowSec, 7_200)
        XCTAssertEqual(detail.resolvedAlgorithmVersion, "fy-sha256-v1")
        XCTAssertEqual(detail.eligibility?.isRealNamed, true)
        XCTAssertEqual(detail.eligibility?.isDepositFrozen, false)
        XCTAssertEqual(detail.eligibility?.isCreditOk, true)
        XCTAssertNotNil(detail.resolvedServerNow)
    }

    func testDecodeNMAliasesAndDepositFallback() throws {
        let json = """
        {
          "id": 1,
          "n": 5,
          "m": 3,
          "exclusive_deposit_fen": 30000,
          "status": "drawn"
        }
        """.data(using: .utf8)!
        let detail = try decoder.decode(LotteryReleaseDetail.self, from: json)
        XCTAssertEqual(detail.resolvedQuotaN, 5)
        XCTAssertEqual(detail.resolvedWaitlistM, 3)
        XCTAssertEqual(detail.resolvedDepositFen, 30_000)
        XCTAssertEqual(detail.status, .drawn)
    }

    func testDecodeEntryAndCreateResult() throws {
        let entryJSON = """
        {
          "id": 501,
          "entry_no": 12,
          "release_id": 88,
          "status": "won",
          "rank": 1,
          "order_id": 9001,
          "pay_deadline": "2026-11-05T14:00:00Z",
          "win_source": "drawn",
          "title": "GT3 抽签",
          "price_fen": 259900
        }
        """.data(using: .utf8)!
        let entry = try decoder.decode(LotteryEntry.self, from: entryJSON)
        XCTAssertEqual(entry.resolvedStatus, .won)
        XCTAssertEqual(entry.winSource, .drawn)
        XCTAssertEqual(entry.orderId, 9001)

        let resultJSON = """
        {
          "entry_id": 501,
          "entry_no": 12,
          "release_id": 88,
          "status": "registered",
          "deposit_id": 77,
          "deposit_status": "frozen",
          "already_entered": false
        }
        """.data(using: .utf8)!
        let result = try decoder.decode(LotteryEntryCreateResult.self, from: resultJSON)
        XCTAssertEqual(result.resolvedEntryId, 501)
        XCTAssertTrue(result.isRegistered)
        XCTAssertFalse(result.needsDepositPayment)
    }

    func testDecodeDrawProofPublicFields() throws {
        let json = """
        {
          "release_id": 88,
          "entries_count": 100,
          "entries_hash": "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
          "algorithm_version": "fy-sha256-v1",
          "external_source": "sporttery_dlt",
          "external_ref": "https://example.com/dlt/24001",
          "external_random": "24001-01-02-03-04-05-06-07",
          "seed": "11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff",
          "n": 10,
          "m": 10,
          "drawn_at": "2026-11-05T12:05:00Z",
          "legal_reviewed": true,
          "winners": [
            { "rank": 1, "nickname": "张*丰", "phone": "138****1234" }
          ],
          "waitlist": [
            { "rank": 11, "nickname_masked": "李*华", "phone_masked": "139****5678" }
          ]
        }
        """.data(using: .utf8)!
        let proof = try decoder.decode(LotteryDrawProof.self, from: json)
        XCTAssertEqual(proof.releaseId, 88)
        XCTAssertEqual(proof.entriesCount, 100)
        XCTAssertEqual(proof.n, 10)
        XCTAssertEqual(proof.m, 10)
        XCTAssertEqual(proof.resolvedAlgorithmVersion, "fy-sha256-v1")
        XCTAssertTrue(proof.isLegalReviewed)
        XCTAssertEqual(proof.winners.count, 1)
        XCTAssertEqual(proof.winners[0].nicknameMasked, "张*丰")
        XCTAssertEqual(proof.waitlist[0].phoneMasked, "139****5678")
        let copied = proof.copyAllFieldsText
        XCTAssertTrue(copied.contains("entries_hash="))
        XCTAssertTrue(copied.contains("seed="))
        XCTAssertTrue(copied.contains("legal_reviewed=true"))
        // Public payload must not invent internal ids.
        XCTAssertFalse(copied.contains("user_id"))
        XCTAssertFalse(copied.contains("entry_id"))
    }

    // MARK: Countdown / CTA / checklist

    func testPayDeadlineCountdownUsesServerNow() {
        let deadline = t0.addingTimeInterval(7_200)
        XCTAssertEqual(LotteryLogic.countdownSeconds(until: deadline, serverNow: t0), 7_200)
        XCTAssertEqual(
            LotteryLogic.countdownSeconds(until: deadline, serverNow: t0.addingTimeInterval(3_600)),
            3_600
        )
        let line = LotteryLogic.payDeadlineCountdownLine(seconds: 65)
        XCTAssertTrue(line.contains(LotteryCopy.serverTimeHint))
        XCTAssertTrue(line.contains("00:01:05"))
        XCTAssertTrue(
            LotteryLogic.isPayRemindWindow(
                now: deadline.addingTimeInterval(-1_000),
                payDeadline: deadline
            )
        )
        XCTAssertFalse(
            LotteryLogic.isPayRemindWindow(
                now: deadline.addingTimeInterval(-3_000),
                payDeadline: deadline
            )
        )
        XCTAssertTrue(LotteryLogic.isPayOverdue(now: deadline.addingTimeInterval(1), payDeadline: deadline))
    }

    func testEnrollChecklistAndCTA() {
        let eligibility = LotteryEligibility(
            realNamed: true,
            depositFrozen: false,
            creditOk: true,
            addressReady: true
        )
        let items = LotteryLogic.enrollChecklist(
            isLoggedIn: true,
            eligibility: eligibility,
            hasAddress: true
        )
        XCTAssertEqual(items.map(\.step), [.login, .realName, .credit, .deposit, .address])
        XCTAssertEqual(items.map(\.done), [true, true, true, false, true])
        XCTAssertEqual(
            LotteryLogic.nextEnrollStep(isLoggedIn: true, eligibility: eligibility, hasAddress: true),
            .deposit
        )

        let detail = LotteryReleaseDetail(
            id: 1,
            mode: "lottery",
            status: .enrolling,
            enrollStartAt: t0.addingTimeInterval(-3_600),
            enrollEndAt: t0.addingTimeInterval(3_600),
            eligibility: eligibility
        )
        XCTAssertEqual(
            LotteryLogic.resolveReleaseCTA(
                detail: detail,
                serverNow: t0,
                isLoggedIn: true,
                hasAddress: true
            ),
            .completeEligibility
        )

        let ready = LotteryReleaseDetail(
            id: 1,
            mode: "lottery",
            status: .enrolling,
            enrollStartAt: t0.addingTimeInterval(-3_600),
            enrollEndAt: t0.addingTimeInterval(3_600),
            eligibility: LotteryEligibility(
                realNamed: true,
                depositFrozen: true,
                creditOk: true,
                addressReady: true
            )
        )
        XCTAssertEqual(
            LotteryLogic.resolveReleaseCTA(
                detail: ready,
                serverNow: t0,
                isLoggedIn: true,
                hasAddress: true
            ),
            .enroll
        )
        XCTAssertEqual(
            LotteryLogic.resolveReleaseCTA(
                detail: ready,
                serverNow: t0,
                isLoggedIn: false,
                hasAddress: false
            ),
            .login
        )
    }

    func testEntryCTAsWonWaitlistLostForfeited() {
        let won = LotteryEntry(
            id: 1,
            status: .won,
            orderId: 9,
            payDeadline: t0.addingTimeInterval(3_600)
        )
        XCTAssertEqual(
            LotteryLogic.resolveEntryCTA(entry: won, serverNow: t0),
            .pay
        )
        XCTAssertEqual(LotteryCTA.pay.buttonTitle, LotteryCopy.payCTA)
        XCTAssertNotEqual(LotteryCTA.pay.buttonTitle, "立即购买")

        let waitlisted = LotteryEntry(id: 2, status: .waitlisted, rank: 3, remainingUnpaidWon: 2)
        XCTAssertEqual(LotteryLogic.resolveEntryCTA(entry: waitlisted), .waitlist)
        XCTAssertEqual(
            LotteryLogic.waitlistPositionLine(rank: 3, remainingUnpaid: 2),
            "当前候补位 3 · 剩余中签未付 2"
        )

        XCTAssertEqual(
            LotteryLogic.resolveEntryCTA(entry: LotteryEntry(id: 3, status: .lost)),
            .lost
        )
        XCTAssertEqual(
            LotteryLogic.resolveEntryCTA(entry: LotteryEntry(id: 4, status: .forfeited)),
            .forfeited
        )
        XCTAssertEqual(
            LotteryLogic.resolveEntryCTA(entry: LotteryEntry(id: 5, status: .paid)),
            .paid
        )

        let overdue = LotteryEntry(
            id: 6,
            status: .won,
            payDeadline: t0.addingTimeInterval(-10)
        )
        XCTAssertEqual(
            LotteryLogic.resolveEntryCTA(entry: overdue, serverNow: t0),
            .forfeited
        )
    }

    func testEnrollOpenBoundaryInclusiveEnd() {
        let detail = LotteryReleaseDetail(
            id: 1,
            status: .enrolling,
            enrollStartAt: t0,
            enrollEndAt: t0.addingTimeInterval(3_600)
        )
        XCTAssertTrue(LotteryLogic.isEnrollOpen(detail, serverNow: t0))
        XCTAssertTrue(LotteryLogic.isEnrollOpen(detail, serverNow: t0.addingTimeInterval(3_600)))
        XCTAssertFalse(LotteryLogic.isEnrollOpen(detail, serverNow: t0.addingTimeInterval(3_601)))
        XCTAssertFalse(LotteryLogic.isEnrollOpen(detail, serverNow: t0.addingTimeInterval(-1)))
    }

    func testDeviceAttestationHelper() {
        let ok = LotteryLogic.deviceAttestation(vendorId: " E621E1F8-C36C-495A-93FC-0C247A3E6E5F ")
        XCTAssertEqual(ok.platform, "ios")
        XCTAssertFalse(ok.isEmptyDevice)
        let empty = LotteryLogic.deviceAttestation(vendorId: nil)
        XCTAssertTrue(empty.isEmptyDevice)
        XCTAssertEqual(empty.empty, true)
    }

    func testReproduceGuideCopy() {
        XCTAssertEqual(LotteryCopy.reproduceGuide, "复现说明")
        XCTAssertEqual(LotteryCopy.reproduceSteps.count, 4)
        XCTAssertTrue(LotteryCopy.reproduceSteps[2].contains("entries_hash_hex"))
        XCTAssertTrue(LotteryCopy.reproduceSteps[3].contains("fy-sha256-v1"))
        XCTAssertEqual(LotteryCopy.legalReviewedBadge, "本场已经法务审阅")
    }
}
