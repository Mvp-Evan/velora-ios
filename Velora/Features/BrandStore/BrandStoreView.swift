import SwiftUI

/// 品牌店铺主页：店招 → 标识/店名 → 关注 → 公告 → 在售 → 日历 → 介绍（DES-v1.3-05-03 §5.2 / §5.8）。
struct BrandStoreView: View {
    let brandId: Int64
    @StateObject private var model: BrandStoreModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore
    @State private var showReport = false
    @State private var showBlockConfirm = false

    init(brandId: Int64) {
        self.brandId = brandId
        _model = StateObject(wrappedValue: BrandStoreModel(brandId: brandId))
    }

    private var reportTargetId: Int64 {
        model.store?.sellerId ?? brandId
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                storeSkeleton
            case .failed(let message):
                VErrorView(message: message) { Task { await model.load() } }
            case .loaded:
                if let store = model.store {
                    storeScroll(store)
                } else {
                    VEmptyState(icon: "storefront", title: "店铺不存在", message: "该品牌店铺暂不可用")
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(model.store?.storeName ?? BrandStoreCopy.storeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.store == nil { await model.load() } }
        .refreshable { await model.load() }
        .confirmationDialog(
            BrandStoreCopy.unfollowConfirm,
            isPresented: $model.showUnfollowConfirm,
            titleVisibility: .visible
        ) {
            Button(BrandStoreCopy.unfollow, role: .destructive) {
                Task { await model.confirmUnfollow() }
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                router.showLogin = true
                model.needsLogin = false
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheetView(
                targetType: .user,
                targetId: reportTargetId,
                peerName: model.store?.storeName
            )
        }
        .confirmationDialog(
            RiskCopy.blockConfirmTitle,
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(RiskCopy.blockAction, role: .destructive) {
                Task { _ = await BlockUserAction.block(userId: reportTargetId) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(RiskCopy.blockConfirmMessage)
        }
    }

    // MARK: - Sections (§5.8 order)

    private func storeScroll(_ store: BrandStorePage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner(store)
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if store.isFrozen {
                        frozenBanner
                    }
                    identity(store)
                    followRow(store)
                    if store.showsVipStrip, let vip = store.viewerVip {
                        vipStrip(vip)
                    }
                    // Guests: viewer_vip absent → no strip (DES-v1.3-05-04 §5.4).
                    announcement(store)
                    onSale(store)
                    calendar(store)
                    intro(store)
                    footer
                }
                .padding(.horizontal, VSpace.l)
                .padding(.top, VSpace.l)
                .padding(.bottom, VSpace.xl)
            }
        }
    }

    private func banner(_ store: BrandStorePage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = store.banner, !url.isEmpty {
                    RemoteImage(url)
                } else {
                    LinearGradient(
                        colors: [Color.vBlue.opacity(0.85), Color.vCarbon.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 168)
            .frame(maxWidth: .infinity)
            .clipped()

            if let logo = store.logo, !logo.isEmpty {
                RemoteImage(logo)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    )
                    .padding(VSpace.l)
            }
        }
    }

    private func identity(_ store: BrandStorePage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let label = store.officialBadgeLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.vBlue, in: Capsule())
                        .accessibilityLabel(label)
                }
                Text(store.storeName.isEmpty ? BrandStoreCopy.storeTitle : store.storeName)
                    .font(.vTitle(22))
                    .foregroundStyle(Color.vText)
                Spacer(minLength: 0)
            }
            if let count = store.followerCount {
                Text(BrandStoreCopy.followerCountLabel(count))
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private func followRow(_ store: BrandStorePage) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.toggleFollow() }
            } label: {
                HStack(spacing: 6) {
                    if model.followingBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: store.viewerFollowing == true ? "bell.fill" : "bell")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(store.followTitle)
                        .font(.vBodyMedium)
                }
                .foregroundStyle(store.viewerFollowing == true ? Color.vPrimary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    store.viewerFollowing == true
                        ? AnyShapeStyle(Color.vPrimary.opacity(0.12))
                        : AnyShapeStyle(VGradient.brand),
                    in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                )
                .overlay {
                    if store.viewerFollowing == true {
                        RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                            .stroke(Color.vPrimary.opacity(0.35), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.followingBusy)
        }
    }

    /// Brand loyalty strip only — never a platform VIP paywall (DES-v1.3-05-04 §5.4 / §5.6).
    private func vipStrip(_ vip: BrandViewerVIP) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: vip.stripMode == .nonMemberCTA ? "crown" : "crown.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vGold)
                Text(vip.stripPrimaryText)
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vText)
                Spacer(minLength: 0)
            }
            if vip.stripMode == .member, let distance = vip.distance, distance.remainingFen > 0 {
                Text(distance.progressCopy)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
        .padding(12)
        .background(Color.vGold.opacity(0.12), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            vip.stripMode == .nonMemberCTA
                ? BrandVIPCopy.stripAccessibilityCTA
                : BrandVIPCopy.stripAccessibilityMember
        )
        .accessibilityValue(vip.stripPrimaryText)
    }

    private var frozenBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.vGold)
            Text(BrandStoreCopy.frozenBanner)
                .font(.vCaption)
                .foregroundStyle(Color.vText)
            Spacer()
        }
        .padding(12)
        .background(Color.vGold.opacity(0.15), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private func announcement(_ store: BrandStorePage) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("公告").font(.vHeadline)
                if let text = store.announcement, !text.isEmpty {
                    Text(text)
                        .font(.vBody)
                        .foregroundStyle(Color.vText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(BrandStoreCopy.announcementEmpty)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func onSale(_ store: BrandStorePage) -> some View {
        let items = store.onSaleItems.filter(\.isStoreOnSaleVisible)
        return VStack(alignment: .leading, spacing: VSpace.m) {
            HStack {
                Text("在售").font(.vHeadline)
                Spacer()
                if let n = store.onSaleCount ?? (items.isEmpty ? nil : items.count) {
                    Text("\(n) 件").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
            }
            if items.isEmpty {
                Text(BrandStoreCopy.onSaleEmpty)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        NavigationLink {
                            ListingDetailView(listingId: item.listingId)
                        } label: {
                            onSaleCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func onSaleCard(_ item: BrandOnSaleItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(item.cover ?? "")
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let price = item.price {
                    VPriceText(amount: price, size: 16)
                }
            }
            .padding(8)
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func calendar(_ store: BrandStorePage) -> some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            Text("发售日历").font(.vHeadline)
            let releases = model.calendar.isEmpty ? store.upcomingReleases : model.calendar
            if releases.isEmpty {
                Text(BrandStoreCopy.calendarEmpty)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                let grouped = BrandReleaseCalendarResponse(items: releases).groupedByDay()
                VStack(spacing: VSpace.m) {
                    ForEach(grouped, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayLabel(group.day))
                                .font(.vCaptionMedium)
                                .foregroundStyle(Color.vTextSecondary)
                            ForEach(group.releases) { release in
                                calendarRow(release)
                            }
                        }
                    }
                }
            }
        }
    }

    private func calendarRow(_ release: BrandUpcomingRelease) -> some View {
        NavigationLink {
            switch (release.releaseMode ?? "").lowercased() {
            case "lottery":
                LotteryEnrollView(releaseId: release.id)
            case "presale":
                PresaleDepositView(releaseId: release.id)
            default:
                SpotReleaseDetailView(releaseId: release.id)
            }
        } label: {
            HStack(spacing: 12) {
                RemoteImage(release.cover ?? "")
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(release.displayTitle)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(release.modeLabel)
                            .font(.vMicro)
                            .foregroundStyle(Color.vBlue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.vBlue.opacity(0.12), in: Capsule())
                        if let at = release.startAt {
                            Text(timeLabel(at))
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vTextTertiary)
            }
            .padding(10)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func intro(_ store: BrandStorePage) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("品牌介绍").font(.vHeadline)
                if let text = store.intro, !text.isEmpty {
                    Text(text)
                        .font(.vBody)
                        .foregroundStyle(Color.vTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(BrandStoreCopy.introEmpty)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                ToastCenter.shared.show("客服入口即将开放", .info)
            } label: {
                Label(BrandStoreCopy.customerService, systemImage: "bubble.left.and.bubble.right")
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                guard session.isLoggedIn else {
                    router.showLogin = true
                    return
                }
                showReport = true
            } label: {
                Label(BrandStoreCopy.report, systemImage: "exclamationmark.bubble")
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(RiskCopy.blockAction, role: .destructive) {
                    guard session.isLoggedIn else {
                        router.showLogin = true
                        return
                    }
                    showBlockConfirm = true
                }
            }
        }
    }

    private var storeSkeleton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.vFill)
                .frame(height: 168)
                .redacted(reason: .placeholder)
            VStack(alignment: .leading, spacing: VSpace.m) {
                RoundedRectangle(cornerRadius: 6).fill(Color.vFill).frame(height: 24).frame(width: 160)
                RoundedRectangle(cornerRadius: 6).fill(Color.vFill).frame(height: 44)
                RoundedRectangle(cornerRadius: 6).fill(Color.vFill).frame(height: 80)
                Spacer()
            }
            .padding(VSpace.l)
            .redacted(reason: .placeholder)
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = BrandStoreValidation.shanghaiTimeZone()
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: day)
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = BrandStoreValidation.shanghaiTimeZone()
        f.dateFormat = "HH:mm"
        return f.string(from: date) + "（服务器时间）"
    }
}
