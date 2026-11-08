import Foundation
import SwiftUI
import AVFoundation

/// Ship / unbox evidence session orchestration (DES-v1.3-09-01 §5.10).
@MainActor
final class EvidenceCaptureModel: ObservableObject {
    let orderId: Int64
    let orderNo: String
    let kindGroup: EvidenceKindGroup
    let amountFen: Int64
    let sellerType: String?

    @Published var draft = EvidenceDraft()
    @Published var state: OrderEvidenceState?
    @Published var slots: [EvidenceSlotProgress] = EvidenceLogic.emptyShipSlots()
    @Published var working = false
    @Published var hashing = false
    @Published var hashProgress: Double = 0
    @Published var errorMessage: String?
    @Published var clockSkewHint = false
    @Published var activeSlot: EvidencePhotoSlot?
    @Published var showCamera = false
    @Published var showVideoRecorder = false
    @Published var localVideoMissing = false

    private var frameSeq = 0

    init(
        orderId: Int64,
        orderNo: String,
        kindGroup: EvidenceKindGroup = .ship,
        amountFen: Int64 = 0,
        sellerType: String? = nil
    ) {
        self.orderId = orderId
        self.orderNo = orderNo
        self.kindGroup = kindGroup
        self.amountFen = amountFen
        self.sellerType = sellerType
    }

    var filledCount: Int { slots.filter(\.filled).count }
    var progressLabel: String { EvidenceLogic.slotProgressLabel(filled: filledCount) }

    var inspectRequired: Bool {
        if let s = draft.session { return s.inspectVideoRequired }
        if let st = state { return st.inspectVideoRequired }
        return EvidenceLogic.inspectVideoRequired(sellerType: sellerType, amountFen: amountFen)
    }

    var shipVideoRegistered: Bool {
        switch state?.shipVideo {
        case .registered, .registeredNotUploaded, .verified: return true
        default: return draft.phase == .fingerprintSubmitted || draft.phase == .readyToShip
        }
    }

    var canFinish: Bool {
        EvidenceLogic.canShip(
            photosFilled: filledCount,
            inspectRequired: inspectRequired,
            shipVideoRegistered: shipVideoRegistered,
            hashingInProgress: hashing
        ) == nil
    }

    var watermarkText: String {
        draft.session?.watermarkText
            ?? EvidenceLogic.buildWatermarkText(orderNo: orderNo, serverTime: Date())
    }

    var sessionRemaining: Int {
        draft.session?.remainingSeconds ?? 0
    }

    func load() async {
        working = true
        defer { working = false }
        do {
            let remote = try await API.orderEvidence(orderId)
            state = remote
            slots = EvidenceLogic.mergeServerSlots(remote.shipPhotoSlots)
            if let open = remote.openSession, !open.isExpired {
                draft.session = open
                draft.phase = .sessionOpen
                clockSkewHint = EvidenceLogic.shouldWarnClockSkew(localNow: Date(), serverTime: open.serverTime)
            }
            refreshPhase()
            if inspectRequired {
                localVideoMissing = !EvidenceStorage.localVideoExists(orderId: orderId, kind: .shipVideo)
                    && shipVideoRegistered
            }
        } catch {
            // Cold start: open session even if GET fails (server may not be ready in CI).
            errorMessage = (error as? APIError)?.message
        }
    }

    func ensureSession() async -> Bool {
        if let s = draft.session, !s.isExpired { return true }
        working = true
        defer { working = false }
        do {
            let session = try await API.openEvidenceSession(
                orderId: orderId,
                kindGroup: kindGroup,
                idempotencyKey: "evidence-session-\(orderId)-\(kindGroup.rawValue)-\(UUID().uuidString)"
            )
            draft.session = session
            draft.phase = .sessionOpen
            clockSkewHint = EvidenceLogic.shouldWarnClockSkew(localNow: Date(), serverTime: session.serverTime)
            errorMessage = nil
            return true
        } catch {
            present(error)
            return false
        }
    }

    func startPhoto(slot: EvidencePhotoSlot) {
        Task {
            guard await ensureSession() else { return }
            activeSlot = slot
            _ = EvidenceLogic.advanceDraft(&draft, to: .capturingPhoto)
            showCamera = true
        }
    }

    func handleCapturedJPEG(_ data: Data) async {
        guard let slot = activeSlot, let session = draft.session else { return }
        showCamera = false
        if let err = EvidenceLogic.validatePhotoByteSize(data.count) {
            errorMessage = err.fallbackMessage
            return
        }
        working = true
        defer { working = false }
        frameSeq += 1
        draft.frameSeq = frameSeq
        let token = EvidenceLogic.captureToken(nonce: session.nonce, frameSeq: frameSeq)
        do {
            let result = try await API.uploadEvidencePhoto(
                orderId: orderId,
                sessionId: session.sessionId,
                slot: slot.rawValue,
                jpegData: data,
                captureToken: token,
                deviceId: DeviceID.current
            )
            if let idx = slots.firstIndex(where: { $0.slot == slot.rawValue }) {
                slots[idx] = EvidenceSlotProgress(
                    slot: slot.rawValue,
                    filled: true,
                    evidenceId: result.id,
                    verified: result.verified
                )
            }
            draft.filledSlots.insert(slot.rawValue)
            refreshPhase()
            await reloadQuiet()
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func startVideo() {
        Task {
            guard await ensureSession() else { return }
            _ = EvidenceLogic.advanceDraft(&draft, to: .recordingVideo)
            showVideoRecorder = true
        }
    }

    /// After one-shot record: hash sandbox file → submit fingerprint.
    func handleRecordedVideo(tempURL: URL, durationMs: Int64) async {
        showVideoRecorder = false
        guard let session = draft.session else { return }

        // Prefer container duration over wall-clock (design §5.3 / T-10).
        let asset = AVURLAsset(url: tempURL)
        let assetMs: Int64
        if let t = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(t)
            assetMs = seconds.isFinite ? Int64((seconds * 1000).rounded()) : durationMs
        } else {
            assetMs = durationMs
        }

        if let err = EvidenceLogic.validateVideoDuration(assetMs) {
            errorMessage = err.fallbackMessage
            _ = EvidenceLogic.advanceDraft(&draft, to: .sessionOpen)
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        do {
            let dest = try EvidenceStorage.videoURL(
                orderId: orderId,
                kind: kindGroup == .ship ? .shipVideo : .unboxVideo
            )
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: tempURL, to: dest)
            try? FileManager.default.removeItem(at: tempURL)

            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let byteSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if let err = EvidenceLogic.validateVideoByteSize(byteSize) {
                errorMessage = err.fallbackMessage
                return
            }

            hashing = true
            hashProgress = 0
            _ = EvidenceLogic.advanceDraft(&draft, to: .hashing)
            defer {
                hashing = false
                hashProgress = 0
            }

            let destURL = dest
            let sha = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let hex = try EvidenceHasher.sha256Hex(ofFileAt: destURL) { p in
                            DispatchQueue.main.async { self.hashProgress = p }
                        }
                        cont.resume(returning: hex)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }

            guard let normalized = EvidenceHasher.normalizeSha256(sha) else {
                errorMessage = EvidenceErrorCode.sha256Invalid.fallbackMessage
                _ = EvidenceLogic.advanceDraft(&draft, to: .recordingVideo)
                return
            }

            let kind: EvidenceKind = kindGroup == .ship ? .shipVideo : .unboxVideo
            let req = EvidenceVideoFingerprintRequest(
                sessionId: session.sessionId,
                kind: kind,
                sha256: normalized,
                durationMs: assetMs,
                byteSize: byteSize,
                deviceId: DeviceID.current
            )
            _ = try await API.submitEvidenceVideoFingerprint(orderId: orderId, request: req)
            draft.pendingSha256 = normalized
            draft.pendingDurationMs = assetMs
            draft.localVideoURL = dest
            _ = EvidenceLogic.advanceDraft(&draft, to: .fingerprintSubmitted)
            localVideoMissing = false
            await reloadQuiet()
            refreshPhase()
            errorMessage = nil
        } catch {
            present(error)
            _ = EvidenceLogic.advanceDraft(&draft, to: .sessionOpen)
        }
    }

    func videoInterrupted() {
        showVideoRecorder = false
        errorMessage = EvidenceCopy.interruptRerecord
        _ = EvidenceLogic.advanceDraft(&draft, to: .sessionOpen)
    }

    private func reloadQuiet() async {
        if let remote = try? await API.orderEvidence(orderId) {
            state = remote
            slots = EvidenceLogic.mergeServerSlots(remote.shipPhotoSlots)
        }
    }

    private func refreshPhase() {
        let phase = EvidenceLogic.recomputeReadyPhase(
            photosComplete: filledCount >= EvidenceConfigDefaults.shipPhotosMinCount,
            inspectRequired: inspectRequired,
            fingerprintDone: shipVideoRegistered
        )
        if draft.phase != .hashing && draft.phase != .recordingVideo && draft.phase != .capturingPhoto {
            draft.phase = phase
        }
    }

    private func present(_ error: Error) {
        if let api = error as? APIError, let code = EvidenceErrorCode.normalize(api.code) {
            errorMessage = code.fallbackMessage
        } else if let api = error as? APIError {
            errorMessage = api.message
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
