import SwiftUI
import Photos

/// 资质公示 (DES-v1.3-12-01 ME-07 / NFR-08 / D39). Pending items show「办理中」without fake numbers.
struct LegalLicensesView: View {
    @State private var items: [LegalLicense] = []
    @State private var sdks: [LegalSDK] = []
    @State private var state: LoadState = .idle
    @State private var previewURL: IdentifiedURL?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load() } }
            case .loaded:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(MeCopy.licensesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $previewURL) { box in
            LicenseImagePreview(url: box.url)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                if items.isEmpty {
                    VEmptyState(icon: "building.columns", title: MeCopy.licensesEmpty)
                } else {
                    ForEach(items) { license in
                        licenseCard(license)
                    }
                }
                sdkSection
                Text(MeCopy.licensesFooter)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, VSpace.m)
                    .padding(.bottom, 40)
            }
            .padding(VSpace.l)
        }
    }

    private var sdkSection: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            Text(MeCopy.sdkDisclosureTitle)
                .font(.vHeadline)
                .foregroundStyle(Color.vText)
            if sdks.isEmpty {
                Text(MeCopy.sdkDisclosureEmpty)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            } else {
                ForEach(sdks) { sdk in
                    VCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sdk.name).font(.vHeadline).foregroundStyle(Color.vText)
                            if let vendor = sdk.vendor, !vendor.isEmpty {
                                VKeyValue(key: "厂商", value: vendor)
                            }
                            if let purpose = sdk.purpose, !purpose.isEmpty {
                                VKeyValue(key: "用途", value: purpose)
                            }
                            if let types = sdk.dataTypes, !types.isEmpty {
                                VKeyValue(key: "数据类型", value: types.joined(separator: "、"))
                            }
                            if let url = sdk.privacyURL, !url.isEmpty, let link = URL(string: url) {
                                Link("隐私政策", destination: link)
                                    .font(.vCaptionMedium)
                                    .foregroundStyle(Color.vBlue)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, VSpace.l)
    }

    private func licenseCard(_ license: LegalLicense) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(license.name).font(.vHeadline).foregroundStyle(Color.vText)
                    Spacer()
                    Text(license.resolvedStatus.displayLabel)
                        .font(.vCaptionMedium)
                        .foregroundStyle(license.isPending ? Color.vGold : Color.vGreen)
                }
                VKeyValue(key: "证号", value: license.displayLicenseNo)
                if let issuer = license.issuer, !issuer.isEmpty {
                    VKeyValue(key: "发证机关", value: issuer)
                }
                if let granted = license.grantedAt {
                    VKeyValue(key: "获批", value: granted.shortText)
                }
                if let expires = license.expiresAt {
                    VKeyValue(key: "有效期至", value: expires.shortText)
                }
                if let url = license.imageUrl, !url.isEmpty {
                    Button {
                        previewURL = IdentifiedURL(url: url)
                    } label: {
                        RemoteImage(url)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Text("查看大图")
                                    .font(.vMicro)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.45), in: Capsule())
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        if items.isEmpty { state = .loading }
        do {
            async let licResp = API.legalLicenses()
            async let sdkResp = API.legalSDKs()
            let resp = try await licResp
            items = resp.items
            sdks = (try? await sdkResp)?.items ?? []
            // Fallback: settings may embed licenses when public endpoint 404s.
            if items.isEmpty, let embedded = try? await API.meSettings() {
                items = embedded.licenses
            }
            state = .loaded
        } catch let e as APIError where e.status == 404 {
            if let embedded = try? await API.meSettings() {
                items = embedded.licenses
            }
            state = .loaded
        } catch {
            if items.isEmpty {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: String
}

private struct LicenseImagePreview: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RemoteImage(url)
                    .scaledToFit()
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveToAlbum() }
                    } label: {
                        if saving {
                            ProgressView().tint(.white)
                        } else {
                            Text("保存").foregroundStyle(.white)
                        }
                    }
                    .disabled(saving)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func saveToAlbum() async {
        saving = true
        defer { saving = false }
        do {
            guard let u = URL(string: url) else {
                ToastCenter.shared.show("无效链接", .error)
                return
            }
            let (data, _) = try await URLSession.shared.data(from: u)
            guard let image = UIImage(data: data) else {
                ToastCenter.shared.show("图片无效", .error)
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            ToastCenter.shared.show("已保存到相册", .success)
        } catch {
            ToastCenter.shared.show((error as? LocalizedError)?.errorDescription ?? "保存失败", .error)
        }
    }
}
