import Foundation

/// API / WS endpoints from Info.plist keys (`APIBaseURL`, `WSBaseURL`). Kept in sync with `Velora/Core/AppConfig.swift`.
public enum AppConfig {
    public static var infoBundle: Bundle = .main

    public static var baseURL: URL {
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

    public static var apiURL: URL { baseURL.appendingPathComponent("api/v1") }

    /// Merchant Web host from Info.plist `MerchantWebBaseURL` (DES-v1.3-06-04 / D26).
    /// Falls back to local merchant Vite default.
    public static var merchantWebBaseURL: URL {
        if let raw = infoBundle.object(forInfoDictionaryKey: "MerchantWebBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return URL(string: PresaleSummaryConfigDefaults.defaultMerchantWebBaseURL)!
    }

    public static var wsURL: URL {
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
}
