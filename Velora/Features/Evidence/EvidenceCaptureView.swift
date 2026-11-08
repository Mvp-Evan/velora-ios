import SwiftUI

/// Five-slot ship evidence + optional inspect video (DES-v1.3-09-01).
struct EvidenceCaptureView: View {
    @StateObject private var model: EvidenceCaptureModel
    @Environment(\.dismiss) private var dismiss
    var onReady: (() -> Void)?

    init(
        orderId: Int64,
        orderNo: String,
        kindGroup: EvidenceKindGroup = .ship,
        amountFen: Int64 = 0,
        sellerType: String? = nil,
        onReady: (() -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: EvidenceCaptureModel(
                orderId: orderId,
                orderNo: orderNo,
                kindGroup: kindGroup,
                amountFen: amountFen,
                sellerType: sellerType
            )
        )
        self.onReady = onReady
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    header
                    slotGrid
                    if model.inspectRequired {
                        videoSection
                    }
                    if model.hashing {
                        hashBanner
                    }
                    if let err = model.errorMessage {
                        Text(err)
                            .font(.vCaption)
                            .foregroundStyle(Color.vPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.localVideoMissing {
                        Text(EvidenceCopy.localVideoMissing)
                            .font(.vCaption)
                            .foregroundStyle(Color.vGold)
                    }
                }
                .padding(VSpace.xl)
            }
            .background(Color.vBackground)
            .navigationTitle(model.kindGroup == .ship ? EvidenceCopy.titleShip : EvidenceCopy.titleUnbox)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if model.canFinish {
                        Text(EvidenceCopy.readyToShip)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                    VPrimaryButton(
                        title: model.canFinish ? EvidenceCopy.readyToShip : EvidenceCopy.continueEvidence,
                        loading: model.working || model.hashing,
                        disabled: !model.canFinish
                    ) {
                        onReady?()
                        dismiss()
                    }
                }
                .padding(VSpace.l)
                .background(Color.vSurface)
            }
            .task { await model.load(); _ = await model.ensureSession() }
            .fullScreenCover(isPresented: $model.showCamera) {
                EvidencePhotoCameraView(
                    watermarkText: model.watermarkText,
                    slotLabel: model.activeSlot?.displayLabel ?? "",
                    onCapture: { data in
                        Task { await model.handleCapturedJPEG(data) }
                    },
                    onCancel: { model.showCamera = false }
                )
            }
            .fullScreenCover(isPresented: $model.showVideoRecorder) {
                EvidenceVideoRecorderView(
                    watermarkText: model.watermarkText,
                    title: model.kindGroup == .ship ? EvidenceCopy.recordInspect : EvidenceCopy.recordUnbox,
                    onFinished: { url, ms in
                        Task { await model.handleRecordedVideo(tempURL: url, durationMs: ms) }
                    },
                    onCancel: { model.showVideoRecorder = false },
                    onInterrupted: { model.videoInterrupted() }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(EvidenceCopy.shipHint)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            HStack {
                Text(model.progressLabel)
                    .font(.vMono(16))
                    .foregroundStyle(Color.vPrimary)
                Spacer()
                if model.sessionRemaining > 0 {
                    Text("会话 \(OrderLogic.formatCountdown(model.sessionRemaining))")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
            if model.clockSkewHint {
                Text(EvidenceCopy.serverTimeHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vGold)
            }
            Text(model.watermarkText)
                .font(.vMono(12))
                .foregroundStyle(Color.vTextTertiary)
                .lineLimit(1)
        }
    }

    private var slotGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(EvidencePhotoSlot.shipRequired) { slot in
                let filled = model.slots.first(where: { $0.slot == slot.rawValue })?.filled == true
                Button {
                    model.startPhoto(slot: slot)
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: filled ? "checkmark.circle.fill" : slot.diagramSystemImage)
                            .font(.system(size: 28))
                            .foregroundStyle(filled ? Color.vPrimary : Color.vTextSecondary)
                        Text(slot.displayLabel)
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vText)
                        Text(filled ? EvidenceCopy.retake : EvidenceCopy.shootSlot)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    .accessibilityLabel(slot.voiceOverHint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(EvidenceCopy.recordInspect)
                .font(.vHeadline)
            Text(model.shipVideoRegistered ? EvidenceCopy.fingerprintDone : EvidenceCopy.inspectVideoRequired)
                .font(.vCaption)
                .foregroundStyle(model.shipVideoRegistered ? Color.vTextSecondary : Color.vPrimary)
            VPrimaryButton(
                title: model.shipVideoRegistered ? EvidenceCopy.retake : EvidenceCopy.recordInspect,
                style: .dark,
                disabled: model.hashing
            ) {
                model.startVideo()
            }
        }
        .padding(VSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private var hashBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(EvidenceCopy.hashing).font(.vCaptionMedium)
            ProgressView(value: model.hashProgress)
                .tint(Color.vPrimary)
        }
        .padding(VSpace.l)
        .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}

// MARK: - Confirm-receipt unbox guide (AFS-02, skippable)

struct UnboxVideoGuideSheet: View {
    let orderId: Int64
    let orderNo: String
    var onSkip: () -> Void
    var onRecord: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text(EvidenceCopy.unboxGuideTitle).font(.vTitle(20))
            Text(EvidenceCopy.unboxGuideBody)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            VPrimaryButton(title: EvidenceCopy.recordUnbox) {
                onRecord()
                dismiss()
            }
            Button(EvidenceCopy.skipUnbox) {
                onSkip()
                dismiss()
            }
            .font(.vCaptionMedium)
            .foregroundStyle(Color.vTextSecondary)
            .frame(maxWidth: .infinity)
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
    }
}
