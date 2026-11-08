import Foundation
import Combine
import PhotosUI
import SwiftUI

/// Report / bounty report form (DES-v1.3-10-02 RISK-04 / RISK-07 / D36).
@MainActor
final class ReportSheetModel: ObservableObject {
    let targetType: ReportTargetType
    let targetId: Int64
    let orderId: Int64?
    let isOrderBuyer: Bool
    let peerName: String?

    @Published var reason: ReportReason?
    @Published var attachConversation = false
    @Published var evidenceURLs: [String] = []
    @Published var evidenceThumbnails: [UIImage] = []
    @Published var pickerItems: [PhotosPickerItem] = []
    @Published var uploading = false
    @Published var submitting = false
    @Published var errorMessage: String?
    @Published var created: Report?

    private var idempotencyKey: String?

    init(
        targetType: ReportTargetType,
        targetId: Int64,
        orderId: Int64? = nil,
        isOrderBuyer: Bool = true,
        peerName: String? = nil
    ) {
        self.targetType = targetType
        self.targetId = targetId
        self.orderId = orderId
        self.isOrderBuyer = isOrderBuyer
        self.peerName = peerName
        if targetType.isBountyTarget {
            reason = .induceOffline
        }
    }

    var reasons: [ReportReason] { targetType.selectableReasons }

    var title: String {
        targetType.isBountyTarget ? RiskCopy.bountyReportTitle : RiskCopy.reportTitle
    }

    private var isRealNamed: Bool {
        let raw = SessionStore.shared.bootstrap?.me?.realNameStatus ?? SessionStore.shared.user?.realNameStatus
        return RealNameStatusValue(rawValue: raw ?? "")?.isVerified == true
            || raw == "passed"
    }

    private var accountFrozen: Bool {
        SessionStore.shared.user?.isFrozen == true
            || SessionStore.shared.bootstrap?.me?.status == AccountStatus.frozen.rawValue
    }

    var gateError: RiskErrorCode? {
        RiskLogic.createReportGate(
            targetType: targetType,
            reason: reason,
            evidenceCount: evidenceURLs.count,
            attachConversation: attachConversation,
            orderId: orderId,
            isLoggedIn: SessionStore.shared.isLoggedIn,
            isRealNamed: isRealNamed,
            accountFrozen: accountFrozen,
            isOrderBuyer: isOrderBuyer
        )
    }

    var canSubmit: Bool {
        reason != nil
            && !submitting
            && !uploading
            && RiskLogic.canSubmitReport(
                targetType: targetType,
                reason: reason,
                evidenceCount: evidenceURLs.count,
                attachConversation: attachConversation,
                orderId: orderId,
                isLoggedIn: SessionStore.shared.isLoggedIn,
                isRealNamed: isRealNamed,
                accountFrozen: accountFrozen,
                isOrderBuyer: isOrderBuyer
            )
    }

    func onPickerChange(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let room = RiskConfigDefaults.evidencePhotosMax - evidenceURLs.count
        guard room > 0 else {
            pickerItems = []
            return
        }
        uploading = true
        defer {
            uploading = false
            pickerItems = []
        }
        var datas: [Data] = []
        var thumbs: [UIImage] = []
        for item in items.prefix(room) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                datas.append(data)
                if let img = UIImage(data: data) { thumbs.append(img) }
            }
        }
        guard !datas.isEmpty else { return }
        do {
            let urls = try await API.upload(images: datas)
            evidenceURLs.append(contentsOf: urls)
            evidenceThumbnails.append(contentsOf: thumbs.prefix(urls.count))
        } catch {
            errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            ToastCenter.shared.error(error)
        }
    }

    func removeEvidence(at index: Int) {
        guard evidenceURLs.indices.contains(index) else { return }
        evidenceURLs.remove(at: index)
        if evidenceThumbnails.indices.contains(index) {
            evidenceThumbnails.remove(at: index)
        }
    }

    func submit() async {
        errorMessage = gateError?.fallbackMessage
        guard let reason, canSubmit else { return }
        submitting = true
        defer { submitting = false }
        if idempotencyKey == nil {
            idempotencyKey = APIClient.shared.idempotencyKey()
        }
        let req = CreateReportRequest(
            targetType: targetType,
            targetId: targetId,
            reason: reason,
            evidenceUrls: evidenceURLs,
            orderId: orderId,
            attachConversation: attachConversation && targetType.isBountyTarget
        )
        do {
            created = try await API.createReport(req, idempotencyKey: idempotencyKey)
            ToastCenter.shared.show(RiskCopy.reportSuccess, .success)
        } catch {
            if let api = error as? APIError, let mapped = RiskErrorCode.normalize(api.code) {
                errorMessage = mapped.fallbackMessage
            } else {
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            }
            ToastCenter.shared.error(error)
        }
    }
}
