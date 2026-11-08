import XCTest
@testable import VeloraCore

final class EvidenceModelsTests: XCTestCase {
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
        XCTAssertEqual(EvidenceConfigDefaults.inspectVideoRequiredSellerTypes, ["proxy_agent", "brand"])
        XCTAssertEqual(EvidenceConfigDefaults.inspectVideoMinAmountFen, 200_000)
        XCTAssertEqual(EvidenceConfigDefaults.unboxVideoMode, "guided")
        XCTAssertEqual(EvidenceConfigDefaults.shipPhotosMinCount, 5)
        XCTAssertEqual(EvidenceConfigDefaults.unboxPhotosMinCount, 3)
        XCTAssertEqual(EvidenceConfigDefaults.unboxPhotosMaxCount, 9)
        XCTAssertEqual(EvidenceConfigDefaults.photoMaxBytes, 10_485_760)
        XCTAssertEqual(EvidenceConfigDefaults.videoMinDurationMs, 3_000)
        XCTAssertEqual(EvidenceConfigDefaults.videoMaxDurationMs, 300_000)
        XCTAssertEqual(EvidenceConfigDefaults.videoMaxBytes, 524_288_000)
        XCTAssertEqual(EvidenceConfigDefaults.photoRetentionDaysAfterComplete, 180)
        XCTAssertEqual(EvidenceConfigDefaults.videoRetentionDaysAfterCaseClosed, 60)
        XCTAssertEqual(EvidenceConfigDefaults.sessionTTLSeconds, 900)
        XCTAssertEqual(EvidenceConfigDefaults.photoMinLuma, 80)
        XCTAssertEqual(EvidenceConfigDefaults.videoPartSizeBytes, 5_242_880)
        XCTAssertEqual(EvidenceConfigDefaults.photoSourceAppCamera, "app_camera")
        XCTAssertEqual(EvidencePhotoSlot.shipRequired.count, 5)
        XCTAssertEqual(EvidencePhotoSlot.shipRequired.map(\.rawValue), [
            "front", "back", "left", "right", "box_bottom",
        ])
    }

    // MARK: B-16 inspect gate

    func testProxyAgentAlwaysRequiresInspectVideo() {
        XCTAssertTrue(EvidenceLogic.inspectVideoRequired(sellerType: "proxy_agent", amountFen: 1))
        XCTAssertTrue(EvidenceLogic.inspectVideoRequired(sellerType: "brand", amountFen: 1))
    }

    func testPersonalAt2000RequiresInspect() {
        XCTAssertTrue(EvidenceLogic.inspectVideoRequired(sellerType: "personal", amountFen: 200_000))
        XCTAssertFalse(EvidenceLogic.inspectVideoRequired(sellerType: "personal", amountFen: 199_999))
    }

    func testFeatureFlagDisablesInspectRequirement() {
        XCTAssertFalse(
            EvidenceLogic.inspectVideoRequired(
                sellerType: "brand",
                amountFen: 1_000_000,
                featureEnabled: false
            )
        )
    }

    func testSnapshotFrozenForDisputeHint() {
        let snap = EvidenceLogic.snapshot(sellerType: "personal", amountFen: 200_000, configVersion: "v1")
        XCTAssertTrue(snap.required)
        XCTAssertEqual(snap.amount, 200_000)
        XCTAssertEqual(snap.configVersion, "v1")
    }

    // MARK: Video duration / hash (AFS-03 / T-10)

    func testVideoDurationBoundaries() {
        XCTAssertEqual(EvidenceLogic.validateVideoDuration(2_900), .videoTooShort)
        XCTAssertEqual(EvidenceLogic.validateVideoDuration(3_000), .videoTooShort) // exclusive min (3000, 300000]
        XCTAssertNil(EvidenceLogic.validateVideoDuration(3_001))
        XCTAssertNil(EvidenceLogic.validateVideoDuration(300_000))
        XCTAssertEqual(EvidenceLogic.validateVideoDuration(300_001), .videoTooLong)
    }

    func testSha256NormalizeLowercasesAndRejectsBad() {
        let upper = String(repeating: "A", count: 64)
        XCTAssertEqual(EvidenceHasher.normalizeSha256(upper), String(repeating: "a", count: 64))
        XCTAssertNil(EvidenceHasher.normalizeSha256("deadbeef"))
        XCTAssertNil(EvidenceHasher.normalizeSha256(String(repeating: "g", count: 64)))
        XCTAssertEqual(EvidenceLogic.validateSha256("not-a-hash"), .sha256Invalid)
    }

    func testStreamingSha256MatchesInMemory() throws {
        let payload = Data((0..<4_096).map { UInt8($0 % 251) })
        let mem = EvidenceHasher.sha256Hex(payload)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("clip.bin")
        try payload.write(to: file)
        var progressHits = 0
        let streamed = try EvidenceHasher.sha256Hex(ofFileAt: file, chunkSize: 1_024) { _ in progressHits += 1 }
        XCTAssertEqual(mem, streamed)
        XCTAssertGreaterThan(progressHits, 0)
        XCTAssertEqual(mem.count, 64)
    }

    // MARK: CanShip gate

    func testCanShipRequiresFiveSlots() {
        XCTAssertEqual(
            EvidenceLogic.canShip(photosFilled: 4, inspectRequired: false, shipVideoRegistered: false),
            .evidencePhotosIncomplete
        )
        XCTAssertNil(
            EvidenceLogic.canShip(photosFilled: 5, inspectRequired: false, shipVideoRegistered: false)
        )
    }

    func testCanShipRequiresInspectFingerprint() {
        XCTAssertEqual(
            EvidenceLogic.canShip(photosFilled: 5, inspectRequired: true, shipVideoRegistered: false),
            .inspectVideoRequired
        )
        XCTAssertNil(
            EvidenceLogic.canShip(photosFilled: 5, inspectRequired: true, shipVideoRegistered: true)
        )
    }

    func testCanShipBlocksWhileHashing() {
        XCTAssertEqual(
            EvidenceLogic.canShip(
                photosFilled: 5,
                inspectRequired: false,
                shipVideoRegistered: false,
                hashingInProgress: true
            ),
            .hashingInProgress
        )
    }

    func testCanShipFromOrderEvidenceState() {
        var slots = EvidenceLogic.emptyShipSlots()
        for i in 0..<5 {
            slots[i] = EvidenceSlotProgress(slot: slots[i].slot, filled: true, evidenceId: Int64(i + 1), verified: true)
        }
        let incomplete = OrderEvidenceState(orderId: 1, inspectVideoRequired: true, shipPhotoSlots: slots, shipVideo: .missing)
        XCTAssertEqual(EvidenceLogic.canShip(state: incomplete), .inspectVideoRequired)

        let ready = OrderEvidenceState(orderId: 1, inspectVideoRequired: true, shipPhotoSlots: slots, shipVideo: .registered)
        XCTAssertNil(EvidenceLogic.canShip(state: ready))
        XCTAssertTrue(ready.shipPhotosComplete)
    }

    func testAppearanceAfterSaleNeedsThreeUnboxPhotos() {
        XCTAssertEqual(EvidenceLogic.canOpenAppearanceAfterSale(unboxPhotoCount: 2), .evidencePhotosIncomplete)
        XCTAssertNil(EvidenceLogic.canOpenAppearanceAfterSale(unboxPhotoCount: 3))
    }

    // MARK: Draft / session / slots

    func testDraftPhaseTransitions() {
        XCTAssertTrue(EvidenceDraftPhase.idle.canTransition(to: .sessionOpen))
        XCTAssertTrue(EvidenceDraftPhase.recordingVideo.canTransition(to: .hashing))
        XCTAssertTrue(EvidenceDraftPhase.hashing.canTransition(to: .fingerprintSubmitted))
        XCTAssertFalse(EvidenceDraftPhase.idle.canTransition(to: .readyToShip))
        var draft = EvidenceDraft()
        XCTAssertTrue(EvidenceLogic.advanceDraft(&draft, to: .sessionOpen))
        XCTAssertEqual(draft.phase, .sessionOpen)
        XCTAssertFalse(EvidenceLogic.advanceDraft(&draft, to: .fingerprintSubmitted))
    }

    func testRecomputeReadyPhase() {
        XCTAssertEqual(
            EvidenceLogic.recomputeReadyPhase(photosComplete: true, inspectRequired: false, fingerprintDone: false),
            .readyToShip
        )
        XCTAssertEqual(
            EvidenceLogic.recomputeReadyPhase(photosComplete: true, inspectRequired: true, fingerprintDone: false),
            .sessionOpen
        )
        XCTAssertEqual(
            EvidenceLogic.recomputeReadyPhase(photosComplete: true, inspectRequired: true, fingerprintDone: true),
            .readyToShip
        )
    }

    func testCaptureTokenStableAndPhotoIdempotencyKey() {
        let a = EvidenceLogic.captureToken(nonce: "n1", frameSeq: 1)
        let b = EvidenceLogic.captureToken(nonce: "n1", frameSeq: 1)
        let c = EvidenceLogic.captureToken(nonce: "n1", frameSeq: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.count, 64)
        XCTAssertEqual(EvidenceLogic.photoIdempotencyKey(sessionId: "s", slot: "front"), "photo:s:front")
    }

    func testVideoUploadStatusMachine() {
        XCTAssertTrue(EvidenceVideoUploadStatus.initiated.canTransition(to: .uploading))
        XCTAssertTrue(EvidenceVideoUploadStatus.hashing.canTransition(to: .matched))
        XCTAssertTrue(EvidenceVideoUploadStatus.hashing.canTransition(to: .mismatch))
        XCTAssertFalse(EvidenceVideoUploadStatus.ready.canTransition(to: .uploading))
        XCTAssertTrue(EvidenceVideoUploadStatus.mismatch.canTransition(to: .initiated))
    }

    // MARK: Decode fixtures

    func testDecodeCaptureSession() throws {
        let json = """
        {
          "session_id": "sess-1",
          "order_id": 42,
          "kind_group": "ship",
          "nonce": "abc",
          "watermark_text": "P2024 2024-01-01T00:00:00Z",
          "server_time": "2024-01-01T00:00:00Z",
          "expires_at": "2024-01-01T00:15:00Z",
          "slots": ["front","back","left","right","box_bottom"],
          "inspect_video_required": true,
          "status": "open"
        }
        """.data(using: .utf8)!
        let session = try decoder.decode(EvidenceCaptureSession.self, from: json)
        XCTAssertEqual(session.sessionId, "sess-1")
        XCTAssertEqual(session.kindGroup, .ship)
        XCTAssertTrue(session.inspectVideoRequired)
        XCTAssertEqual(session.slots.count, 5)
        XCTAssertEqual(session.status, .open)
    }

    func testDecodeOrderEvidenceStateAndFingerprintResult() throws {
        let json = """
        {
          "order_id": 9,
          "kind_group": "ship",
          "inspect_video_required": false,
          "ship_photo_slots": [
            {"slot":"front","filled":true,"evidence_id":1,"verified":true},
            {"slot":"back","filled":true,"evidence_id":2,"verified":true},
            {"slot":"left","filled":false},
            {"slot":"right","filled":false},
            {"slot":"box_bottom","filled":false}
          ],
          "ship_video": "missing",
          "evidence_ready": false,
          "ship_frozen": false
        }
        """.data(using: .utf8)!
        let state = try decoder.decode(OrderEvidenceState.self, from: json)
        XCTAssertEqual(state.orderId, 9)
        XCTAssertEqual(state.shipPhotosFilledCount, 2)
        XCTAssertFalse(state.shipPhotosComplete)
        XCTAssertEqual(state.shipVideo, .missing)

        let fpJSON = """
        {"id":7,"kind":"ship_video","sha256":"\(String(repeating: "ab", count: 32))","duration_ms":12000,"byte_size":1024}
        """.data(using: .utf8)!
        let fp = try decoder.decode(EvidenceVideoFingerprintResult.self, from: fpJSON)
        XCTAssertEqual(fp.kind, .shipVideo)
        XCTAssertEqual(fp.durationMs, 12_000)
    }

    func testDecodeEvidenceSummaryAndErrorNormalize() throws {
        let json = """
        {
          "inspect_required": true,
          "ship_video": "registered_not_uploaded",
          "unbox_skipped": true,
          "ship_photos_complete": true,
          "evidence_ready": false
        }
        """.data(using: .utf8)!
        let summary = try decoder.decode(EvidenceSummary.self, from: json)
        XCTAssertTrue(summary.inspectRequired)
        XCTAssertEqual(summary.shipVideo, .registeredNotUploaded)
        XCTAssertEqual(summary.unboxSkipped, true)

        XCTAssertEqual(EvidenceErrorCode.normalize("inspect_video_required"), .inspectVideoRequired)
        XCTAssertEqual(EvidenceErrorCode.normalize("photos_incomplete"), .evidencePhotosIncomplete)
        XCTAssertEqual(EvidenceErrorCode.inspectVideoRequired.fallbackMessage, EvidenceCopy.inspectVideoRequired)
    }

    func testWatermarkAndClockSkew() {
        let server = Date(timeIntervalSince1970: 1_700_000_000)
        let text = EvidenceLogic.buildWatermarkText(orderNo: "P1", serverTime: server)
        XCTAssertTrue(text.hasPrefix("P1 "))
        XCTAssertTrue(EvidenceLogic.shouldWarnClockSkew(localNow: server.addingTimeInterval(6), serverTime: server))
        XCTAssertFalse(EvidenceLogic.shouldWarnClockSkew(localNow: server.addingTimeInterval(2), serverTime: server))
    }

    func testLocalStoragePathAndPartCount() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let url = try EvidenceStorage.videoURL(orderId: 99, kind: .shipVideo, base: base)
        XCTAssertTrue(url.path.contains("Evidence/99"))
        XCTAssertTrue(url.lastPathComponent == EvidenceConfigDefaults.shipVideoFileName)
        XCTAssertEqual(EvidenceLogic.partCount(totalBytes: 5_242_880), 1)
        XCTAssertEqual(EvidenceLogic.partCount(totalBytes: 5_242_881), 2)
        XCTAssertEqual(EvidenceLogic.validateShipPhotoSlot("front"), nil)
        XCTAssertEqual(EvidenceLogic.validateShipPhotoSlot("top"), .slotInvalid)
        XCTAssertEqual(EvidenceLogic.validateUnboxPhotoSlot("issue_3"), nil)
        XCTAssertEqual(EvidenceLogic.validateUnboxPhotoSlot("issue_99"), .slotInvalid)
    }

    func testSlotDisplayLabelsForVoiceOver() {
        XCTAssertEqual(EvidencePhotoSlot.front.displayLabel, "正面")
        XCTAssertEqual(EvidencePhotoSlot.boxBottom.displayLabel, "盒底")
        XCTAssertEqual(EvidenceLogic.slotProgressLabel(filled: 3), "3/5")
    }
}
