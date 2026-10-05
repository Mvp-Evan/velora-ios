import SwiftUI

// MARK: - Price

struct VPriceText: View {
    let amount: Money
    var size: CGFloat = 20
    var color: Color = .vPrice
    var prefix: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let prefix { Text(prefix).font(.vCaption).foregroundStyle(Color.vTextSecondary) }
            Text("¥").font(.system(size: size * 0.6, weight: .bold, design: .rounded))
            Text(amount.displayNoSymbol).font(.vPrice(size))
        }
        .foregroundStyle(color)
        .contentTransition(.numericText())
    }
}

// MARK: - Tag chip

struct VTagChip: View {
    let text: String
    var tint: Color = .vTextSecondary
    var background: Color = .vFill
    var body: some View {
        Text(text)
            .font(.vMicro)
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
            .lineLimit(1)
    }
}

// MARK: - Status badge

struct VStatusBadge: View {
    let status: LotStatus
    var body: some View {
        HStack(spacing: 4) {
            if status == .live {
                Circle().fill(.white).frame(width: 5, height: 5)
                    .modifier(PulseModifier())
            }
            Text(status.label)
        }
        .font(.vMicro)
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color, in: Capsule())
    }
    private var color: Color {
        switch status {
        case .live: return .vPrimary
        case .scheduled: return .vBlue
        case .ended: return .vCarbon.opacity(0.75)
        case .unsold, .cancelled, .draft: return .vTextTertiary
        }
    }
}

struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Countdown

/// 全局 1s 时钟，供倒计时共享避免大量 Timer
@MainActor
final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published var now = Date()
    private var timer: Timer?
    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

struct VCountdown: View {
    let endAt: Date
    var status: LotStatus = .live
    var style: Style = .compact
    @ObservedObject private var ticker = Ticker.shared

    enum Style { case compact, large, inline }

    var body: some View {
        let remain = endAt.timeIntervalSince(ticker.now)
        let urgent = status == .live && remain > 0 && remain < 300
        switch style {
        case .compact:
            HStack(spacing: 3) {
                Image(systemName: status == .scheduled ? "clock" : "timer").font(.system(size: 9, weight: .bold))
                Text(label(remain)).font(.vMono(11))
            }
            .foregroundStyle(urgent ? Color.vPrimary : Color.vTextSecondary)
        case .inline:
            Text(label(remain)).font(.vMono(13)).foregroundStyle(urgent ? Color.vPrimary : Color.vText)
        case .large:
            VStack(alignment: .leading, spacing: 4) {
                Text(status == .scheduled ? "距开拍" : (remain > 0 ? "距结束" : "已结束"))
                    .font(.vCaption).foregroundStyle(.white.opacity(0.75))
                Text(remain > 0 ? endAt.countdownText(to: ticker.now) : "00:00:00")
                    .font(.vMono(22, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
    }

    private func label(_ remain: TimeInterval) -> String {
        if status == .scheduled { return "\(endAt.countdownText(to: ticker.now)) 后开拍" }
        if remain <= 0 { return "已结束" }
        return endAt.countdownText(to: ticker.now)
    }
}

// MARK: - Avatar

struct VAvatar: View {
    let url: String
    var size: CGFloat = 36
    var body: some View {
        RemoteImage(url)
            .frame(width: size, height: size)
            .background(Color.vFill)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.vSeparator, lineWidth: 0.5))
    }
}

// MARK: - Buttons

struct VPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var loading = false
    var disabled = false
    var style: Style = .filled
    var height: CGFloat = 48
    let action: () -> Void

    enum Style { case filled, outline, dark, soft }

    init(title: String, icon: String? = nil, style: Style = .filled, loading: Bool = false, disabled: Bool = false, height: CGFloat = 48, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.style = style; self.loading = loading; self.disabled = disabled; self.height = height; self.action = action
    }

    var body: some View {
        Button {
            Haptics.light(); action()
        } label: {
            HStack(spacing: 6) {
                if loading { ProgressView().tint(foreground) }
                else if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(.vHeadline)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: VRadius.l, style: .continuous).stroke(style == .outline ? Color.vPrimary : .clear, lineWidth: 1.2))
        }
        .disabled(disabled || loading)
        .opacity(disabled ? 0.45 : 1)
    }

    private var foreground: Color {
        switch style { case .filled, .dark: return .white; case .outline, .soft: return .vPrimary }
    }
    private var background: AnyShapeStyle {
        switch style {
        case .filled: return AnyShapeStyle(VGradient.brand)
        case .dark: return AnyShapeStyle(VGradient.carbon)
        case .outline: return AnyShapeStyle(Color.clear)
        case .soft: return AnyShapeStyle(Color.vPrimarySoft)
        }
    }
}

struct VIconButton: View {
    let system: String
    var size: CGFloat = 36
    var tint: Color = .vText
    var background: Color = .vSurface
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(background, in: Circle())
        }
    }
}

// MARK: - Card

struct VCard<Content: View>: View {
    var padding: CGFloat = VSpace.l
    var radius: CGFloat = VRadius.l
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct VSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionTitle = "查看全部"
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.vTitle(18)).foregroundStyle(Color.vText)
            if let subtitle { Text(subtitle).font(.vCaption).foregroundStyle(Color.vTextTertiary) }
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 2) { Text(actionTitle); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }
                        .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
            }
        }
    }
}

// MARK: - Skeleton

struct VSkeleton: View {
    var radius: CGFloat = 0
    @State private var phase: CGFloat = -1
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.vFill)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

struct VSkeletonLines: View {
    var lines = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { i in
                VSkeleton(radius: 4).frame(width: i == lines - 1 ? 120 : nil, height: 12)
            }
        }
    }
}

// MARK: - Empty / Error

struct VEmptyState: View {
    var icon = "tray"
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: VSpace.m) {
            ZStack {
                Circle().fill(Color.vFill).frame(width: 84, height: 84)
                Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Color.vTextTertiary)
            }
            Text(title).font(.vHeadline).foregroundStyle(Color.vText)
            if let message { Text(message).font(.vCaption).foregroundStyle(Color.vTextSecondary).multilineTextAlignment(.center) }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.vBodyMedium).foregroundStyle(Color.vPrimary)
                        .padding(.horizontal, 20).padding(.vertical, 9)
                        .background(Color.vPrimarySoft, in: Capsule())
                }.padding(.top, 4)
            }
        }
        .padding(VSpace.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Toast

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var kind: Kind = .info
    enum Kind { case info, success, error }
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var current: ToastItem?
    private var task: Task<Void, Never>?

    func show(_ text: String, _ kind: ToastItem.Kind = .info) {
        task?.cancel()
        withAnimation(.spring(duration: 0.35)) { current = ToastItem(text: text, kind: kind) }
        if kind == .error { Haptics.error() } else if kind == .success { Haptics.success() }
        task = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { current = nil }
        }
    }
    func error(_ e: Error) { show((e as? APIError)?.message ?? e.localizedDescription, .error) }
}

struct ToastOverlay: ViewModifier {
    @ObservedObject var center = ToastCenter.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let t = center.current {
                HStack(spacing: 8) {
                    Image(systemName: icon(t.kind)).font(.system(size: 14, weight: .semibold))
                    Text(t.text).font(.vBodyMedium).lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Color.vCarbon.opacity(0.92), in: Capsule())
                .vFloatingShadow()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(99)
            }
        }
    }
    private func icon(_ k: ToastItem.Kind) -> String {
        switch k { case .info: return "info.circle.fill"; case .success: return "checkmark.circle.fill"; case .error: return "exclamationmark.triangle.fill" }
    }
}

extension View { func toastHost() -> some View { modifier(ToastOverlay()) } }

// MARK: - Segmented tabs (underline style)

struct VSegmentedTabs<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var counts: [T: Int] = [:]
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(items, id: \.0) { item in
                    let selected = item.0 == selection
                    Button {
                        withAnimation(.spring(duration: 0.3)) { selection = item.0 }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Text(item.1).font(.system(size: selected ? 16 : 15, weight: selected ? .bold : .medium))
                                if let n = counts[item.0], n > 0 {
                                    Text("\(n)").font(.vMicro).foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.vPrimary, in: Capsule())
                                }
                            }
                            .foregroundStyle(selected ? Color.vText : Color.vTextSecondary)
                            ZStack {
                                Capsule().fill(.clear).frame(height: 3)
                                if selected {
                                    Capsule().fill(Color.vPrimary).frame(width: 18, height: 3)
                                        .matchedGeometryEffect(id: "tab", in: ns)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, VSpace.l)
        }
    }
}

/// 胶囊分段
struct VPillSegments<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    let on = item.0 == selection
                    Button { withAnimation(.easeOut(duration: 0.15)) { selection = item.0 } } label: {
                        Text(item.1)
                            .font(on ? .vCaptionMedium : .vCaption)
                            .foregroundStyle(on ? Color.vPrimary : Color.vTextSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(on ? Color.vPrimarySoft : Color.vFill, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, VSpace.l)
        }
    }
}

// MARK: - Image carousel

struct VImageCarousel: View {
    let images: [String]
    @Binding var index: Int
    var height: CGFloat = 360
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                    RemoteImage(url).tag(i).contentShape(Rectangle()).onTapGesture { onTap?() }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            .background(Color.vFill)

            if images.count > 1 {
                Text("\(index + 1)/\(images.count)")
                    .font(.vMono(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(12)
            }
        }
    }
}

// MARK: - Waterfall grid

/// 两列瀑布流（按累计高度分配列）
struct WaterfallGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var columns = 2
    var spacing: CGFloat = 10
    let height: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    private var distributed: [[Item]] {
        var cols = Array(repeating: [Item](), count: columns)
        var heights = Array(repeating: CGFloat(0), count: columns)
        for it in items {
            let i = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
            cols[i].append(it)
            heights[i] += height(it) + spacing
        }
        return cols
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(distributed.enumerated()), id: \.offset) { _, col in
                LazyVStack(spacing: spacing) {
                    ForEach(col) { content($0) }
                }
            }
        }
    }
}

// MARK: - Form rows

struct VFormRow<Content: View>: View {
    let title: String
    var required = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Text(title).font(.vBody).foregroundStyle(Color.vText)
                if required { Text("*").foregroundStyle(Color.vPrimary) }
            }
            .frame(width: 84, alignment: .leading)
            content()
        }
        .padding(.vertical, 13)
        .padding(.horizontal, VSpace.l)
    }
}

struct VNavRow: View {
    let icon: String
    var iconTint: Color = .vPrimary
    let title: String
    var value: String? = nil
    var badge: Int = 0
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 30, height: 30)
                .background(iconTint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.vBody).foregroundStyle(Color.vText)
            Spacer()
            if badge > 0 {
                Text("\(badge)").font(.vMicro).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.vPrimary, in: Capsule())
            }
            if let value { Text(value).font(.vCaption).foregroundStyle(Color.vTextTertiary) }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct VDivider: View {
    var inset: CGFloat = VSpace.l
    var body: some View { Rectangle().fill(Color.vSeparator).frame(height: 0.5).padding(.leading, inset) }
}

// MARK: - Key-value row

struct VKeyValue: View {
    let key: String
    let value: String
    var valueColor: Color = .vText
    var bold = false
    var body: some View {
        HStack {
            Text(key).font(.vBody).foregroundStyle(Color.vTextSecondary)
            Spacer()
            Text(value).font(bold ? .vHeadline : .vBody).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Loading overlay

struct VLoadingView: View {
    var text = "加载中…"
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color.vPrimary)
            Text(text).font(.vCaption).foregroundStyle(Color.vTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

struct VErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VEmptyState(icon: "wifi.exclamationmark", title: "加载失败", message: message, actionTitle: "重试", action: retry)
    }
}
