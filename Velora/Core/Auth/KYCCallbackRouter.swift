import Foundation

/// Routes KYC return deep links (`paddock43://kyc/return` / Universal Link `/kyc/return/{channel}`).
@MainActor
enum KYCCallbackRouter {
    static var onReturn: ((KYCReturnPayload) -> Void)?

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let payload = KYCReturnPayload.parse(url: url) else { return false }
        onReturn?(payload)
        NotificationCenter.default.post(name: .kycReturn, object: payload)
        return true
    }
}

extension Notification.Name {
    static let kycReturn = Notification.Name("velora.kyc.return")
}
