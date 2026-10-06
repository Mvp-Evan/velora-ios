# Velora iOS

赛车模型实时拍卖 App 的 iOS 客户端（SwiftUI · iOS 17+）。

对标闲鱼 / 卡淘体验：瀑布流发现、实时拍卖间、结拍付款、钱包与税务预留。

服务端仓库：[velora-server](https://github.com/Mvp-Evan/velora-server)

## 功能

- 手机号验证码登录（开发环境验证码固定 `123456`）
- 首页瀑布流 / 拍场 Tab / 搜索筛选
- 拍卖间：倒计时、快捷出价、WebSocket 实时出价流、截止前 2 分钟出价自动延时 2 分钟
- 发布拍品（最多 9 图、费用预估、草稿本地保存）
- 订单：收货地址、收银台（模拟支付 / 支付宝 / 微信预留）、发货与确认收货
- 钱包、提现、实名与税务中心（季度申报导出）
- 私信与拍卖通知

## 环境要求

- Xcode 16+（Swift 5.10）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- 运行中的 [velora-server](https://github.com/Mvp-Evan/velora-server)（默认 `http://localhost:5052`，服务端监听 `0.0.0.0:5052`）

## 快速开始

```bash
# 生成 Xcode 工程
xcodegen generate

# 用 Xcode 打开并运行到模拟器 / 真机
open Velora.xcodeproj
```

API 地址在 `Velora/Core/AppConfig.swift`：

```swift
static let baseURL = URL(string: "http://localhost:5052")!
```

模拟器访问本机服务端请保持上述 localhost；真机请改为电脑局域网 IP。

开发账号（需先对服务端执行 `make seed`）：

| 手机号 | 验证码 |
|--------|--------|
| 13800000001 – 13800000010 | 123456 |

## 项目结构

```
Velora/
├── App/                 # 入口、Root、TabBar
├── Core/                # 网络、鉴权、WebSocket、图片
├── DesignSystem/        # Token 与通用组件
├── Features/            # 业务页面
│   ├── Auth / Home / Discover / AuctionRoom
│   ├── Publish / Order / Wallet / Chat / Profile
├── Models/              # DTO
└── Resources/           # Info.plist、Assets
```

## 支付 SDK 接入

当前收银台默认可用 **模拟支付**（调用服务端 `POST /payments/:id/mock-confirm`）。

支付宝 / 微信支付的 iOS SDK 接入步骤、`Info.plist`、URL Scheme 与 Universal Link 配置见服务端文档：

- [docs/payments.md](https://github.com/Mvp-Evan/velora-server/blob/main/docs/payments.md)

客户端抽象：`Velora/Features/Order/PaymentService.swift`（`PaymentService` 协议 + Mock / Alipay / Wechat 实现；接入 SDK 后取消 `#if canImport` 注释即可）。

## License

Private / All rights reserved.
