import SwiftUI

/// 代拍标识说明页：金牌 / 观察期 / 取消后的权益对照（DES-v1.3-05-01 §3 / §5.5 / §9）。
struct ProxyAgentBadgeView: View {
    let level: ProxyAssessmentLevel
    let badgeLabel: String
    let capabilities: ProxyCapabilities

    init(
        level: ProxyAssessmentLevel = .gold,
        badgeLabel: String? = nil,
        capabilities: ProxyCapabilities = .goldDefaults
    ) {
        self.level = level
        self.badgeLabel = badgeLabel ?? (level.buyerBadgeLabel ?? "个人卖家")
        self.capabilities = capabilities
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                hero
                fulfillmentCard
                privilegeMatrix
                notes
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle(ProxyAgentCopy.badgePageTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(badgeLabel)
                    .font(.vTitle(24))
                    .foregroundStyle(level == .gold ? Color(hex: 0x5C3B00) : Color.vText)
                Text("考核等级 · \(level.displayLabel)")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if level.showsGoldBadge {
                    Text("列表与详情展示固定文案「金牌代拍」，客户端不可自定义。")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                } else if level == .probation {
                    Text("观察期不展示金牌；专场与推荐位申请已关闭。")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                } else {
                    Text("资格已取消，买家侧按个人卖家卡渲染。")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
            }
        }
    }

    private var fulfillmentCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("履约责任").font(.vHeadline)
                Text(ProxyAgentCopy.fulfillmentResponsibility)
                    .font(.vBody)
                    .foregroundStyle(Color.vText)
                Text(ProxyAgentCopy.protocolSummary)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(ProxyAgentCopy.noConsignorSwitch)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    private var privilegeMatrix: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("当前权益").font(.vHeadline)
                ForEach(ProxyCapabilityKey.allCases, id: \.rawValue) { key in
                    HStack {
                        Text(key.title).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        Spacer()
                        let on = capabilities.allows(key)
                        Text(on ? "开" : "关")
                            .font(.vCaptionMedium)
                            .foregroundStyle(on ? Color.vGreen : Color.vTextTertiary)
                    }
                }
            }
        }
    }

    private var notes: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("说明").font(.vHeadline)
                Text("首页推荐与专场报名以服务端 capabilities 为准，客户端不可伪造金牌。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text("降级当月权益立即失效；在途订单继续由你本人发货售后。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }
}

/// Compact seller card chip used on listing detail (PXY-02).
struct ProxySellerCardView: View {
    let sellerId: Int64
    let badge: SellerBadge?
    let showFulfillment: Bool

    var body: some View {
        VCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("卖家").font(.vHeadline)
                    Text("卖家 #\(sellerId)")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    if let badge {
                        SellerBadgeChip(badge: badge)
                    }
                    if showFulfillment {
                        Text(ProxyAgentCopy.fulfillmentResponsibility)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
