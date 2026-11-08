# Velora iOS

赛车模型实时拍卖 App 的 iOS 客户端（SwiftUI · iOS 17+）。

对标闲鱼 / 卡淘体验：瀑布流发现、实时拍卖间、结拍付款、钱包与税务预留。

服务端仓库：[velora-server](https://github.com/Mvp-Evan/velora-server)

工程名 **Velora**；用户可见品牌「毂毂」（String Catalog `brand.name`，灰度 stub `AppConfig.brandingPaddock43` / `branding.paddock43`）。

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
# 生成 Xcode 工程（含 Velora / VeloraTests / VeloraUITests）
xcodegen generate

# 用 Xcode 打开并运行到模拟器 / 真机
open Velora.xcodeproj
```

### 配置（Debug / Staging / Release）

API / WS 地址由 `Configs/*.xcconfig` 注入 Info.plist（`APIBaseURL`、`WSBaseURL`），`AppConfig` 读取 Bundle；DEBUG 下若缺失则回退 `http://localhost:5052`。当前 Debug 默认指向临时测试服 `47.98.250.121`。

| Config | API | WS |
|--------|-----|----|
| Debug | `http://47.98.250.121`（临时测试服） | `ws://47.98.250.121` |
| Staging | `https://api.example.com`（占位） | `wss://api.example.com` |
| Release | `https://api.example.com`（占位） | `wss://api.example.com` |

本地联调：把 `Configs/Debug.xcconfig` 改回 `localhost:5052`（或电脑局域网 IP）。改完 xcconfig 后 Clean Build。

### ATS（App Transport Security）

- 保留 `NSAllowsLocalNetworking`、`localhost` 与临时测试 IP `47.98.250.121` 的 insecure HTTP 例外（Debug 联调）。
- Staging / Release 必须使用 **HTTPS / WSS**；切勿把 Release 的 `API_BASE_URL` 设成 `http://`。

### 测试目标

```bash
# VeloraCore 纯 Swift 包（模型 / 钱包归一化，不依赖 Xcode 模拟器）
cd Packages/VeloraCore && swift test

# App 单元测试（需已接受 Xcode 许可协议）
xcodebuild test -scheme Velora -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VeloraTests

# UI smoke（启动窗口；环境异常时可 XCTSkip）
xcodebuild test -scheme Velora -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VeloraUITests
```

若 `swift test` / `xcodebuild` 提示未接受 Xcode 许可，在本机执行 `sudo xcodebuild -license` 后重试。

#### 测试矩阵（品牌 毂毂）

| 目标 | 位置 | 说明 |
|------|------|------|
| VeloraCore | `Packages/VeloraCore/Tests` | 钱包渠道提现状态（legacy `rejected`→`failed`、未知枚举→nil）、`WalletCopy` 托管文案含「毂毂」、分账/进件状态机、发票/社区品牌常量 |
| VeloraTests | `VeloraTests/` | `AppConfig.brandDisplayName` 旗标开→「毂毂」/关→`gugu`、`WalletErrorNormalizeTests`（无 `payout_account_required`） |
| VeloraUITests | `VeloraUITests/` | 启动 smoke；`WalletBidFlowUITests` 登录→钱包/出价（无 accessibility ID 时 XCTSkip） |

- `VeloraTests` — `MoneyFormattingTests`、`EnvelopeDecodingTests`、`IdempotencyKeyTests`、`AppConfigTests`（含 brand 分支）
- `VeloraUITests` — `testLaunchSmoke`、`testLoginNavigateToWalletSmoke`、`testLoginNavigateToBidSmoke`

**遗留：** 本机需先 `sudo xcodebuild -license` 才能跑 `swift test` / `xcodebuild`；Wallet/KYC/LotDetail ViewModel 抽取与 FakeAPI 注入、UI accessibility ID 与 mock 登录 harness 尚未接线。

写接口（POST/PUT/PATCH/DELETE）由 `APIClient` 自动附加 `Idempotency-Key`（UUID）；可用 `APIClient.shared.idempotencyKey()` 自行生成。

开发账号（需先对服务端执行 `make seed`）：

| 手机号 | 验证码 |
|--------|--------|
| 13800000001 – 13800000010 | 123456 |

## 项目结构

```
Configs/                 # Debug / Staging / Release.xcconfig
Velora/
├── App/                 # 入口、Root、TabBar
├── Core/                # 网络、鉴权、WebSocket、图片、AppConfig
├── DesignSystem/        # Token 与通用组件
├── Features/            # 业务页面
│   ├── Auth / Home / Discover / AuctionRoom
│   ├── Publish / Order / Wallet / Chat / Profile
├── Models/              # DTO
└── Resources/           # Info.plist、Assets、Localizable.xcstrings
VeloraTests/             # 单元测试 + Fixtures
VeloraUITests/           # UI smoke
```

## 支付 SDK 接入

当前收银台默认可用 **模拟支付**（调用服务端 `POST /payments/:id/mock-confirm`）。

支付宝 / 微信支付的 iOS SDK 接入步骤、`Info.plist`、URL Scheme 与 Universal Link 配置见服务端文档：

- [docs/payments.md](https://github.com/Mvp-Evan/velora-server/blob/main/docs/payments.md)

客户端抽象：`Velora/Features/Order/PaymentService.swift`（`PaymentService` 协议 + Mock / Alipay / Wechat 实现；接入 SDK 后取消 `#if canImport` 注释即可）。

## License

Private / All rights reserved.
