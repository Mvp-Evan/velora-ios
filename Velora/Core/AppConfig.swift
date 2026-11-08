import Foundation

enum AppConfig {
    /// Bundle that supplies `APIBaseURL` / `WSBaseURL` (overridable in unit tests).
    static var infoBundle: Bundle = .main

    /// API host from Configs/*.xcconfig → Info.plist `APIBaseURL`. Falls back to localhost in DEBUG.
    static var baseURL: URL {
        if let raw = infoBundle.object(forInfoDictionaryKey: "APIBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        #if DEBUG
        return URL(string: "http://localhost:5052")!
        #else
        return URL(string: "https://api.example.com")!
        #endif
    }

    static var apiURL: URL { baseURL.appendingPathComponent("api/v1") }

    /// Merchant Web host from Info.plist `MerchantWebBaseURL` (DES-v1.3-06-04 / D26 deep link).
    /// Falls back to local merchant Vite (`http://localhost:5173`).
    static var merchantWebBaseURL: URL {
        if let raw = infoBundle.object(forInfoDictionaryKey: "MerchantWebBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return URL(string: PresaleSummaryConfigDefaults.defaultMerchantWebBaseURL)!
    }

    /// WebSocket URL from Info.plist `WSBaseURL`, else derived from `baseURL` (http→ws / https→wss) + `/ws`.
    static var wsURL: URL {
        if let raw = infoBundle.object(forInfoDictionaryKey: "WSBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                if url.path.isEmpty || url.path == "/" {
                    return url.appendingPathComponent("ws")
                }
                return url
            }
        }
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        c.path = "/ws"
        return c.url!
    }

    /// Feature flag stub `branding.paddock43`: when true, user-facing display name is「毂毂」(`Localizable` key `brand.name`).
    /// Remote flag wiring can replace this default later; keep engineering name Velora.
    /// `var` (not `let`) so unit tests can exercise the flag-off branch.
    static var brandingPaddock43 = true

    /// Resolved brand string for UI (About, nav title, etc.).
    static var brandDisplayName: String {
        brandingPaddock43
            ? String(localized: "brand.name", defaultValue: "毂毂")
            : "gugu"
    }

    /// 微信开放平台 AppID 与 Universal Link（接入微信支付时填写，并同步修改 Info.plist 的 URL Scheme）
    static let wechatAppID = ""
    static let wechatUniversalLink = ""
    /// 支付宝回跳 URL Scheme（需与 Info.plist 一致）
    static let alipayScheme = "velora-alipay"

    /// KYC return scheme (DES-v1.3-01-02 §5.1: `paddock43://kyc/return`)
    static let kycURLScheme = "paddock43"
}
