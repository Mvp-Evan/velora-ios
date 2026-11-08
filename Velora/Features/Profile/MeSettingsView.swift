import SwiftUI

/// Settings hub (DES-v1.3-12-01 ME-07 / D39): 实名、地址、推送、黑名单、协议、资质、注销、足迹开关.
struct MeSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter

    @State private var settings: MeSettingsResponse?
    @State private var state: LoadState = .idle
    @State private var savingHistory = false
    @State private var showDeletion = false

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load() } }
            case .loaded:
                form
            }
        }
        .background(Color.vBackground)
        .navigationTitle(MeCopy.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showDeletion) { AccountDeletionView() }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                accountCard
                privacyCard
                legalCard
                if session.isLoggedIn {
                    dangerCard
                }
            }
            .padding(VSpace.l)
            .padding(.bottom, 40)
        }
    }

    private var accountCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { RealNameView() } label: {
                    VNavRow(
                        icon: "checkmark.shield",
                        iconTint: .vGreen,
                        title: MeCopy.realNameTitle,
                        value: settings?.realName?.summaryLabel ?? MeCopy.realNameUnset
                    )
                }
                VDivider(inset: 58)
                NavigationLink { AddressListView() } label: {
                    VNavRow(icon: "mappin.and.ellipse", iconTint: .vGreen, title: MeCopy.addressTitle)
                }
                VDivider(inset: 58)
                NavigationLink { PushSettingsView() } label: {
                    VNavRow(icon: "bell.badge", iconTint: .vPrimary, title: MeCopy.pushSettingsTitle)
                }
                VDivider(inset: 58)
                NavigationLink { BlockListView() } label: {
                    VNavRow(icon: "hand.raised", iconTint: .vPrimary, title: MeCopy.blacklistTitle)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var privacyCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { settings?.saveBrowseHistory ?? true },
                    set: { newValue in Task { await setSaveHistory(newValue) } }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MeCopy.saveBrowseHistory).font(.vBody)
                        if settings?.saveBrowseHistory == false {
                            Text(MeCopy.historySaveOffHint)
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .disabled(savingHistory || !session.isLoggedIn)
                .tint(Color.vPrimary)

                VDivider(inset: 16)
                NavigationLink { BrowseHistoryView() } label: {
                    VNavRow(icon: "clock", iconTint: .vBlue, title: MeCopy.historyTitle)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var legalCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(protocolRows) { row in
                    NavigationLink {
                        MeProtocolDetailView(sign: row)
                    } label: {
                        VNavRow(
                            icon: row.protocolCode.lowercased().contains("privacy") ? "hand.raised.square" : "doc.plaintext",
                            iconTint: .vBlue,
                            title: row.displayTitle,
                            value: row.version.isEmpty ? nil : "v\(row.version)"
                        )
                    }
                    VDivider(inset: 58)
                }
                if protocolRows.isEmpty {
                    NavigationLink {
                        LegalDocumentView(document: .disclaimer, showDone: false)
                    } label: {
                        VNavRow(icon: "doc.plaintext", iconTint: .vBlue, title: MeCopy.userAgreement)
                    }
                    VDivider(inset: 58)
                }
                NavigationLink { LegalLicensesView() } label: {
                    VNavRow(icon: "building.columns", iconTint: .vGold, title: MeCopy.licensesTitle)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var dangerCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                Button { showDeletion = true } label: {
                    VNavRow(icon: "trash", iconTint: .vPrimary, title: MeCopy.deletionTitle)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var protocolRows: [MeProtocolSign] {
        settings?.protocols ?? []
    }

    private func load() async {
        if settings == nil { state = .loading }
        do {
            settings = try await API.meSettings()
            state = .loaded
        } catch let e as APIError where e.status == 401 {
            state = .loaded
            settings = MeSettingsResponse()
            router.showLogin = true
        } catch let e as APIError where e.status == 404 {
            // Settings endpoint not shipped yet — still show local shell.
            settings = MeSettingsResponse()
            state = .loaded
        } catch {
            if settings == nil {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func setSaveHistory(_ on: Bool) async {
        let previous = settings?.saveBrowseHistory ?? true
        settings = rewritten(saveBrowseHistory: on)
        savingHistory = true
        defer { savingHistory = false }
        do {
            let resp = try await API.updateMePrefs(saveBrowseHistory: on)
            let resolved = resp.saveBrowseHistory
                ?? resp.prefs?.saveBrowseHistory
                ?? on
            settings = rewritten(saveBrowseHistory: resolved)
        } catch {
            settings = rewritten(saveBrowseHistory: previous)
            ToastCenter.shared.error(error)
        }
    }

    private func rewritten(saveBrowseHistory: Bool) -> MeSettingsResponse {
        let s = settings
        return MeSettingsResponse(
            realName: s?.realName,
            protocols: s?.protocols ?? [],
            licenses: s?.licenses ?? [],
            saveBrowseHistory: saveBrowseHistory,
            deletionEligible: s?.deletionEligible,
            meView: s?.meView
        )
    }
}

struct MeProtocolDetailView: View {
    let sign: MeProtocolSign

    var body: some View {
        ScrollView {
            VCard {
                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text(sign.displayTitle).font(.vHeadline)
                    Text(MeLogic.protocolSignedCaption(signedAt: sign.signedAt, version: sign.version))
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    if let hash = sign.contentHash, !hash.isEmpty {
                        Text("内容指纹 \(hash.prefix(12))…")
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                    Text("点此可再次阅读全文；协议正文以服务端公示版本为准。")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .lineSpacing(4)
                }
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle(sign.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
