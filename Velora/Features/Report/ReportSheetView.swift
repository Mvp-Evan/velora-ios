import SwiftUI
import PhotosUI

/// Multi-target report sheet (DES-v1.3-10-02 §5.4 / §5.12 / §9).
struct ReportSheetView: View {
    @StateObject private var model: ReportSheetModel
    @Environment(\.dismiss) private var dismiss
    var onSubmitted: ((Report) -> Void)?

    init(
        targetType: ReportTargetType,
        targetId: Int64,
        orderId: Int64? = nil,
        isOrderBuyer: Bool = true,
        peerName: String? = nil,
        onSubmitted: ((Report) -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: ReportSheetModel(
                targetType: targetType,
                targetId: targetId,
                orderId: orderId,
                isOrderBuyer: isOrderBuyer,
                peerName: peerName
            )
        )
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if let name = model.peerName, !name.isEmpty {
                        Text("对象：\(name)")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }

                    reasonPicker

                    if model.targetType.isBountyTarget {
                        bountyExtras
                    } else if model.reason?.requiresEvidenceHint == true {
                        evidenceSection
                    } else {
                        evidenceSection
                    }

                    if let err = model.errorMessage ?? model.gateError?.fallbackMessage {
                        Text(err)
                            .font(.vCaption)
                            .foregroundStyle(Color.vPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VPrimaryButton(
                        title: model.submitting ? RiskCopy.submitLocked : RiskCopy.reportTitle,
                        loading: model.submitting,
                        disabled: !model.canSubmit
                    ) {
                        Task {
                            await model.submit()
                            if let created = model.created {
                                onSubmitted?(created)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(VSpace.xl)
            }
            .background(Color.vBackground)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: model.pickerItems) { _, items in
                Task { await model.onPickerChange(items) }
            }
        }
    }

    private var reasonPicker: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(RiskCopy.reasonPickerHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                ForEach(model.reasons) { r in
                    Button {
                        model.reason = r
                    } label: {
                        HStack {
                            Text(r.displayLabel).font(.vBody).foregroundStyle(Color.vText)
                            Spacer()
                            if model.reason == r {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vGold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.targetType.isBountyTarget)
                }
            }
        }
    }

    private var bountyExtras: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            evidenceSection
            Toggle(isOn: $model.attachConversation) {
                Text(RiskCopy.attachConversation)
                    .font(.vBody)
                    .foregroundStyle(Color.vText)
            }
            .tint(Color.vPrimary)
        }
    }

    private var evidenceSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text(RiskCopy.evidenceHint)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.uploading { ProgressView().controlSize(.small) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(model.evidenceThumbnails.enumerated()), id: \.offset) { i, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            Button {
                                model.removeEvidence(at: i)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, Color.black.opacity(0.55))
                                    .padding(4)
                            }
                        }
                    }
                    if model.evidenceURLs.count < RiskConfigDefaults.evidencePhotosMax {
                        PhotosPicker(
                            selection: $model.pickerItems,
                            maxSelectionCount: RiskConfigDefaults.evidencePhotosMax - model.evidenceURLs.count,
                            matching: .images
                        ) {
                            RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                                .strokeBorder(Color.vSeparator, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.title3)
                                        .foregroundStyle(Color.vTextTertiary)
                                }
                        }
                    }
                }
            }
        }
    }
}
