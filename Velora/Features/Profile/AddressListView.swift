import SwiftUI

struct AddressListView: View {
    var selecting = false
    var onSelect: ((Address) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Address] = []
    @State private var state: LoadState = .idle
    @State private var editing: Address?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if items.isEmpty {
                        VEmptyState(icon: "mappin.and.ellipse", title: "还没有收货地址", actionTitle: "新增地址") { creating = true }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: VSpace.m) {
                                ForEach(items) { a in
                                    Button {
                                        if selecting { onSelect?(a); dismiss() } else { editing = a }
                                    } label: { row(a) }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(VSpace.l)
                        }
                    }
                }
            }
            .background(Color.vBackground)
            .navigationTitle(selecting ? "选择收货地址" : "收货地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selecting { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                ToolbarItem(placement: .primaryAction) { Button { creating = true } label: { Image(systemName: "plus") } }
            }
            .task { await load() }
            .sheet(isPresented: $creating) { AddressEditView(address: .blank) { Task { await load() } } }
            .sheet(item: $editing) { a in AddressEditView(address: a) { Task { await load() } } }
        }
    }

    private func row(_ a: Address) -> some View {
        VCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(a.name).font(.vHeadline)
                        Text(a.phone).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        if a.isDefault { VTagChip(text: "默认", tint: .vPrimary, background: .vPrimarySoft) }
                    }
                    Text(a.oneLine).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                Spacer()
                if selecting { Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary) }
                else { Button { editing = a } label: { Image(systemName: "square.and.pencil").foregroundStyle(Color.vTextSecondary) } }
            }
        }
    }

    private func load() async {
        if items.isEmpty { state = .loading }
        do { items = try await API.addresses(); state = .loaded } catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }
}

struct AddressEditView: View {
    @State var address: Address
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.m) {
                    VCard(padding: 0) {
                        VStack(spacing: 0) {
                            VFormRow(title: "收货人", required: true) { TextField("姓名", text: $address.name).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "手机号", required: true) { TextField("11 位手机号", text: $address.phone).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "省份", required: true) { TextField("如：上海市", text: $address.province).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "城市", required: true) { TextField("如：上海市", text: $address.city).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "区县", required: true) { TextField("如：浦东新区", text: $address.district).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "详细地址", required: true) { TextField("街道、门牌号", text: $address.detail, axis: .vertical).multilineTextAlignment(.trailing) }
                        }
                    }
                    VCard(padding: 0) {
                        VFormRow(title: "设为默认") { Spacer(); Toggle("", isOn: $address.isDefault).labelsHidden().tint(Color.vPrimary) }
                    }
                    if address.id != 0 {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text("删除地址").font(.vBodyMedium).frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                        }
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle(address.id == 0 ? "新增地址" : "编辑地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid || saving) }
            }
            .confirmationDialog("删除该地址？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    Task { do { try await API.deleteAddress(address.id); done(); dismiss() } catch { ToastCenter.shared.error(error) } }
                }
            }
        }
    }

    private var valid: Bool { !address.name.isBlank && address.phone.isPhone && !address.province.isBlank && !address.city.isBlank && !address.district.isBlank && !address.detail.isBlank }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                if address.id == 0 { _ = try await API.createAddress(address) } else { _ = try await API.updateAddress(address) }
                ToastCenter.shared.show("已保存", .success); done(); dismiss()
            } catch { ToastCenter.shared.error(error) }
        }
    }
}
