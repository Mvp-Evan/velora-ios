import SwiftUI
import PhotosUI

/// Buyer apply form (DES-v1.3-09-02 §5.1 / §9).
struct AfterSaleApplyView: View {
    @StateObject private var model: AfterSaleApplyModel
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((AfterSale) -> Void)?

    @State private var photoPicker: [PhotosPickerItem] = []
    @State private var showUnboxCapture = false

    init(
        orderId: Int64,
        orderStatus: String,
        afterSaleStatus: String,
        signedAt: Date?,
        shipDeadline: Date?,
        remainingPayableCents: Int64,
        unboxPhotoCount: Int = 0,
        isRealNamed: Bool = true,
        accountRestricted: Bool = false,
        onCreated: ((AfterSale) -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: AfterSaleApplyModel(
                orderId: orderId,
                orderStatus: orderStatus,
                afterSaleStatus: afterSaleStatus,
                signedAt: signedAt,
                shipDeadline: shipDeadline,
                remainingPayableCents: remainingPayableCents,
                unboxPhotoCount: unboxPhotoCount,
                isRealNamed: isRealNamed,
                accountRestricted: accountRestricted
            )
        )
        self.onCreated = onCreated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                Text(AfterSaleLogic.applyTypeBanner(for: model.type))
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(model.type)

                typePicker
                claimPicker
                if model.claim == .partial {
                    amountField
                } else {
                    VKeyValue(key: "退款金额", value: model.claimAmountCents.display)
                        .font(.vBody)
                }
                reasonField
                photoSection

                if let err = model.errorMessage ?? model.gateError?.fallbackMessage {
                    Text(err)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.gateError?.suggestsSuspectedFake == true {
                        Button("改选疑似假货") {
                            model.type = .suspectedFake
                            model.onTypeChange()
                        }
                        .font(.vCaptionMedium)
                    }
                    if model.gateError?.opensUnboxCapture == true {
                        Button(EvidenceCopy.supplementUnbox) {
                            showUnboxCapture = true
                        }
                        .font(.vCaptionMedium)
                    }
                }

                Text(AfterSaleCopy.noReasonReturnHidden)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)

                VPrimaryButton(
                    title: model.submitting ? AfterSaleCopy.submitLocked : AfterSaleCopy.applyTitle,
                    loading: model.submitting,
                    disabled: !model.canSubmit
                ) {
                    Task {
                        await model.submit()
                        if let created = model.created {
                            onCreated?(created)
                            dismiss()
                        }
                    }
                }
            }
            .padding(VSpace.xl)
        }
        .background(Color.vBackground)
        .navigationTitle(AfterSaleCopy.applyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .onChange(of: model.type) { _, _ in model.onTypeChange() }
        .onChange(of: model.claim) { _, _ in model.onClaimChange() }
        .onChange(of: photoPicker) { _, items in
            guard !items.isEmpty else { return }
            let captured = items
            photoPicker = []
            Task { await uploadPickedPhotos(captured) }
        }
        .sheet(isPresented: $showUnboxCapture) {
            EvidenceCaptureView(
                orderId: model.orderId,
                orderNo: "\(model.orderId)",
                kindGroup: .unbox
            ) {
                model.unboxEvidenceReady = true
                model.errorMessage = model.gateError?.fallbackMessage
            }
        }
    }

    private var typePicker: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(AfterSaleCopy.typePickerHint).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                ForEach(model.types) { t in
                    Button {
                        model.type = t
                    } label: {
                        HStack {
                            Text(t.displayLabel).font(.vBody).foregroundStyle(Color.vText)
                            Spacer()
                            if model.type == t {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vGold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var claimPicker: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(AfterSaleCopy.claimPickerHint).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                ForEach(AfterSaleClaim.allCases) { c in
                    Button {
                        model.claim = c
                    } label: {
                        HStack {
                            Text(c.displayLabel).font(.vBody).foregroundStyle(Color.vText)
                            Spacer()
                            if model.claim == c {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vGold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var amountField: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("部分退款金额（元）").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                TextField("0.00", text: $model.amountYuanText)
                    .keyboardType(.decimalPad)
                    .font(.vMono(18))
            }
        }
    }

    private var reasonField: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("问题描述").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                TextField(AfterSaleCopy.reasonPlaceholder, text: $model.reason, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.vBody)
            }
        }
    }

    private var photoSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("开箱照片").font(.vHeadline)
                    Text("\(model.unboxPhotoCount)/\(EvidenceConfigDefaults.unboxPhotosMinCount)+")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                    Spacer()
                    if model.uploadingPhotos { ProgressView().controlSize(.small) }
                }
                Text("品相类售后至少需要 \(EvidenceConfigDefaults.unboxPhotosMinCount) 张开箱照片")
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $photoPicker,
                        maxSelectionCount: EvidenceConfigDefaults.unboxPhotosMaxCount - model.unboxPhotoIds.count,
                        matching: .images
                    ) {
                        Label("从相册添加", systemImage: "photo.on.rectangle")
                            .font(.vCaptionMedium)
                    }
                    .disabled(model.uploadingPhotos)

                    Button {
                        showUnboxCapture = true
                    } label: {
                        Label("拍摄开箱", systemImage: "camera")
                            .font(.vCaptionMedium)
                    }
                }
            }
        }
    }

    private func uploadPickedPhotos(_ items: [PhotosPickerItem]) async {
        model.uploadingPhotos = true
        defer { model.uploadingPhotos = false }
        var datas: [Data] = []
        for item in items {
            if let raw = try? await item.loadTransferable(type: Data.self) {
                datas.append(raw)
            }
        }
        guard !datas.isEmpty else { return }
        do {
            let uploaded = try await API.uploadPublishImages(datas)
            let ids = uploaded.compactMap { item -> Int64? in
                guard let raw = item.imageId, let id = Int64(raw) else { return nil }
                return id
            }
            model.appendUnboxPhotoIds(ids)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
