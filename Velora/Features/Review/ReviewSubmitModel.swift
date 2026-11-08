import Foundation
import Combine
import PhotosUI
import SwiftUI

/// Submit mutual review on a completed order (DES-v1.3-12-02 CRD-01 / D40).
@MainActor
final class ReviewSubmitModel: ObservableObject {
    let orderId: Int64

    @Published var rating: ReviewRating?
    @Published var content: String = ""
    @Published var imageIds: [String] = []
    @Published var imageThumbnails: [UIImage] = []
    @Published var pickerItems: [PhotosPickerItem] = []
    @Published var uploading = false
    @Published var submitting = false
    @Published var errorMessage: String?
    @Published var showBadConfirm = false
    @Published var submitted: OrderReview?
    @Published var draftHint = false

    private var idempotencyKey: String?
    private let draftKey: String

    init(orderId: Int64) {
        self.orderId = orderId
        self.draftKey = "review_draft_\(orderId)"
        restoreDraft()
    }

    private var isRealNamed: Bool {
        let raw = SessionStore.shared.bootstrap?.me?.realNameStatus ?? SessionStore.shared.user?.realNameStatus
        return RealNameStatusValue(rawValue: raw ?? "")?.isVerified == true || raw == "passed"
    }

    var canSubmit: Bool {
        rating != nil
            && !submitting
            && !uploading
            && ReviewCreditLogic.canSubmitReview(
                rating: rating,
                content: content.isEmpty ? nil : content,
                imageCount: imageIds.count,
                isLoggedIn: SessionStore.shared.isLoggedIn,
                isRealNamed: isRealNamed,
                windowOpen: true
            ) == nil
    }

    var remainingImages: Int {
        max(0, ReviewCreditConfigDefaults.reviewMaxImages - imageIds.count)
    }

    func selectRating(_ value: ReviewRating) {
        rating = value
        persistDraft()
        if value.requiresSecondaryConfirm {
            // Confirm is shown at submit time (design §9).
        }
    }

    func onContentChange() {
        if content.count > ReviewCreditConfigDefaults.reviewContentMax {
            content = String(content.prefix(ReviewCreditConfigDefaults.reviewContentMax))
        }
        persistDraft()
    }

    func onPickerChange(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let room = remainingImages
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
            let uploaded = try await API.uploadPublishImages(datas)
            for (idx, up) in uploaded.enumerated() {
                if let id = up.imageId ?? up.url {
                    imageIds.append(id)
                    if thumbs.indices.contains(idx) {
                        imageThumbnails.append(thumbs[idx])
                    }
                }
            }
            persistDraft()
        } catch {
            errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            draftHint = true
            ToastCenter.shared.error(error)
        }
    }

    func removeImage(at index: Int) {
        guard imageIds.indices.contains(index) else { return }
        imageIds.remove(at: index)
        if imageThumbnails.indices.contains(index) {
            imageThumbnails.remove(at: index)
        }
        persistDraft()
    }

    func requestSubmit() {
        guard let rating else { return }
        if rating.requiresSecondaryConfirm {
            showBadConfirm = true
            return
        }
        Task { await submit() }
    }

    func confirmBadAndSubmit() {
        showBadConfirm = false
        Task { await submit() }
    }

    func submit() async {
        errorMessage = nil
        if let gate = ReviewCreditLogic.canSubmitReview(
            rating: rating,
            content: content.isEmpty ? nil : content,
            imageCount: imageIds.count,
            isLoggedIn: SessionStore.shared.isLoggedIn,
            isRealNamed: isRealNamed,
            windowOpen: true
        ) {
            errorMessage = gate.fallbackMessage
            return
        }
        guard let rating else { return }
        submitting = true
        defer { submitting = false }
        if idempotencyKey == nil {
            idempotencyKey = APIClient.shared.idempotencyKey()
        }
        do {
            submitted = try await API.submitOrderReview(
                orderId: orderId,
                rating: rating,
                content: content.isEmpty ? nil : content,
                imageIds: imageIds,
                idempotencyKey: idempotencyKey
            )
            clearDraft()
            ToastCenter.shared.show(ReviewCreditCopy.submitSuccess, .success)
        } catch {
            if let api = error as? APIError {
                if let mapped = ReviewCreditErrorCode.normalize(api.code) {
                    errorMessage = mapped.fallbackMessage
                } else {
                    errorMessage = api.message
                }
                draftHint = true
            } else {
                errorMessage = error.localizedDescription
                draftHint = true
            }
            ToastCenter.shared.error(error)
        }
    }

    private func persistDraft() {
        let payload: [String: Any] = [
            "rating": rating?.rawValue as Any,
            "content": content,
            "image_ids": imageIds,
        ]
        UserDefaults.standard.set(payload, forKey: draftKey)
    }

    private func restoreDraft() {
        guard let payload = UserDefaults.standard.dictionary(forKey: draftKey) else { return }
        if let raw = payload["rating"] as? String {
            rating = ReviewRating.normalize(raw)
        }
        content = payload["content"] as? String ?? ""
        imageIds = payload["image_ids"] as? [String] ?? []
        if !imageIds.isEmpty || !(content.isEmpty) || rating != nil {
            draftHint = true
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        draftHint = false
    }
}
