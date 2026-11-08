import Foundation
import CryptoKit

// MARK: - Ship / unbox evidence + video fingerprint (DES-v1.3-09-01 AFS-01～03 / D33 — app mirror of VeloraCore)

/// Product defaults (design §3 config). Hot-config on server; client mirrors for UX + gate.
enum EvidenceConfigDefaults {
    static let inspectVideoRequiredSellerTypes = ["proxy_agent", "brand"]
    static let inspectVideoMinAmountFen: Int64 = 200_000
    static let unboxVideoMode = "guided"
    static let shipPhotosMinCount = 5
    static let unboxPhotosMinCount = 3
    static let unboxPhotosMaxCount = 9
    static let photoMaxBytes = 10_485_760
    static let videoMinDurationMs: Int64 = 3_000
    static let videoMaxDurationMs: Int64 = 300_000
    static let videoMaxBytes: Int64 = 524_288_000
    static let photoRetentionDaysAfterComplete = 180
    static let videoRetentionDaysAfterCaseClosed = 60
    static let sessionTTLSeconds = 900
    static let photoMinLuma = 80
    static let clockSkewWarnSeconds: TimeInterval = 5
    static let captureArriveSkewSeconds: TimeInterval = 20 * 60
    static let hashChunkBytes = 1_048_576
    static let videoPartSizeBytes = 5_242_880
    static let disputeUploadTTLHours = 24
    static let featureFlagAfsVideo = "afs_video"
    static let photoSourceAppCamera = "app_camera"
    static let localEvidenceDirName = "Evidence"
    static let shipVideoFileName = "ship_video.bin"
    static let unboxVideoFileName = "unbox_video.bin"
    static let watermarkFontPt: Double = 28
    static let watermarkStrokePx: Double = 2
    static let watermarkMarginPx: Double = 24
    static let watermarkOpacity: Double = 0.85
    static let jpegQuality: Double = 0.85
    static let photoLongEdgeMin = 1920
    static let photoLongEdgeMax = 2560
    static let photoMinShortEdge = 720
}

// MARK: - Kind / slot / status

enum EvidenceKindGroup: String, Codable, Sendable, CaseIterable, Equatable {
    case ship
    case unbox

    var displayLabel: String {
        switch self {
        case .ship: return "发货取证"
        case .unbox: return "开箱取证"
        }
    }
}

enum EvidenceKind: String, Codable, Sendable, CaseIterable, Equatable {
    case shipPhoto = "ship_photo"
    case unboxPhoto = "unbox_photo"
    case shipVideo = "ship_video"
    case unboxVideo = "unbox_video"

    var isPhoto: Bool {
        self == .shipPhoto || self == .unboxPhoto
    }

    var isVideo: Bool {
        self == .shipVideo || self == .unboxVideo
    }

    var kindGroup: EvidenceKindGroup {
        switch self {
        case .shipPhoto, .shipVideo: return .ship
        case .unboxPhoto, .unboxVideo: return .unbox
        }
    }

    var displayLabel: String {
        switch self {
        case .shipPhoto: return "发货照片"
        case .unboxPhoto: return "开箱照片"
        case .shipVideo: return "验车视频"
        case .unboxVideo: return "开箱视频"
        }
    }
}

/// Ship photo slots (AFS-01). Unbox issue slots are `issue_1…issue_n`.
enum EvidencePhotoSlot: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case front
    case back
    case left
    case right
    case boxBottom = "box_bottom"

    var id: String { rawValue }

    static let shipRequired: [EvidencePhotoSlot] = [.front, .back, .left, .right, .boxBottom]

    var displayLabel: String {
        switch self {
        case .front: return "正面"
        case .back: return "背面"
        case .left: return "左侧"
        case .right: return "右侧"
        case .boxBottom: return "盒底"
        }
    }

    var voiceOverHint: String { displayLabel }

    var diagramSystemImage: String {
        switch self {
        case .front: return "cube.transparent"
        case .back: return "cube"
        case .left: return "arrow.left.square"
        case .right: return "arrow.right.square"
        case .boxBottom: return "shippingbox"
        }
    }
}

enum EvidenceVideoSlot: String, Codable, Sendable, CaseIterable, Equatable {
    case full
}

enum EvidenceSessionStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case consumed
    case expired

    var isUsable: Bool { self == .open }
}

enum EvidenceVideoUploadStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case initiated
    case uploading
    case hashing
    case matched
    case mismatch
    case transcoding
    case ready
    case failed

    var isTerminal: Bool {
        switch self {
        case .ready, .mismatch, .failed: return true
        default: return false
        }
    }

    /// Illegal: ready → uploading. mismatch may reopen for same arbitration.
    func canTransition(to next: EvidenceVideoUploadStatus) -> Bool {
        if self == next { return true }
        if self == .ready { return false }
        switch (self, next) {
        case (.initiated, .uploading),
             (.uploading, .hashing),
             (.uploading, .failed),
             (.hashing, .matched),
             (.hashing, .mismatch),
             (.hashing, .failed),
             (.matched, .transcoding),
             (.transcoding, .ready),
             (.transcoding, .failed),
             (.mismatch, .initiated),
             (.failed, .initiated):
            return true
        default:
            return false
        }
    }
}

/// Local draft machine (design §5.10).
enum EvidenceDraftPhase: String, Codable, Sendable, CaseIterable, Equatable {
    case idle
    case sessionOpen = "session_open"
    case capturingPhoto = "capturing_photo"
    case recordingVideo = "recording_video"
    case hashing
    case fingerprintSubmitted = "fingerprint_submitted"
    case readyToShip = "ready_to_ship"

    var displayLabel: String {
        switch self {
        case .idle: return "未开始"
        case .sessionOpen: return "会话已开"
        case .capturingPhoto: return "拍摄中"
        case .recordingVideo: return "录像中"
        case .hashing: return "正在计算指纹"
        case .fingerprintSubmitted: return "指纹已登记"
        case .readyToShip: return "可发货"
        }
    }

    func canTransition(to next: EvidenceDraftPhase) -> Bool {
        if self == next { return true }
        switch (self, next) {
        case (.idle, .sessionOpen),
             (.sessionOpen, .capturingPhoto),
             (.sessionOpen, .recordingVideo),
             (.sessionOpen, .readyToShip),
             (.capturingPhoto, .sessionOpen),
             (.capturingPhoto, .recordingVideo),
             (.capturingPhoto, .readyToShip),
             (.recordingVideo, .hashing),
             (.recordingVideo, .sessionOpen), // interrupt / 重录
             (.hashing, .fingerprintSubmitted),
             (.hashing, .recordingVideo), // hash fail → re-record
             (.fingerprintSubmitted, .readyToShip),
             (.fingerprintSubmitted, .recordingVideo), // 发货前覆盖
             (.readyToShip, .capturingPhoto),
             (.readyToShip, .recordingVideo),
             (.readyToShip, .sessionOpen):
            return true
        default:
            return false
        }
    }
}

enum EvidenceFingerprintStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case missing
    case registered
    case registeredNotUploaded = "registered_not_uploaded"
    case mismatch
    case verified

    var displayLabel: String {
        switch self {
        case .missing: return "未登记"
        case .registered: return "已登记"
        case .registeredNotUploaded: return "已登记未上传"
        case .mismatch: return "证据不一致"
        case .verified: return "已校验"
        }
    }
}

// MARK: - Error codes (design §5.11)

enum EvidenceErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case captureSessionExpired = "capture_session_expired"
    case albumUploadForbidden = "album_upload_forbidden"
    case evidenceTooDark = "evidence_too_dark"
    case evidenceTooSmall = "evidence_too_small"
    case inspectVideoRequired = "inspect_video_required"
    case fingerprintFrozen = "fingerprint_frozen"
    case evidenceMismatch = "evidence_mismatch"
    case videoNotInDispute = "video_not_in_dispute"
    case uploadIncomplete = "upload_incomplete"
    case evidencePurged = "evidence_purged"
    case merchantEvidenceAppOnly = "merchant_evidence_app_only"
    case featureDisabled = "feature_disabled"
    case evidencePhotosIncomplete = "evidence_photos_incomplete"
    case evidenceRequired = "evidence_required"
    case videoTooLong = "video_too_long"
    case videoTooShort = "video_too_short"
    case sha256Invalid = "sha256_invalid"
    case fileTooLarge = "file_too_large"
    case slotInvalid = "slot_invalid"
    case duplicatePhoto = "duplicate_photo"
    case fingerprintNotFound = "fingerprint_not_found"
    case durationMismatch = "duration_mismatch"
    case partSizeInvalid = "part_size_invalid"
    case storageUnavailable = "storage_unavailable"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case notOrderParty = "not_order_party"
    case orderStatusInvalid = "order_status_invalid"
    case orderNotFound = "order_not_found"
    case unauthenticated = "unauthenticated"
    case localVideoMissing = "local_video_missing"
    case cameraPermissionDenied = "camera_permission_denied"
    case hashingInProgress = "hashing_in_progress"

    static func normalize(_ raw: String?) -> EvidenceErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = EvidenceErrorCode(rawValue: s) { return exact }
        switch s {
        case "http_401", "401": return .unauthenticated
        case "http_404", "404": return .orderNotFound
        case "photos_incomplete", "ship_photos_incomplete": return .evidencePhotosIncomplete
        case "video_required", "inspect_required": return .inspectVideoRequired
        default: return nil
        }
    }

    var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return EvidenceCopy.missingIdempotencyKey
        case .captureSessionExpired: return EvidenceCopy.sessionExpired
        case .albumUploadForbidden: return EvidenceCopy.albumForbidden
        case .evidenceTooDark: return EvidenceCopy.tooDark
        case .evidenceTooSmall: return EvidenceCopy.tooSmall
        case .inspectVideoRequired: return EvidenceCopy.inspectVideoRequired
        case .fingerprintFrozen: return EvidenceCopy.fingerprintFrozen
        case .evidenceMismatch: return EvidenceCopy.evidenceMismatch
        case .videoNotInDispute: return EvidenceCopy.videoNotInDispute
        case .uploadIncomplete: return EvidenceCopy.uploadIncomplete
        case .evidencePurged: return EvidenceCopy.evidencePurged
        case .merchantEvidenceAppOnly: return EvidenceCopy.merchantAppOnly
        case .featureDisabled: return EvidenceCopy.featureDisabled
        case .evidencePhotosIncomplete, .evidenceRequired: return EvidenceCopy.photosIncomplete
        case .videoTooLong: return EvidenceCopy.videoTooLong
        case .videoTooShort: return EvidenceCopy.videoTooShort
        case .sha256Invalid: return EvidenceCopy.sha256Invalid
        case .fileTooLarge: return EvidenceCopy.fileTooLarge
        case .slotInvalid: return EvidenceCopy.slotInvalid
        case .duplicatePhoto: return EvidenceCopy.duplicatePhoto
        case .fingerprintNotFound: return EvidenceCopy.fingerprintNotFound
        case .durationMismatch: return EvidenceCopy.durationMismatch
        case .partSizeInvalid: return EvidenceCopy.partSizeInvalid
        case .storageUnavailable: return EvidenceCopy.storageUnavailable
        case .realNameRequired: return EvidenceCopy.realNameRequired
        case .accountRestricted: return EvidenceCopy.accountRestricted
        case .notOrderParty: return EvidenceCopy.notOrderParty
        case .orderStatusInvalid: return EvidenceCopy.orderStatusInvalid
        case .orderNotFound: return EvidenceCopy.orderNotFound
        case .unauthenticated: return EvidenceCopy.unauthenticated
        case .localVideoMissing: return EvidenceCopy.localVideoMissing
        case .cameraPermissionDenied: return EvidenceCopy.cameraDenied
        case .hashingInProgress: return EvidenceCopy.hashingInProgress
        }
    }
}

// MARK: - UX copy (design §9)

enum EvidenceCopy {
    static let titleShip = "发货取证"
    static let titleUnbox = "开箱取证"
    static let shipHint = "须在 App 内拍摄五张照片；不可从相册选择"
    static let slotProgressFormat = "%d/%d"
    static let shootSlot = "拍摄"
    static let retake = "重拍"
    static let recordInspect = "录制验车视频"
    static let recordUnbox = "录制开箱视频"
    static let skipUnbox = "暂不录制"
    static let unboxGuideTitle = "建议录制开箱视频"
    static let unboxGuideBody = "录制后仅上传指纹，原片留在本机；品相争议时再上传"
    static let hashing = "正在计算指纹"
    static let fingerprintDone = "指纹已登记"
    static let readyToShip = "取证完成，可以发货"
    static let goEvidence = "去取证"
    static let continueEvidence = "继续取证"
    static let serverTimeHint = "以服务器时间为准"
    static let openLights = "打开灯光重新拍"
    static let cameraDenied = "需要相机权限才能取证；请在系统设置中开启，不可改用相册"
    static let albumForbidden = "取证必须使用 App 内相机，不可从相册选择"
    static let tooDark = "光线不足，请打开灯光重新拍"
    static let tooSmall = "照片分辨率过低，请靠近重拍"
    static let sessionExpired = "拍摄会话已过期，请重新开始"
    static let photosIncomplete = "发货取证未完备，请先完成拍照/验车视频"
    static let inspectVideoRequired = "请先录制验车视频并登记指纹"
    static let fingerprintFrozen = "已发货，不可修改验车指纹"
    static let evidenceMismatch = "原片与登记指纹不一致"
    static let videoNotInDispute = "当前不在争议上传期"
    static let uploadIncomplete = "视频分片不完整，请续传"
    static let evidencePurged = "证据已到期删除"
    static let merchantAppOnly = "商家后台请使用 App 完成取证"
    static let featureDisabled = "视频取证能力暂未开放"
    static let videoTooLong = "视频不可超过 5 分钟"
    static let videoTooShort = "视频至少录制 3 秒"
    static let sha256Invalid = "指纹格式无效"
    static let fileTooLarge = "文件过大"
    static let slotInvalid = "槽位无效"
    static let duplicatePhoto = "与已有照片过于相似，请换角度重拍"
    static let fingerprintNotFound = "尚未登记视频指纹"
    static let durationMismatch = "视频时长与登记不一致"
    static let partSizeInvalid = "分片大小无效"
    static let storageUnavailable = "存储暂不可用，请稍后重试"
    static let realNameRequired = "请先完成实名认证"
    static let accountRestricted = "账号受限，无法取证"
    static let notOrderParty = "非订单当事人"
    static let orderStatusInvalid = "当前订单状态不可取证"
    static let orderNotFound = "订单不存在"
    static let unauthenticated = "请先登录"
    static let localVideoMissing = "本地视频丢失，争议期将无法提供一致原片，可能被不利推定"
    static let hashingInProgress = "正在计算指纹，请稍候再发货"
    static let missingIdempotencyKey = "缺少幂等键"
    static let watermarkPreviewHint = "水印不可关闭"
    static let interruptRerecord = "录制中断，请重新录制"
    static let unboxSkippedHint = "已跳过开箱视频，可稍后补录"
    static let supplementUnbox = "补录开箱视频"
}

// MARK: - Domain models

struct EvidenceCaptureSession: Codable, Equatable, Sendable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let orderId: Int64?
    let kindGroup: EvidenceKindGroup
    let nonce: String
    let watermarkText: String
    let serverTime: Date
    let expiresAt: Date
    let slots: [String]
    let inspectVideoRequired: Bool
    let status: EvidenceSessionStatus?
    let deviceId: String?

    init(
        sessionId: String,
        orderId: Int64? = nil,
        kindGroup: EvidenceKindGroup,
        nonce: String,
        watermarkText: String,
        serverTime: Date,
        expiresAt: Date,
        slots: [String] = EvidencePhotoSlot.shipRequired.map(\.rawValue),
        inspectVideoRequired: Bool = false,
        status: EvidenceSessionStatus? = .open,
        deviceId: String? = nil
    ) {
        self.sessionId = sessionId
        self.orderId = orderId
        self.kindGroup = kindGroup
        self.nonce = nonce
        self.watermarkText = watermarkText
        self.serverTime = serverTime
        self.expiresAt = expiresAt
        self.slots = slots
        self.inspectVideoRequired = inspectVideoRequired
        self.status = status
        self.deviceId = deviceId
    }

    var isExpired: Bool { Date() >= expiresAt || status == .expired }
    var remainingSeconds: Int { max(0, Int(expiresAt.timeIntervalSinceNow)) }
}

struct EvidenceItem: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let orderId: Int64?
    let kind: EvidenceKind
    let slot: String
    let sha256: String?
    let sha256Prefix: String?
    let durationMs: Int64?
    let byteSize: Int64?
    let url: String?
    let posterUrl: String?
    let watermarkText: String?
    let serverTs: Date?
    let verified: Bool?
    let mismatchReason: String?
    let version: Int?
    let source: String?
    let captureSessionId: String?
    let lumaMean: Double?
    let deletedAt: Date?

    init(
        id: Int64,
        orderId: Int64? = nil,
        kind: EvidenceKind,
        slot: String,
        sha256: String? = nil,
        sha256Prefix: String? = nil,
        durationMs: Int64? = nil,
        byteSize: Int64? = nil,
        url: String? = nil,
        posterUrl: String? = nil,
        watermarkText: String? = nil,
        serverTs: Date? = nil,
        verified: Bool? = nil,
        mismatchReason: String? = nil,
        version: Int? = nil,
        source: String? = nil,
        captureSessionId: String? = nil,
        lumaMean: Double? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.kind = kind
        self.slot = slot
        self.sha256 = sha256
        self.sha256Prefix = sha256Prefix
        self.durationMs = durationMs
        self.byteSize = byteSize
        self.url = url
        self.posterUrl = posterUrl
        self.watermarkText = watermarkText
        self.serverTs = serverTs
        self.verified = verified
        self.mismatchReason = mismatchReason
        self.version = version
        self.source = source
        self.captureSessionId = captureSessionId
        self.lumaMean = lumaMean
        self.deletedAt = deletedAt
    }

    var isActive: Bool { deletedAt == nil }
    var maskedSha: String {
        if let p = sha256Prefix, !p.isEmpty { return p }
        guard let sha = sha256, sha.count >= 8 else { return "--------" }
        return String(sha.prefix(8))
    }
}

struct EvidenceSlotProgress: Codable, Equatable, Sendable, Identifiable {
    var id: String { slot }
    let slot: String
    let filled: Bool
    let evidenceId: Int64?
    let verified: Bool?
    let thumbnailUrl: String?

    init(
        slot: String,
        filled: Bool,
        evidenceId: Int64? = nil,
        verified: Bool? = nil,
        thumbnailUrl: String? = nil
    ) {
        self.slot = slot
        self.filled = filled
        self.evidenceId = evidenceId
        self.verified = verified
        self.thumbnailUrl = thumbnailUrl
    }
}

struct OrderEvidenceState: Codable, Equatable, Sendable {
    let orderId: Int64
    let kindGroup: EvidenceKindGroup?
    let inspectVideoRequired: Bool
    let shipPhotoSlots: [EvidenceSlotProgress]
    let unboxPhotoSlots: [EvidenceSlotProgress]?
    let shipVideo: EvidenceFingerprintStatus?
    let unboxVideo: EvidenceFingerprintStatus?
    let unboxVideoSkippedAt: Date?
    let evidenceReady: Bool?
    let shipFrozen: Bool?
    let openSession: EvidenceCaptureSession?
    let items: [EvidenceItem]?

    init(
        orderId: Int64,
        kindGroup: EvidenceKindGroup? = nil,
        inspectVideoRequired: Bool = false,
        shipPhotoSlots: [EvidenceSlotProgress] = [],
        unboxPhotoSlots: [EvidenceSlotProgress]? = nil,
        shipVideo: EvidenceFingerprintStatus? = nil,
        unboxVideo: EvidenceFingerprintStatus? = nil,
        unboxVideoSkippedAt: Date? = nil,
        evidenceReady: Bool? = nil,
        shipFrozen: Bool? = nil,
        openSession: EvidenceCaptureSession? = nil,
        items: [EvidenceItem]? = nil
    ) {
        self.orderId = orderId
        self.kindGroup = kindGroup
        self.inspectVideoRequired = inspectVideoRequired
        self.shipPhotoSlots = shipPhotoSlots
        self.unboxPhotoSlots = unboxPhotoSlots
        self.shipVideo = shipVideo
        self.unboxVideo = unboxVideo
        self.unboxVideoSkippedAt = unboxVideoSkippedAt
        self.evidenceReady = evidenceReady
        self.shipFrozen = shipFrozen
        self.openSession = openSession
        self.items = items
    }

    var shipPhotosFilledCount: Int {
        shipPhotoSlots.filter(\.filled).count
    }

    var shipPhotosComplete: Bool {
        let required = Set(EvidencePhotoSlot.shipRequired.map(\.rawValue))
        let filled = Set(shipPhotoSlots.filter(\.filled).map(\.slot))
        return required.isSubset(of: filled) || shipPhotosFilledCount >= EvidenceConfigDefaults.shipPhotosMinCount
    }
}

struct EvidenceSummary: Codable, Equatable, Sendable {
    let inspectRequired: Bool
    let shipVideo: EvidenceFingerprintStatus?
    let unboxSkipped: Bool?
    let shipPhotosComplete: Bool?
    let evidenceReady: Bool?

    init(
        inspectRequired: Bool,
        shipVideo: EvidenceFingerprintStatus? = nil,
        unboxSkipped: Bool? = nil,
        shipPhotosComplete: Bool? = nil,
        evidenceReady: Bool? = nil
    ) {
        self.inspectRequired = inspectRequired
        self.shipVideo = shipVideo
        self.unboxSkipped = unboxSkipped
        self.shipPhotosComplete = shipPhotosComplete
        self.evidenceReady = evidenceReady
    }
}

struct EvidencePhotoUploadResult: Codable, Equatable, Sendable {
    let id: Int64
    let sha256: String
    let slot: String
    let verified: Bool

    init(id: Int64, sha256: String, slot: String, verified: Bool) {
        self.id = id
        self.sha256 = sha256
        self.slot = slot
        self.verified = verified
    }
}

struct EvidenceVideoFingerprintRequest: Equatable, Sendable {
    let sessionId: String
    let kind: EvidenceKind
    let sha256: String
    let durationMs: Int64
    let byteSize: Int64
    let deviceId: String
    let slot: String

    init(
        sessionId: String,
        kind: EvidenceKind,
        sha256: String,
        durationMs: Int64,
        byteSize: Int64,
        deviceId: String,
        slot: String = EvidenceVideoSlot.full.rawValue
    ) {
        self.sessionId = sessionId
        self.kind = kind
        self.sha256 = sha256
        self.durationMs = durationMs
        self.byteSize = byteSize
        self.deviceId = deviceId
        self.slot = slot
    }

    var body: [String: Any?] {
        [
            "session_id": sessionId,
            "kind": kind.rawValue,
            "sha256": sha256,
            "duration_ms": durationMs,
            "byte_size": byteSize,
            "device_id": deviceId,
            "slot": slot,
        ]
    }
}

struct EvidenceVideoFingerprintResult: Codable, Equatable, Sendable {
    let id: Int64
    let kind: EvidenceKind
    let sha256: String
    let durationMs: Int64
    let byteSize: Int64?

    init(id: Int64, kind: EvidenceKind, sha256: String, durationMs: Int64, byteSize: Int64? = nil) {
        self.id = id
        self.kind = kind
        self.sha256 = sha256
        self.durationMs = durationMs
        self.byteSize = byteSize
    }
}

struct EvidenceVideoUploadSession: Codable, Equatable, Sendable {
    let uploadId: String
    let partSize: Int
    let maxBytes: Int64
    let expiresAt: Date

    init(uploadId: String, partSize: Int, maxBytes: Int64, expiresAt: Date) {
        self.uploadId = uploadId
        self.partSize = partSize
        self.maxBytes = maxBytes
        self.expiresAt = expiresAt
    }
}

struct EvidenceVideoCompleteResult: Codable, Equatable, Sendable {
    let verified: Bool
    let mismatchReason: String?
    let previewReady: Bool?

    init(verified: Bool, mismatchReason: String? = nil, previewReady: Bool? = nil) {
        self.verified = verified
        self.mismatchReason = mismatchReason
        self.previewReady = previewReady
    }
}

struct EvidenceRuleSnapshot: Codable, Equatable, Sendable {
    let required: Bool
    let sellerType: String?
    let amount: Int64?
    let configVersion: String?

    init(required: Bool, sellerType: String? = nil, amount: Int64? = nil, configVersion: String? = nil) {
        self.required = required
        self.sellerType = sellerType
        self.amount = amount
        self.configVersion = configVersion
    }
}

struct EvidenceDraft: Equatable, Sendable {
    var phase: EvidenceDraftPhase
    var session: EvidenceCaptureSession?
    var filledSlots: Set<String>
    var localVideoURL: URL?
    var pendingSha256: String?
    var pendingDurationMs: Int64?
    var frameSeq: Int
    var hashProgress: Double

    init(
        phase: EvidenceDraftPhase = .idle,
        session: EvidenceCaptureSession? = nil,
        filledSlots: Set<String> = [],
        localVideoURL: URL? = nil,
        pendingSha256: String? = nil,
        pendingDurationMs: Int64? = nil,
        frameSeq: Int = 0,
        hashProgress: Double = 0
    ) {
        self.phase = phase
        self.session = session
        self.filledSlots = filledSlots
        self.localVideoURL = localVideoURL
        self.pendingSha256 = pendingSha256
        self.pendingDurationMs = pendingDurationMs
        self.frameSeq = frameSeq
        self.hashProgress = hashProgress
    }
}

// MARK: - Hash / path helpers

enum EvidenceHasher {
    /// SHA-256 lowercase hex of in-memory bytes.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streaming SHA-256 over file (1MB chunks by default; design §5.10 / T-10).
    static func sha256Hex(
        ofFileAt url: URL,
        chunkSize: Int = EvidenceConfigDefaults.hashChunkBytes,
        onProgress: ((Double) -> Void)? = nil
    ) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let total = (attrs[.size] as? NSNumber)?.doubleValue ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var read: Double = 0
        while true {
            let chunk: Data
            if #available(iOS 13.4, macOS 10.15.4, *) {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } else {
                chunk = handle.readData(ofLength: chunkSize)
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            read += Double(chunk.count)
            if total > 0 {
                onProgress?(min(1, read / total))
            }
        }
        onProgress?(1)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Accept only 64 hex; normalize to lowercase. Nil if invalid.
    static func normalizeSha256(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.count == 64, s.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else {
            return nil
        }
        return s
    }
}

enum EvidenceStorage {
    /// Documents/Evidence/{orderId}/ — App Group optional later.
    static func directory(forOrderId orderId: Int64, base: URL? = nil) throws -> URL {
        let root = base ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = root
            .appendingPathComponent(EvidenceConfigDefaults.localEvidenceDirName, isDirectory: true)
            .appendingPathComponent("\(orderId)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func videoURL(orderId: Int64, kind: EvidenceKind, base: URL? = nil) throws -> URL {
        let name: String
        switch kind {
        case .shipVideo: name = EvidenceConfigDefaults.shipVideoFileName
        case .unboxVideo: name = EvidenceConfigDefaults.unboxVideoFileName
        default: name = "\(kind.rawValue).bin"
        }
        return try directory(forOrderId: orderId, base: base).appendingPathComponent(name)
    }

    static func localVideoExists(orderId: Int64, kind: EvidenceKind, base: URL? = nil) -> Bool {
        guard let url = try? videoURL(orderId: orderId, kind: kind, base: base) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - Logic

enum EvidenceLogic {
    /// B-16: proxy_agent / brand OR amount ≥ 200000 fen (inclusive).
    static func inspectVideoRequired(
        sellerType: String?,
        amountFen: Int64,
        requiredSellerTypes: [String] = EvidenceConfigDefaults.inspectVideoRequiredSellerTypes,
        minAmountFen: Int64 = EvidenceConfigDefaults.inspectVideoMinAmountFen,
        featureEnabled: Bool = true
    ) -> Bool {
        guard featureEnabled else { return false }
        let t = (sellerType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if requiredSellerTypes.map({ $0.lowercased() }).contains(t) { return true }
        return amountFen >= minAmountFen
    }

    static func snapshot(
        sellerType: String?,
        amountFen: Int64,
        configVersion: String? = nil,
        featureEnabled: Bool = true
    ) -> EvidenceRuleSnapshot {
        EvidenceRuleSnapshot(
            required: inspectVideoRequired(
                sellerType: sellerType,
                amountFen: amountFen,
                featureEnabled: featureEnabled
            ),
            sellerType: sellerType,
            amount: amountFen,
            configVersion: configVersion
        )
    }

    static func validateVideoDuration(
        _ durationMs: Int64,
        minMs: Int64 = EvidenceConfigDefaults.videoMinDurationMs,
        maxMs: Int64 = EvidenceConfigDefaults.videoMaxDurationMs
    ) -> EvidenceErrorCode? {
        if durationMs <= minMs { return .videoTooShort }
        if durationMs > maxMs { return .videoTooLong }
        return nil
    }

    static func validateVideoByteSize(
        _ bytes: Int64,
        maxBytes: Int64 = EvidenceConfigDefaults.videoMaxBytes
    ) -> EvidenceErrorCode? {
        if bytes <= 0 { return .fileTooLarge }
        if bytes > maxBytes { return .fileTooLarge }
        return nil
    }

    static func validatePhotoByteSize(
        _ bytes: Int,
        maxBytes: Int = EvidenceConfigDefaults.photoMaxBytes
    ) -> EvidenceErrorCode? {
        if bytes <= 0 || bytes > maxBytes { return .fileTooLarge }
        return nil
    }

    static func validateSha256(_ raw: String?) -> EvidenceErrorCode? {
        EvidenceHasher.normalizeSha256(raw) == nil ? .sha256Invalid : nil
    }

    static func validateShipPhotoSlot(_ slot: String) -> EvidenceErrorCode? {
        EvidencePhotoSlot(rawValue: slot) == nil ? .slotInvalid : nil
    }

    static func validateUnboxPhotoSlot(_ slot: String) -> EvidenceErrorCode? {
        if slot.hasPrefix("issue_") {
            let n = Int(slot.dropFirst("issue_".count)) ?? 0
            if n >= 1 && n <= EvidenceConfigDefaults.unboxPhotosMaxCount { return nil }
        }
        return .slotInvalid
    }

    static func photoIdempotencyKey(sessionId: String, slot: String) -> String {
        "photo:\(sessionId):\(slot)"
    }

    /// Phase 1 capture token: hash(nonce:frameSeq) — no App Attest yet.
    static func captureToken(nonce: String, frameSeq: Int) -> String {
        EvidenceHasher.sha256Hex(Data("\(nonce):\(frameSeq)".utf8))
    }

    static func shouldWarnClockSkew(
        localNow: Date,
        serverTime: Date,
        threshold: TimeInterval = EvidenceConfigDefaults.clockSkewWarnSeconds
    ) -> Bool {
        abs(localNow.timeIntervalSince(serverTime)) > threshold
    }

    static func buildWatermarkText(orderNo: String, serverTime: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return "\(orderNo) \(fmt.string(from: serverTime))"
    }

    /// Client-side CanShip (design §4). Server is authoritative.
    static func canShip(
        state: OrderEvidenceState,
        hashingInProgress: Bool = false,
        featureVideoEnabled: Bool = true
    ) -> EvidenceErrorCode? {
        if hashingInProgress { return .hashingInProgress }
        if !state.shipPhotosComplete { return .evidencePhotosIncomplete }
        let needVideo = state.inspectVideoRequired && featureVideoEnabled
        if needVideo {
            switch state.shipVideo {
            case .registered, .registeredNotUploaded, .verified:
                break
            case .mismatch:
                return .evidenceMismatch
            case .missing, .none:
                return .inspectVideoRequired
            }
        }
        return nil
    }

    static func canShip(
        photosFilled: Int,
        inspectRequired: Bool,
        shipVideoRegistered: Bool,
        hashingInProgress: Bool = false,
        featureVideoEnabled: Bool = true,
        minPhotos: Int = EvidenceConfigDefaults.shipPhotosMinCount
    ) -> EvidenceErrorCode? {
        if hashingInProgress { return .hashingInProgress }
        if photosFilled < minPhotos { return .evidencePhotosIncomplete }
        if inspectRequired && featureVideoEnabled && !shipVideoRegistered {
            return .inspectVideoRequired
        }
        return nil
    }

    /// Condition-mismatch / transport-damage after-sale gate (AFS-02).
    static func canOpenAppearanceAfterSale(unboxPhotoCount: Int) -> EvidenceErrorCode? {
        if unboxPhotoCount < EvidenceConfigDefaults.unboxPhotosMinCount {
            return .evidencePhotosIncomplete
        }
        return nil
    }

    static func advanceDraft(_ draft: inout EvidenceDraft, to phase: EvidenceDraftPhase) -> Bool {
        guard draft.phase.canTransition(to: phase) else { return false }
        draft.phase = phase
        return true
    }

    static func recomputeReadyPhase(
        photosComplete: Bool,
        inspectRequired: Bool,
        fingerprintDone: Bool,
        featureVideoEnabled: Bool = true
    ) -> EvidenceDraftPhase {
        if !photosComplete { return .sessionOpen }
        if inspectRequired && featureVideoEnabled && !fingerprintDone {
            return .sessionOpen
        }
        if fingerprintDone || !(inspectRequired && featureVideoEnabled) {
            return .readyToShip
        }
        return .sessionOpen
    }

    static func slotProgressLabel(filled: Int, total: Int = EvidenceConfigDefaults.shipPhotosMinCount) -> String {
        String(format: EvidenceCopy.slotProgressFormat, filled, total)
    }

    static func emptyShipSlots() -> [EvidenceSlotProgress] {
        EvidencePhotoSlot.shipRequired.map {
            EvidenceSlotProgress(slot: $0.rawValue, filled: false)
        }
    }

    static func mergeServerSlots(
        _ server: [EvidenceSlotProgress],
        required: [EvidencePhotoSlot] = EvidencePhotoSlot.shipRequired
    ) -> [EvidenceSlotProgress] {
        let bySlot = Dictionary(uniqueKeysWithValues: server.map { ($0.slot, $0) })
        return required.map { slot in
            bySlot[slot.rawValue] ?? EvidenceSlotProgress(slot: slot.rawValue, filled: false)
        }
    }

    static func partCount(totalBytes: Int64, partSize: Int = EvidenceConfigDefaults.videoPartSizeBytes) -> Int {
        guard totalBytes > 0, partSize > 0 else { return 0 }
        return Int((totalBytes + Int64(partSize) - 1) / Int64(partSize))
    }
}
