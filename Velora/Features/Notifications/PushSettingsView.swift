import SwiftUI

/// Push / SMS switches (DES-v1.3-11-01 MSG-05 / D37). Trade inbox forced on.
struct PushSettingsView: View {
    @State private var payload = PushSettingsPayload()
    @State private var state: LoadState = .idle
    @State private var saving = false
    @State private var authStatus: String = ""
    @State private var errorText: String?

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
        .navigationTitle(NotifyCopy.pushSettingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var form: some View {
        List {
            Section {
                Text(NotifyCopy.quietHoursHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(NotifyCopy.doNotDisturbHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if !authStatus.isEmpty {
                    Text(authStatus)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                    Button(NotifyCopy.openSystemSettings) {
                        PushNotificationRegistrar.openSystemSettings()
                    }
                    .font(.vCaptionMedium)
                }
            }

            Section {
                Toggle(NotifyCopy.pushEvenWhenOnline, isOn: Binding(
                    get: { payload.pushEvenWhenOnline },
                    set: { newValue in
                        payload.pushEvenWhenOnline = newValue
                        Task { await save() }
                    }
                ))
            }

            Section("按事件") {
                ForEach(Array(payload.items.enumerated()), id: \.element.id) { idx, item in
                    settingRow(index: idx, item: item)
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .disabled(saving)
        .safeAreaPadding(.bottom, 84)
    }

    @ViewBuilder
    private func settingRow(index: Int, item: PushSetting) -> some View {
        let locked = item.channelClass.inboxForcedOn
        VStack(alignment: .leading, spacing: 8) {
            Text(item.eventCode)
                .font(.vBodyMedium)
            if let label = item.resolvedEvent?.channelClass.displayLabel {
                Text(label)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
            Toggle(isOn: Binding(
                get: { item.inboxEnabled },
                set: { newValue in
                    guard !locked else {
                        errorText = NotifyCopy.tradeInboxLocked
                        return
                    }
                    payload.items[index].inboxEnabled = newValue
                    Task { await save() }
                }
            )) {
                Text("站内")
            }
            .disabled(locked)
            Toggle(isOn: Binding(
                get: { item.pushEnabled },
                set: { newValue in
                    payload.items[index].pushEnabled = newValue
                    Task { await save() }
                }
            )) {
                Text("推送")
            }
            if item.resolvedEvent?.smsRequiredByMatrix == true {
                Toggle(isOn: Binding(
                    get: { item.smsEnabled },
                    set: { newValue in
                        payload.items[index].smsEnabled = newValue
                        Task { await save() }
                    }
                )) {
                    Text("短信")
                }
            }
            if locked {
                Text(NotifyCopy.tradeInboxLocked)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        if state != .loaded { state = .loading }
        authStatus = await PushNotificationRegistrar.authorizationHint()
        do {
            payload = try await API.pushSettings()
            if payload.items.isEmpty {
                payload.items = Self.defaultMatrixSettings()
            }
            state = .loaded
        } catch {
            // Soft-fail to matrix defaults so settings UI is usable offline / before server ships.
            payload = PushSettingsPayload(items: Self.defaultMatrixSettings())
            state = .loaded
            #if DEBUG
            print("[push-settings] load failed, using defaults: \(error)")
            #endif
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        errorText = nil
        let normalized = payload.items.map(NotifyLogic.normalizedSetting)
        if let err = NotifyLogic.validatePushSettingsUpdate(normalized) {
            errorText = err.fallbackMessage
            payload.items = normalized
            return
        }
        payload.items = normalized
        do {
            payload = try await API.updatePushSettings(
                UpdatePushSettingsRequest(
                    items: payload.items,
                    pushEvenWhenOnline: payload.pushEvenWhenOnline
                )
            )
            Haptics.light()
        } catch let e as APIError {
            if NotifyErrorCode.normalize(e.code) == .tradeInboxCannotDisable {
                errorText = NotifyCopy.tradeInboxLocked
            } else {
                errorText = e.message
            }
        } catch {
            errorText = "保存失败"
        }
    }

    /// Seed rows covering channel classes when server returns empty.
    private static func defaultMatrixSettings() -> [PushSetting] {
        [
            PushSetting(eventCode: "N-05", inboxEnabled: true, pushEnabled: true, smsEnabled: true),
            PushSetting(eventCode: "N-01", inboxEnabled: true, pushEnabled: true, smsEnabled: false),
            PushSetting(eventCode: "N-10", inboxEnabled: true, pushEnabled: true, smsEnabled: false),
            PushSetting(eventCode: "N-22", inboxEnabled: true, pushEnabled: false, smsEnabled: false),
            PushSetting(eventCode: "N-25", inboxEnabled: true, pushEnabled: true, smsEnabled: false),
            PushSetting(eventCode: "N-27", inboxEnabled: true, pushEnabled: true, smsEnabled: false),
        ]
    }
}
