import Foundation
import Combine

/// Offer write actions + error mapping (DES-v1.3-04-02 §5 / §6).
@MainActor
final class OfferActionModel: ObservableObject {
    @Published var busy = false
    @Published var needsLogin = false
    @Published var needsRealName = false
    @Published var lastCard: OfferCard?
    @Published var lastAccepted: AcceptOfferResponse?
    @Published var lastErrorMessage: String?

    private var idempotencyKey = UUID().uuidString

    func resetIdempotency() {
        idempotencyKey = UUID().uuidString
    }

    func createOffer(listingId: Int64, priceFen: Int64) async -> OfferCard? {
        busy = true
        defer { busy = false }
        do {
            let resp = try await API.createOffer(listingId, price: priceFen, idempotencyKey: idempotencyKey)
            resetIdempotency()
            lastCard = resp.card ?? OfferCard(
                offerId: resp.offerId,
                listingId: listingId,
                listPrice: 0,
                offerPrice: priceFen,
                expiresAt: resp.expiresAt,
                round: resp.round ?? 1,
                status: resp.status ?? .pendingSeller,
                actions: [.cancel],
                serverTime: resp.serverTime,
                minPrice: resp.minPrice
            )
            Haptics.success()
            return lastCard
        } catch {
            handle(error, minPriceHint: nil)
            return nil
        }
    }

    func counterOffer(offerId: Int64, priceFen: Int64) async -> OfferCard? {
        busy = true
        defer { busy = false }
        do {
            let resp = try await API.counterOffer(offerId, price: priceFen, idempotencyKey: idempotencyKey)
            resetIdempotency()
            lastCard = resp.card
            Haptics.success()
            return lastCard
        } catch {
            handle(error, minPriceHint: nil)
            return nil
        }
    }

    func acceptOffer(offerId: Int64) async -> AcceptOfferResponse? {
        busy = true
        defer { busy = false }
        do {
            let resp = try await API.acceptOffer(offerId, idempotencyKey: idempotencyKey)
            // Idempotent re-accept returns same order_id — keep key only on success path for retries of stock.
            lastAccepted = resp
            Haptics.success()
            ToastCenter.shared.show(OfferCopy.lockPayRule, .success)
            return resp
        } catch {
            if let e = error as? APIError, OfferErrorCode(rawValue: e.code)?.retriesSameIdempotencyKey == true {
                // keep key
            } else {
                resetIdempotency()
            }
            handle(error, minPriceHint: nil)
            return nil
        }
    }

    func rejectOffer(offerId: Int64, reason: OfferRejectReasonCode, note: String?) async -> Bool {
        if let msg = OfferLogic.validateRejectNote(reason: reason, note: note) {
            ToastCenter.shared.show(msg, .error)
            return false
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await API.rejectOffer(
                offerId,
                reason: reason,
                note: reason.requiresNote ? note : nil,
                idempotencyKey: idempotencyKey
            )
            resetIdempotency()
            Haptics.light()
            return true
        } catch {
            handle(error, minPriceHint: nil)
            return false
        }
    }

    func cancelOffer(offerId: Int64) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            _ = try await API.cancelOffer(offerId, idempotencyKey: idempotencyKey)
            resetIdempotency()
            Haptics.light()
            return true
        } catch {
            handle(error, minPriceHint: nil)
            return false
        }
    }

    func myOffer(listingId: Int64) async -> Offer? {
        do {
            return try await API.myListingOffer(listingId)
        } catch {
            return nil
        }
    }

    private func handle(_ error: Error, minPriceHint: Int64?) {
        if let e = error as? APIError {
            if let code = OfferErrorCode(rawValue: e.code) {
                switch code {
                case .unauthorized:
                    needsLogin = true
                case .realNameRequired:
                    needsRealName = true
                case .accountRestricted:
                    SessionStore.shared.handleAccountFrozen(message: e.restrictionMessage)
                default:
                    break
                }
                let msg = e.message.isEmpty
                    ? code.message(minPriceFen: minPriceHint ?? extractMinFromMessage(e.message))
                    : e.message
                lastErrorMessage = msg
                ToastCenter.shared.show(msg, code == .stockInsufficient ? .info : .error)
                return
            }
            if e.code == RestrictionErrorCode.accountFrozen.rawValue {
                SessionStore.shared.handleAccountFrozen(message: e.restrictionMessage)
                return
            }
            if e.code == DirectZoneErrorCode.unauthorized.rawValue {
                needsLogin = true
            }
        }
        ToastCenter.shared.error(error)
        lastErrorMessage = (error as? APIError)?.message
    }

    private func extractMinFromMessage(_ msg: String) -> Int64? {
        // Server may embed min in message; client prefers structured field when available.
        _ = msg
        return nil
    }
}
