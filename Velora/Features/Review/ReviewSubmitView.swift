import SwiftUI
import PhotosUI

/// Review compose sheet for a completed order (DES-v1.3-12-02 §9).
struct ReviewSubmitView: View {
    let orderId: Int64
    var onDone: () -> Void = {}

    @StateObject private var model: ReviewSubmitModel
    @Environment(\.dismiss) private var dismiss

    init(orderId: Int64, onDone: @escaping () -> Void = {}) {
        self.orderId = orderId
        self.onDone = onDone
        _model = StateObject(wrappedValue: ReviewSubmitModel(orderId: orderId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    Text(ReviewCreditCopy.submitTitle)
                        .font(.vTitle(22))
                        .foregroundStyle(Color.vText)

                    ratingRow

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(ReviewCreditCopy.contentPlaceholder, text: $model.content, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.vBody)
                            .padding(12)
                            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            .onChange(of: model.content) { _, _ in model.onContentChange() }
                        Text("\(model.content.count)/\(ReviewCreditConfigDefaults.reviewContentMax)")
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }

                    imagesSection

                    if model.draftHint {
                        Text(ReviewCreditCopy.draftSaved)
                            .font(.vCaption)
                            .foregroundStyle(Color.vGold)
                    }
                    if let err = model.errorMessage {
                        Text(err).font(.vCaption).foregroundStyle(Color.vPrimary)
                    }

                    VPrimaryButton(
                        title: ReviewCreditCopy.submitCTA,
                        loading: model.submitting,
                        disabled: !model.canSubmit
                    ) {
                        model.requestSubmit()
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .confirmationDialog(
                ReviewCreditCopy.badConfirmTitle,
                isPresented: $model.showBadConfirm,
                titleVisibility: .visible
            ) {
                Button(ReviewCreditCopy.badConfirmOK, role: .destructive) {
                    model.confirmBadAndSubmit()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(ReviewCreditCopy.badConfirmMessage)
            }
            .onChange(of: model.submitted?.id) { _, newId in
                if newId != nil {
                    onDone()
                    dismiss()
                }
            }
            .onChange(of: model.pickerItems) { _, items in
                Task { await model.onPickerChange(items) }
            }
        }
    }

    private var ratingRow: some View {
        HStack(spacing: 10) {
            ForEach(ReviewRating.allCases) { r in
                Button {
                    model.selectRating(r)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: r.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                        Text(r.displayLabel).font(.vCaptionMedium)
                    }
                    .foregroundStyle(model.rating == r ? Color.vPrimary : Color.vTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        (model.rating == r ? Color.vPrimarySoft : Color.vFill),
                        in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var imagesSection: some View {
        let uploading = model.uploading
        return VStack(alignment: .leading, spacing: 8) {
            Text(ReviewCreditCopy.imagesHint)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.imageThumbnails.enumerated()), id: \.offset) { idx, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            Button {
                                model.removeImage(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, Color.black.opacity(0.55))
                            }
                            .offset(x: 4, y: -4)
                        }
                    }
                    if model.remainingImages > 0 {
                        PhotosPicker(
                            selection: $model.pickerItems,
                            maxSelectionCount: model.remainingImages,
                            matching: .images
                        ) {
                            ReviewPhotoPickerLabel(uploading: uploading)
                        }
                    }
                }
            }
        }
    }
}

private struct ReviewPhotoPickerLabel: View {
    let uploading: Bool

    var body: some View {
        VStack(spacing: 4) {
            if uploading {
                ProgressView()
            } else {
                Image(systemName: "plus")
            }
            Text("相册").font(.vMicro)
        }
        .foregroundStyle(Color.vTextSecondary)
        .frame(width: 72, height: 72)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}
