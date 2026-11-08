import Foundation
import Combine

/// Listing detail + Q&A + 补图 (DES-v1.3-02-04). Auction realtime stays in `LotDetailModel`.
@MainActor
final class ListingDetailModel: ObservableObject {
    let listingId: Int64
    var preferredLotId: Int64?

    @Published var detail: ListingDetail?
    @Published var questions: [ListingQuestion] = []
    @Published var photoRequests: [PhotoRequestRow] = []
    @Published var state: LoadState = .idle
    @Published var asking = false
    @Published var requestingPhoto = false
    @Published var uploadingSupplement = false
    @Published var favoriting = false
    @Published var needsLogin = false
    @Published var needsRealName = false
    @Published var draftQuestion = ""
    @Published var selectedPart: PhotoRequestPart = .front

    init(listingId: Int64, preferredLotId: Int64? = nil) {
        self.listingId = listingId
        self.preferredLotId = preferredLotId
    }

    var me: Int64? { SessionStore.shared.user?.id }
    var isSeller: Bool { detail.map { $0.sellerId == me } ?? false }
    var qaLocked: Bool { detail?.qaLocked == true }
    var lotId: Int64? { preferredLotId ?? detail?.lotId }
    var myQuestionCount: Int { questions.filter { $0.askerId == me }.count }

    var visibleQuestions: [ListingQuestion] {
        questions.filter { q in
            if q.isVisibleToPublic { return true }
            if q.askerId == me { return true } // pending / rejected for asker
            return false
        }
    }

    func load() async {
        guard listingId > 0 else {
            state = .failed("无效商品")
            return
        }
        if detail == nil { state = .loading }
        do {
            let d = try await API.listing(listingId)
            detail = d
            questions = d.questions
            photoRequests = d.photoRequests
            if let lid = d.lotId { preferredLotId = lid }
            state = .loaded
            await refreshQuestionsIfNeeded()
        } catch {
            if let e = error as? APIError, e.code == ListingDetailErrorCode.listingNotPublic.rawValue {
                state = .failed(ListingDetailErrorCode.listingNotPublic.fallbackMessage)
                return
            }
            if detail == nil {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func refreshQuestionsIfNeeded() async {
        guard questions.isEmpty || detail?.questions.isEmpty == true else { return }
        do {
            questions = try await API.listingQuestions(listingId).items
        } catch {
            // First paint from detail payload is enough.
        }
    }

    @discardableResult
    func submitQuestion() async -> Bool {
        guard requireLogin() else { return false }
        if SessionStore.shared.accessFlags.isFrozen {
            ToastCenter.shared.show(ListingDetailErrorCode.accountFrozen.fallbackMessage, .info)
            return false
        }
        if isSeller {
            ToastCenter.shared.show(ListingDetailErrorCode.cannotAskSelf.fallbackMessage, .error)
            return false
        }
        if qaLocked {
            ToastCenter.shared.show(ListingDetailErrorCode.qaLocked.fallbackMessage, .info)
            return false
        }
        if let err = ListingQAValidator.validateQuestion(draftQuestion, alreadyAsked: myQuestionCount) {
            ToastCenter.shared.show(err.fallbackMessage, .error)
            return false
        }
        let content = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        asking = true
        defer { asking = false }
        do {
            let q = try await API.postListingQuestion(listingId, content: content)
            questions.insert(q, at: 0)
            draftQuestion = ""
            Haptics.success()
            ToastCenter.shared.show("提问已提交", .success)
            return true
        } catch {
            handleWriteError(error)
            return false
        }
    }

    @discardableResult
    func requestPhoto(part: PhotoRequestPart? = nil) async -> Bool {
        guard requireLogin() else { return false }
        if SessionStore.shared.accessFlags.isFrozen {
            ToastCenter.shared.show(ListingDetailErrorCode.accountFrozen.fallbackMessage, .info)
            return false
        }
        if qaLocked {
            ToastCenter.shared.show(ListingDetailErrorCode.photoRequestLocked.fallbackMessage, .info)
            return false
        }
        let p = part ?? selectedPart
        requestingPhoto = true
        defer { requestingPhoto = false }
        do {
            let row = try await API.postPhotoRequest(listingId, part: p)
            if let idx = photoRequests.firstIndex(where: { $0.part == row.part }) {
                photoRequests[idx] = row
            } else {
                photoRequests.append(row)
            }
            Haptics.light()
            ToastCenter.shared.show(row.progressText, .success)
            return true
        } catch {
            handleWriteError(error)
            return false
        }
    }

    @discardableResult
    func uploadSupplement(jpegData: Data) async -> Bool {
        guard isSeller else { return false }
        uploadingSupplement = true
        defer { uploadingSupplement = false }
        do {
            let urls = try await API.upload(images: [jpegData])
            guard let url = urls.first else {
                ToastCenter.shared.show("上传失败", .error)
                return false
            }
            _ = try await API.postSupplementPhoto(listingId: listingId, imageId: url)
            if detail != nil {
                await load()
            }
            Haptics.success()
            ToastCenter.shared.show("补图已上传", .success)
            return true
        } catch {
            handleWriteError(error)
            return false
        }
    }

    func toggleFavorite() async {
        guard requireLogin() else { return }
        guard let d = detail else { return }
        let target = !d.isFavorited
        // Optimistic: rebuild via reload after success; flip local fields by re-fetch.
        favoriting = true
        defer { favoriting = false }
        do {
            try await API.favoriteListing(listingId, target)
            await load()
            Haptics.light()
        } catch {
            handleWriteError(error)
        }
    }

    func requireLogin() -> Bool {
        if SessionStore.shared.isLoggedIn { return true }
        needsLogin = true
        return false
    }

    private func handleWriteError(_ error: Error) {
        if let e = error as? APIError {
            if let risk = IMRiskErrorCode.normalize(e.code) {
                // DES-v1.3-10-01: Q&A shares Filter; keep draft on content_blocked.
                switch risk {
                case .contentBlocked:
                    ToastCenter.shared.show(
                        e.message.isEmpty ? IMRiskCopy.blockedNotice : e.message,
                        .error
                    )
                case .contentReviewPending:
                    ToastCenter.shared.show(risk.fallbackMessage, .info)
                case .featureDisabled:
                    ToastCenter.shared.show(IMRiskCopy.imageScanFeatureDisabled, .info)
                default:
                    ToastCenter.shared.show(e.message.isEmpty ? risk.fallbackMessage : e.message, .error)
                }
                return
            }
            if let code = ListingDetailErrorCode(rawValue: e.code) {
                switch code {
                case .loginRequired:
                    needsLogin = true
                    ToastCenter.shared.show(code.fallbackMessage, .info)
                case .realNameRequired:
                    needsRealName = true
                    ToastCenter.shared.show(code.fallbackMessage, .info)
                case .accountFrozen:
                    SessionStore.shared.handleAccountFrozen(message: e.restrictionMessage)
                default:
                    ToastCenter.shared.show(e.message.isEmpty ? code.fallbackMessage : e.message, .error)
                }
                return
            }
            if e.code == RestrictionErrorCode.accountFrozen.rawValue {
                SessionStore.shared.handleAccountFrozen(message: e.restrictionMessage)
                return
            }
        }
        ToastCenter.shared.error(error)
    }
}
