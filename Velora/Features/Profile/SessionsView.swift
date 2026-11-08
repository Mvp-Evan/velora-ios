import SwiftUI

/// Login device / refresh-session list stub (DES-v1.3-01 §5.7 `GET /me/sessions`).
struct SessionsView: View {
    @State private var items: [DeviceSession] = []
    @State private var state: LoadState = .idle
    @State private var unsupported = false
    @State private var revokingId: String?

    var body: some View {
        Group {
            if unsupported {
                VEmptyState(
                    icon: "laptopcomputer.and.iphone",
                    title: "登录设备管理即将开放",
                    message: "服务端上线 /me/sessions 后可在此查看并踢出其他设备"
                )
            } else {
                switch state {
                case .idle, .loading:
                    VLoadingView()
                case .failed(let m):
                    VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if items.isEmpty {
                        VEmptyState(icon: "iphone", title: "暂无其他登录设备", message: "当前仅本机在线")
                    } else {
                        List {
                            ForEach(items) { s in
                                sessionRow(s)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle("登录设备")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func sessionRow(_ s: DeviceSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.current ? "iphone" : "iphone.gen2")
                .foregroundStyle(Color.vPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(s.deviceName?.isEmpty == false ? s.deviceName! : "未知设备")
                        .font(.vBodyMedium)
                    if s.current {
                        Text("本机")
                            .font(.vMicro)
                            .foregroundStyle(Color.vPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.vPrimary.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    if let ip = s.ipMasked, !ip.isEmpty {
                        Text(ip).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                    if let seen = s.lastSeen {
                        Text(seen.relativeText).font(.vCaption).foregroundStyle(Color.vTextTertiary)
                    }
                }
            }
            Spacer()
            if !s.current {
                Button {
                    Task { await revoke(s) }
                } label: {
                    if revokingId == s.id {
                        ProgressView()
                    } else {
                        Text("下线").font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                    }
                }
                .disabled(revokingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        if items.isEmpty { state = .loading }
        unsupported = false
        do {
            items = try await API.sessions()
            state = .loaded
        } catch let e as APIError where e.status == 404 || e.code.hasPrefix("http_404") {
            unsupported = true
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }

    private func revoke(_ s: DeviceSession) async {
        revokingId = s.id
        defer { revokingId = nil }
        do {
            try await API.revokeSession(s.id)
            items.removeAll { $0.id == s.id }
            ToastCenter.shared.show("已下线该设备", .success)
        } catch let e as APIError where e.status == 404 {
            ToastCenter.shared.show("下线能力即将开放", .info)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
