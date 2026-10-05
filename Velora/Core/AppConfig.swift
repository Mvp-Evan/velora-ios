import Foundation

enum AppConfig {
    /// 模拟器可直接访问宿主机 localhost；真机请改为电脑局域网 IP，如 http://192.168.1.10:8080
    static let baseURL = URL(string: "http://localhost:8080")!
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
