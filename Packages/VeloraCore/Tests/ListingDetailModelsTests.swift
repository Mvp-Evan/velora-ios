import XCTest
@testable import VeloraCore

final class ListingDetailModelsTests: XCTestCase {
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

    func testConditionNormalizeAndLabels() {
        XCTAssertEqual(ListingConditionGrade.normalize("new_sealed"), .newSealed)
        XCTAssertEqual(ListingConditionGrade.normalize("全新未拆"), .newSealed)
        XCTAssertEqual(ListingConditionGrade.normalize("99新"), .unpackedMint)
        XCTAssertEqual(ListingConditionGrade.normalize("有瑕疵"), .flawed)
        XCTAssertEqual(ListingConditionGrade.displayLabel("flawed"), "有瑕疵")
        XCTAssertEqual(ListingConditionGrade.flawed.label, "有瑕疵")
    }

    func testReserveCopyThreeStates() {
        XCTAssertEqual(ListingReserveCopy.text(hasReserve: false, reserveMet: false), "无保留价")
        XCTAssertEqual(ListingReserveCopy.text(hasReserve: true, reserveMet: false), "有保留价")
        XCTAssertEqual(ListingReserveCopy.text(hasReserve: true, reserveMet: true), "已达保留价")
        XCTAssertNil(ListingReserveCopy.text(hasReserve: nil, reserveMet: nil))
    }

    func testQAContactGuard() {
        XCTAssertTrue(ListingQAContactGuard.containsContactInfo("加微 vx_alice88"))
        XCTAssertTrue(ListingQAContactGuard.containsContactInfo("V信: hello_world"))
        XCTAssertTrue(ListingQAContactGuard.containsContactInfo("QQ: 12345678"))
        XCTAssertTrue(ListingQAContactGuard.containsContactInfo("详见 https://evil.example/x"))
        XCTAssertTrue(ListingQAContactGuard.containsContactInfo("13812345678"))
        XCTAssertFalse(ListingQAContactGuard.containsContactInfo("成色怎么样？有无配件"))
        XCTAssertFalse(ListingQAContactGuard.containsContactInfo("128000"))
    }

    func testQAValidatorLimits() {
        XCTAssertEqual(ListingQAValidator.validateQuestion("成色如何", alreadyAsked: 5), .questionLimitExceeded)
        XCTAssertEqual(
            ListingQAValidator.validateQuestion(String(repeating: "问", count: 201), alreadyAsked: 0),
            .questionLimitExceeded
        )
        XCTAssertEqual(ListingQAValidator.validateQuestion("微信 wxid_abc12", alreadyAsked: 0), .contactInfoForbidden)
        XCTAssertNil(ListingQAValidator.validateQuestion("底盘清晰吗", alreadyAsked: 2))
    }

    func testWatermarkLine() {
        let date = Date(timeIntervalSince1970: 1_730_764_800) // 2024-11-05 UTC ≈ CST day
        let line = ListingWatermark.line(shortCode: "00AB", date: date, shooterIdSuffix: "0042")
        XCTAssertTrue(line.contains(ListingDetailLimits.watermarkBrand))
        XCTAssertTrue(line.contains("00AB"))
        XCTAssertTrue(line.contains("0042"))
        XCTAssertEqual(ListingWatermark.shortCode(listingId: 0x12AB), "12AB")
        XCTAssertEqual(ListingWatermark.idSuffix(10042), "0042")
    }

    func testPhotoRequestProgressText() {
        let row = PhotoRequestRow(id: 1, listingId: 9, part: .chassis, count: 3)
        XCTAssertEqual(row.progressText, "3 人想看底盘")
    }

    func testDecodeLegacyImagesAsStrings() throws {
        let json = """
        {
          "id": 42,
          "seller_id": 7,
          "trade_type": "auction",
          "title": "Spark GR010",
          "condition": "99新",
          "images": ["https://cdn.example/a.jpg", "https://cdn.example/b.jpg"],
          "price": 45000,
          "stock": 1,
          "status": "live",
          "version": 1,
          "negotiable": false,
          "has_reserve": true,
          "reserve_met": false,
          "lot": { "id": 10 }
        }
        """.data(using: .utf8)!
        let detail = try decoder.decode(ListingDetail.self, from: json)
        XCTAssertEqual(detail.id, 42)
        XCTAssertEqual(detail.template, .auction)
        XCTAssertEqual(detail.conditionGrade, .unpackedMint)
        XCTAssertEqual(detail.galleryURLs.count, 2)
        XCTAssertEqual(detail.lotId, 10)
        XCTAssertEqual(ListingReserveCopy.text(hasReserve: detail.hasReserve, reserveMet: detail.reserveMet), "有保留价")
        XCTAssertFalse(detail.showsFlawSection)
    }

    func testDecodeD10FieldsAndFlawSection() throws {
        let json = """
        {
          "id": 8,
          "seller_id": 3,
          "trade_type": "fixed",
          "title": "有瑕样例",
          "condition": "flawed",
          "images": [
            {"id": 1, "url": "https://cdn.example/c.jpg", "role": "cover", "immutable": true, "watermarked": false, "sort_order": 0},
            {"id": 2, "url": "https://cdn.example/s.jpg", "role": "supplement", "immutable": false, "watermarked": true, "sort_order": 1}
          ],
          "flaw_desc": "右侧车门细微划痕，不影响展示。",
          "flaw_images": [
            {"id": 9, "url": "https://cdn.example/f.jpg", "role": "flaw", "immutable": false, "watermarked": false}
          ],
          "price": 88000,
          "stock": 1,
          "status": "on_sale",
          "version": 2,
          "negotiable": true,
          "sold_count": 0,
          "qa_locked": false,
          "condition_incomplete": false,
          "rules_snapshot": {
            "deposit_rule": "",
            "pay_deadline_hours": 24,
            "ship_deadline_hours": 72,
            "after_sale_hours": 48,
            "fee_note": "买家无佣金"
          },
          "questions": [
            {
              "id": 1,
              "listing_id": 8,
              "asker_id": 99,
              "content": "能议价吗",
              "answer": "可以小刀",
              "status": "visible",
              "version": 1,
              "created_at": "2026-11-01T12:00:00Z"
            }
          ],
          "photo_requests": [
            {"id": 5, "listing_id": 8, "part": "side", "status": "open", "count": 2}
          ]
        }
        """.data(using: .utf8)!
        let detail = try decoder.decode(ListingDetail.self, from: json)
        XCTAssertEqual(detail.template, .direct)
        XCTAssertEqual(detail.conditionGrade, .flawed)
        XCTAssertTrue(detail.showsFlawSection)
        XCTAssertEqual(detail.flawImageURLs.count, 1)
        XCTAssertEqual(detail.galleryURLs.count, 2)
        XCTAssertEqual(detail.questions.first?.content, "能议价吗")
        XCTAssertEqual(detail.photoRequests.first?.part, .side)
        XCTAssertEqual(detail.rulesSnapshot?.payDeadlineHours, 24)
        XCTAssertEqual(detail.rulesSnapshot?.summaryLines.contains("拍中后 24 小时内付款"), true)
    }

    func testConditionIncompleteBlocksPurchase() throws {
        let json = """
        {
          "id": 1,
          "trade_type": "fixed",
          "title": "脏数据",
          "condition": "flawed",
          "images": [],
          "price": 1,
          "stock": 1,
          "status": "on_sale",
          "condition_incomplete": true
        }
        """.data(using: .utf8)!
        let detail = try decoder.decode(ListingDetail.self, from: json)
        XCTAssertTrue(detail.conditionIncomplete)
        XCTAssertFalse(detail.canPurchase)
    }

    func testBuyerSchemaForbidsReservePriceKey() throws {
        let json = """
        {
          "id": 1,
          "trade_type": "auction",
          "title": "x",
          "condition": "new_sealed",
          "images": [],
          "price": 100,
          "stock": 1,
          "status": "live",
          "has_reserve": true,
          "reserve_met": false
        }
        """.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: json)
        XCTAssertTrue(ListingDetailBuyerSchema.leakedKeys(in: obj).isEmpty)

        let leak = """
        {"id":1,"reserve_price":99900,"cost_price":100,"phone":"13800000000"}
        """.data(using: .utf8)!
        let leakObj = try JSONSerialization.jsonObject(with: leak)
        let keys = ListingDetailBuyerSchema.leakedKeys(in: leakObj)
        XCTAssertTrue(keys.contains("reserve_price"))
        XCTAssertTrue(keys.contains("cost_price"))
        XCTAssertTrue(keys.contains("phone"))
    }

    func testTradeTypeTemplates() {
        XCTAssertEqual(ListingTradeType.auction.detailTemplate, .auction)
        XCTAssertEqual(ListingTradeType.fixed.detailTemplate, .direct)
        XCTAssertEqual(ListingTradeType.release.detailTemplate, .release)
    }

    func testErrorFallbackMessages() {
        XCTAssertEqual(ListingDetailErrorCode.qaLocked.fallbackMessage, "已结束，问答已关闭")
        XCTAssertEqual(ListingDetailErrorCode.cameraRequired.fallbackMessage, "补图请使用 App 内相机拍摄")
        XCTAssertEqual(ListingDetailErrorCode.contactInfoForbidden.fallbackMessage, "含联系方式")
    }
}
