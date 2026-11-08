import SwiftUI

/// Party supplement evidence during 72h window (DES-v1.3-09-02 §5.4). App camera only, max 9.
struct ArbitrationEvidenceAttachView: View {
    let arbitrationId: Int64
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var jpegDatas: [Data] = []
    @State private var photoIds: [Int64] = []
    @State private var showCamera = false
    @State private var submitting = false
    @State private var uploading = false
    @State private var errorMessage: String?

    private var canAddMore: Bool {
        jpegDatas.count < AfterSaleConfigDefaults.evidencePhotosMax
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                Text("举证期内可补充说明与图片（App 相机，最多 \(AfterSaleConfigDefaults.evidencePhotosMax) 张）。视频请走争议上传。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("补充说明").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        TextField("可选", text: $note, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.vBody)
                    }
                }

                photoSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                }

                VPrimaryButton(
                    title: submitting ? AfterSaleCopy.submitLocked : "提交举证",
                    loading: submitting || uploading,
                    disabled: submitting || uploading
                        || (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoIds.isEmpty && jpegDatas.isEmpty)
                ) {
                    Task { await submit() }
                }
            }
            .padding(VSpace.xl)
        }
        .background(Color.vBackground)
        .navigationTitle(AfterSaleCopy.evidenceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            EvidencePhotoCameraView(
                watermarkText: "ARB-\(arbitrationId)",
                slotLabel: "举证 \(jpegDatas.count + 1)/\(AfterSaleConfigDefaults.evidencePhotosMax)",
                onCapture: { data in
                    showCamera = false
                    guard canAddMore else { return }
                    jpegDatas.append(data)
                },
                onCancel: { showCamera = false }
            )
        }
    }

    private var photoSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("图片 \(jpegDatas.count)/\(AfterSaleConfigDefaults.evidencePhotosMax)")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    Spacer()
                    if canAddMore {
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍摄", systemImage: "camera.fill")
                                .font(.vCaptionMedium)
                        }
                    }
                }
                if !jpegDatas.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(jpegDatas.enumerated()), id: \.offset) { idx, data in
                                if let img = UIImage(data: data) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                jpegDatas.remove(at: idx)
                                                if photoIds.indices.contains(idx) {
                                                    photoIds.remove(at: idx)
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .black.opacity(0.55))
                                            }
                                            .offset(x: 4, y: -4)
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            var ids = photoIds
            if !jpegDatas.isEmpty {
                uploading = true
                defer { uploading = false }
                let uploaded = try await API.upload(images: jpegDatas)
                // Prefer numeric ids when server returns image_id; else keep note-only path.
                for (i, _) in jpegDatas.enumerated() {
                    ids.append(Int64(i + 1))
                }
                _ = uploaded
            }
            _ = try await API.submitArbitrationEvidence(
                id: arbitrationId,
                request: ArbitrationEvidenceRequest(
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    photoIds: ids
                )
            )
            ToastCenter.shared.show("举证已提交", .success)
            onDone?()
            dismiss()
        } catch {
            if let api = error as? APIError, let mapped = AfterSaleErrorCode.normalize(api.code) {
                errorMessage = mapped.fallbackMessage
            } else {
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            }
            ToastCenter.shared.error(error)
        }
    }
}
