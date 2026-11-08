import Foundation
import Combine

/// Loads `/me/overview` for ME-01～05 badges/entries (DES-v1.3-12-01 / D39).
@MainActor
final class MeOverviewModel: ObservableObject {
    @Published var overview: MeOverviewResponse?
    @Published var saveBrowseHistory = true
    @Published var loading = false
    @Published var partialHint = false
    @Published var switching = false

    func refresh() async {
        guard SessionStore.shared.isLoggedIn else {
            overview = nil
            partialHint = false
            return
        }
        loading = overview == nil
        defer { loading = false }
        do {
            let ov = try await API.meOverview()
            apply(ov)
        } catch let e as APIError where e.status == 404 {
            overview = nil
        } catch {
            #if DEBUG
            print("[me] overview failed: \(error)")
            #endif
        }
    }

    func apply(_ ov: MeOverviewResponse) {
        overview = ov
        if let save = ov.saveBrowseHistory { saveBrowseHistory = save }
        partialHint = ov.partial
    }

    /// Returns the server-confirmed view (for router sync). Throws / returns seller_required via result.
    enum SwitchResult {
        case ok(MeViewMode)
        case sellerRequired
        case failed
    }

    func switchView(_ mode: MeViewMode) async -> SwitchResult {
        switching = true
        defer { switching = false }
        do {
            let resp = try await API.updateMePrefs(meView: mode.rawValue)
            if resp.isSellerRequired {
                if let ov = resp.overview { apply(ov) }
                return .sellerRequired
            }
            if let ov = resp.overview {
                apply(ov)
                return .ok(ov.resolvedView)
            }
            return .ok(resp.resolvedView)
        } catch let e as APIError where e.code == MeErrorCode.sellerRequired.rawValue {
            return .sellerRequired
        } catch {
            return .failed
        }
    }

    func badge(for entryKey: String) -> Int {
        MeLogic.badge(for: entryKey, in: overview)
    }

    func overviewEntry(for entryKey: String) -> MeOverviewEntry? {
        overview?.entries.first(where: {
            $0.code == entryKey || MeEntryCode.normalize($0.code) == MeEntryCode.normalize(entryKey)
        })
    }

    func isEntryEnabled(_ entryKey: String, bootstrapEnabled: Bool) -> Bool {
        overviewEntry(for: entryKey)?.enabled ?? bootstrapEnabled
    }

    func reasonMessage(for entryKey: String) -> String? {
        overviewEntry(for: entryKey)?.resolvedReason?.displayMessage
    }
}
