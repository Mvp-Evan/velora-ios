import Foundation

enum AppConfig {
    /// 生产服务器；本地调试可改回 http://localhost:5052
    static let baseURL = URL(string: "http://47.98.250.121")!
    static var apiURL: URL { baseURL.appendingPathComponent("api/v1") }
    static var wsURL: URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        c.path = "/ws"
        return c.url!
    }

    /// 微信开放平台 AppID 与 Universal Link（接入微信支付时填写，并同步修改 Info.plist 的 URL Scheme）
    static let wechatAppID = ""
    static let wechatUniversalLink = ""
    /// 支付宝回跳 URL Scheme（需与 Info.plist 一致）
    static let alipayScheme = "velora-alipay"
}
