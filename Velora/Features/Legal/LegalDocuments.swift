import SwiftUI

/// 客户端静态法律/说明文档（随 App 版本发布，非律师意见）
enum LegalDocument: String, Identifiable, CaseIterable {
    case appGuide
    case auctionRules
    case disclaimer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appGuide: return "Velora 使用说明书"
        case .auctionRules: return "拍卖规则说明书"
        case .disclaimer: return "免责声明"
        }
    }

    var navTitle: String {
        switch self {
        case .appGuide: return "使用说明"
        case .auctionRules: return "拍卖规则"
        case .disclaimer: return "免责声明"
        }
    }

    var icon: String {
        switch self {
        case .appGuide: return "book"
        case .auctionRules: return "flag.checkered"
        case .disclaimer: return "exclamationmark.shield"
        }
    }

    var sections: [(heading: String, body: String)] {
        switch self {
        case .appGuide: return Self.guide
        case .auctionRules: return Self.rules
        case .disclaimer: return Self.disclaimerText
        }
    }

    private static let guide: [(String, String)] = [
        ("关于本说明", "本说明书介绍 Velora 赛车模型实时拍卖 App 的主要功能。具体以当前版本界面与服务端规则为准；费用、订单金额以订单快照为准。"),
        ("注册与登录", "使用中国大陆手机号获取验证码登录。首次登录将自动注册账号。请妥善保管账号，勿将验证码告知他人。开发环境验证码可能固定，正式环境以短信为准。"),
        ("浏览与搜索", "首页展示正在竞拍与即将结拍的拍品；「拍场」按进行中 / 即将开始 / 已结束浏览。可通过关键词、品牌、比例、成色与价格筛选。点进拍品进入拍卖间查看图片、参数与实时出价。"),
        ("关注与开拍提醒", "对预展或竞拍中的拍品可点「关注」或「开拍提醒」。开拍、被超越、拍中、成交等事件会通过站内通知提示，登录后请保持网络畅通以便接收 WebSocket 推送。"),
        ("如何出价", "仅「竞拍中」的拍品可出价。卖家不能对自己的拍品出价；当前领先者不能连续加价，需被他人超越后才能再出。可使用底部「最低出价 / 加价」或「自定义出价」。出价一经确认不可撤回。截止前 2 分钟内如有出价，拍卖自动延时 2 分钟。"),
        ("结拍与付款", "拍卖结束后，若有有效领先且达到保留价（如有），系统为赢家生成订单。买家出价前须缴纳卖家设定的竞拍押金；未中标全额退回，拍中可抵扣货款。买家须在 24 小时内完成尾款支付，逾期未付将按规则从押金中扣除部分金额（平台抽成 + 卖家入账并依法报税）。货款支付后资金记账冻结在平台，买家确认收货后结算至卖家钱包。"),
        ("发货与收货", "买家付款后，卖家应在 48 小时内填写物流并发货。买家确认收货后，货款扣除平台服务费后进入卖家钱包（冻结款转为可提现）。请先验货再确认，确认后视为交易完成。"),
        ("发布拍品", "登录后点底部「发布」，上传最多 9 张图片，填写标题、分类与拍卖参数（起拍价、加价幅度、时长、开拍时间）。防狙击为平台统一规则，卖家不可关闭。建议如实描述成色、包装与瑕疵。"),
        ("消息与咨询", "在拍品页点「咨询」可与卖家私信，沟通细节、附件与发货方式。聊天记录仅供双方参考，不构成平台对成色或真伪的保证。"),
        ("钱包与提现", "「我的钱包」展示可用余额、在途货款与收支明细。买家确认收货后货款入账可用余额，可申请提现至银行卡，经平台审核后到账。"),
        ("实名与税务", "卖出拍品产生的收入可能涉及个人所得税等纳税义务。请在「实名与税务」完善信息。平台按中国税法预留申报能力，具体申报以税务机关要求为准。"),
        ("更多入口", "完整拍卖规则、免责声明可在登录页、「我的」设置、关于页、拍卖间与发布页查看。"),
    ]

    private static let rules: [(String, String)] = [
        ("适用范围", "Velora 仅提供赛车模型及相关收藏品的实时拍卖，不提供一口价二手交易。参与浏览、出价、发布即视为知悉并同意本规则。本规则与订单快照冲突时，以订单生成时的快照为准。"),
        ("拍品与状态", "拍品由卖家发布。预展中（scheduled）不可出价；竞拍中（live）可出价；结束后为已结拍（ended，生成订单）或流拍（unsold）。卖家仅可在尚无出价时撤拍。"),
        ("出价规则", "首拍不得低于起拍价；此后每次出价不得低于当前价加加价幅度。卖家不得对自己的拍品出价。当前最高出价者不得连续加价，须待他人超越后才可再出。出价成功后不可撤销。"),
        ("保留价", "卖家可设置保留价（不低于起拍价）。结拍时若最高价未达保留价，拍品流拍、不生成订单。保留价具体金额不对买家展示，拍卖间仅提示是否已达保留价。"),
        ("防狙击延时（平台规则）", "距拍卖结束不足 2 分钟时，如有用户成功出价，结束时间自动延后 2 分钟，可多次触发。倒计时、拍卖间提示与站内通知会展示新的结束时间。该规则由平台统一执行，卖家不可关闭或修改。"),
        ("结拍与成交", "到达结束时间后，若存在有效领先且满足保留价条件，领先者成为赢家并生成订单；否则流拍。成交价为最后有效出价。"),
        ("付款时限", "买家须在订单生成后 24 小时内完成付款。逾期未付，订单自动取消，可能影响信用分。请在截止时间前完成支付，勿重复下单支付。"),
        ("发货与确认收货", "卖家应在买家付款后 48 小时内发货并填写真实物流单号。买家确认收货后，平台结算货款：卖家到手 = 成交价 − 平台服务费（及规则载明的其他扣减）。"),
        ("平台服务费与税务", "买家默认不支付佣金，应付金额一般为成交价。卖家按成交价支付平台服务费，费率以费用估算与订单快照为准。卖家收入可能需依法纳税，平台预留报税能力，不替代纳税人申报义务。"),
        ("流拍与重新上拍", "无人出价、未达保留价或赢家逾期未付导致流拍后，卖家可以调整参数后重新发布。已成交订单按订单规则履行，不适用重新上拍。"),
        ("禁止事项", "禁止发布违法违规、侵权或与赛车模型交易无关的物品；禁止恶意抬价、串通拍卖、虚假描述。平台有权取消违规拍品或限制账号。"),
        ("规则修订", "平台可更新本规则，更新后在 App 内公示。继续使用即视为接受修订后的规则。"),
    ]

    private static let disclaimerText: [(String, String)] = [
        ("声明性质", "本免责声明是 Velora 用户使用本服务的前提。Velora 是拍卖信息与撮合平台，不是拍品的卖方，也不对模型真伪、成色、附件完整性作鉴定或担保。正文不构成法律意见。"),
        ("交易风险", "拍品由卖家自行描述与交付。买家应通过图片、参数与私信自行判断。因描述不实、隐藏瑕疵、包装破损、物流损毁等产生的争议，应由买卖双方协商或依法解决，平台可提供订单与聊天记录协助，但不承担先行赔付义务（法律另有规定的除外）。"),
        ("出价与订单", "出价确认后不可撤销。拍中即负有在时限内付款的义务。逾期未付导致订单取消的，损失由买家自行承担。卖家未按时发货或物流信息不实的，买家可与卖家协商，平台可依规则处理订单。"),
        ("支付与资金", "支付由支付宝、微信支付等第三方或开发环境的模拟通道完成。Velora 不保存支付密码。因第三方通道、银行或网络故障导致的到账延迟、失败，平台将协助查询，但不保证即时到账。钱包余额提现需审核，到账时间以银行处理为准。"),
        ("税费", "用户应就其在平台的销售收入自行判断纳税义务并依法申报、缴纳。平台预留的税务信息与季度汇总仅为协助记录，不构成完税证明或税务代理。"),
        ("服务中断", "因维护、不可抗力、网络或第三方故障导致拍卖延时展示、通知延迟或暂时不可用的，平台将在合理范围内恢复服务，但不就间接损失承担责任。"),
        ("账号与内容", "用户对其发布的文字、图片与言论负责，不得侵害他人知识产权或人格权。平台有权删除违法违规内容并限制账号。"),
        ("适用", "使用本 App 即视为已阅读并同意本声明、使用说明书与拍卖规则。如不同意，请停止使用。争议适用中华人民共和国法律，由平台运营方所在地有管辖权的人民法院管辖（法律另有规定的除外）。"),
    ]
}

struct LegalDocumentView: View {
    let document: LegalDocument
    var showDone = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if showDone {
                NavigationStack { documentBody }
            } else {
                documentBody
            }
        }
    }

    private var documentBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                HStack(spacing: 10) {
                    Image(systemName: document.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.vPrimary)
                    Text(document.title).font(.vTitle(20))
                }
                Text("以实际功能与订单快照为准 · 版本 0.1.0")
                    .font(.vMicro).foregroundStyle(Color.vTextTertiary)

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading).font(.vHeadline)
                        Text(section.body).font(.vBody).foregroundStyle(Color.vTextSecondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(VSpace.l)
            .padding(.bottom, showDone ? 80 : 24)
        }
        .background(Color.vBackground)
        .navigationTitle(document.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showDone {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showDone {
                VPrimaryButton(title: "我已了解") { dismiss() }
                    .padding(VSpace.l)
                    .background(Color.vSurface.overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
            }
        }
    }
}
