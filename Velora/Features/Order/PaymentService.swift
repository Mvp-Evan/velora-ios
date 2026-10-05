import Foundation
import UIKit

// 接入真实 SDK 时，在 project.yml 中添加依赖并取消注释：
// #if canImport(AlipaySDK)
// import AlipaySDK
// #endif
// #if canImport(WechatOpenSDK)
// import WechatOpenSDK
// #endif

/// 客户端支付结果（仅代表 SDK 侧结果，最终以服务端 GET /payments/:id 为准）
enum PaymentLaunchResult { case launched, completed, cancelled, failed(String), unavailable }

/// 支付渠道协议：拿到服务端 `client_payload` 后拉起 SDK
protocol PaymentService {
    var provider: String { get }
    var isAvailable: Bool { get }
    func launch(payment: Payment) async -> PaymentLaunchResult
}

/// 支付回调路由：支付宝 URL Scheme / 微信 Universal Link
enum PaymentCallbackRouter {
    static var onAlipayResult: (([AnyHashable: Any]) -> Void)?
    static var onWechatResult: ((Int, String) -> Void)?

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        if url.scheme == AppConfig.alipayScheme {
            // #if canImport(AlipaySDK)
            // AlipaySDK.defaultService().processOrder(withPaymentResult: url) { result in onAlipayResult?(result ?? [:]) }
            // #endif
            onAlipayResult?(["resultStatus": "9000"])
            return true
        }
        if url.host == URL(string: AppConfig.wechatUniversalLink)?.host, !AppConfig.wechatUniversalLink.isEmpty {
            // #if canImport(WechatOpenSDK)
            // return WXApi.handleOpenUniversalLink(userActivity, delegate: WechatDelegate.shared)
            // #endif
            return true
        }
        return false
    }
}

enum PaymentServiceRegistry {
    static let all: [PaymentService] = [MockPaymentService(), AlipayPaymentService(), WechatPaymentService()]

    static func service(for provider: String) -> PaymentService? { all.first { $0.provider == provider } }

    /// App 启动时注册 SDK
    static func registerSDKs() {
        // #if canImport(WechatOpenSDK)
        // WXApi.registerApp(AppConfig.wechatAppID, universalLink: AppConfig.wechatUniversalLink)
        // #endif
    }
}

// MARK: - Mock（开发环境：服务端 /payments/:id/mock-confirm）

struct MockPaymentService: PaymentService {
    let provider = "mock"
    var isAvailable: Bool { true }

    func launch(payment: Payment) async -> PaymentLaunchResult {
        // 模拟收银台延迟，再调用服务端确认接口
        try? await Task.sleep(for: .milliseconds(800))
        do {
            _ = try await API.mockConfirm(payment.id, success: true)
            return .completed
        } catch {
            return .failed((error as? APIError)?.message ?? "模拟支付失败")
        }
    }
}

// MARK: - 支付宝 App 支付

/// 接入步骤见 velora-server/docs/payments.md：
/// 1. pod 'AlipaySDK-iOS' 或 SPM 引入；2. Info.plist 配置 URL Scheme（AppConfig.alipayScheme）及 LSApplicationQueriesSchemes；
/// 3. 服务端返回 client_payload.order_string；4. 调用 AlipaySDK.payOrder；5. 回调后以 GET /payments/:id 查询为准。
struct AlipayPaymentService: PaymentService {
    let provider = "alipay"

    var isAvailable: Bool {
        #if canImport(AlipaySDK)
        return true
        #else
        return false
        #endif
    }

    func launch(payment: Payment) async -> PaymentLaunchResult {
        guard let orderString = payment.clientPayload?["order_string"]?.value as? String, !orderString.isEmpty else {
            return .failed("支付参数缺失")
        }
        #if canImport(AlipaySDK)
        return await withCheckedContinuation { cont in
            var resumed = false
            PaymentCallbackRouter.onAlipayResult = { result in
                guard !resumed else { return }; resumed = true
                let status = result["resultStatus"] as? String ?? ""
                switch status {
                case "9000": cont.resume(returning: .completed)
                case "8000", "6004": cont.resume(returning: .launched) // 处理中，轮询服务端
                case "6001": cont.resume(returning: .cancelled)
                default: cont.resume(returning: .failed("支付失败(\(status))"))
                }
            }
            AlipaySDK.defaultService().payOrder(orderString, fromScheme: AppConfig.alipayScheme) { result in
                PaymentCallbackRouter.onAlipayResult?(result ?? [:])
            }
        }
        #else
        _ = orderString
        return .unavailable
        #endif
    }
}

// MARK: - 微信 App 支付

/// 接入步骤：1. 引入 WechatOpenSDK；2. 配置 Universal Link 与 URL Scheme（wx 开头的 AppID）；
/// 3. 服务端返回 client_payload{partner_id, prepay_id, nonce_str, timestamp, package, sign}；4. WXApi.send(PayReq)；
/// 5. WXApiDelegate.onResp 回调后以 GET /payments/:id 查询为准。
struct WechatPaymentService: PaymentService {
    let provider = "wechatpay"

    var isAvailable: Bool {
        #if canImport(WechatOpenSDK)
        return WXApi.isWXAppInstalled()
        #else
        return false
        #endif
    }

    func launch(payment: Payment) async -> PaymentLaunchResult {
        guard let p = payment.clientPayload, let prepay = p["prepay_id"]?.value as? String, !prepay.isEmpty else {
            return .failed("支付参数缺失")
        }
        #if canImport(WechatOpenSDK)
        let req = PayReq()
        req.partnerId = p["partner_id"]?.value as? String ?? ""
        req.prepayId = prepay
        req.nonceStr = p["nonce_str"]?.value as? String ?? ""
        req.timeStamp = UInt32(p["timestamp"]?.value as? String ?? "") ?? 0
        req.package = p["package"]?.value as? String ?? "Sign=WXPay"
        req.sign = p["sign"]?.value as? String ?? ""
        return await withCheckedContinuation { cont in
            var resumed = false
            PaymentCallbackRouter.onWechatResult = { code, msg in
                guard !resumed else { return }; resumed = true
                switch code {
                case 0: cont.resume(returning: .completed)
                case -2: cont.resume(returning: .cancelled)
                default: cont.resume(returning: .failed(msg))
                }
            }
            WXApi.send(req) { ok in if !ok { PaymentCallbackRouter.onWechatResult?(-1, "无法拉起微信") } }
        }
        #else
        return .unavailable
        #endif
    }
}
