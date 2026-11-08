import SwiftUI

/// Appeal within 3 days; another arbitrator (DES-v1.3-09-02 AFS-08).
struct ArbitrationAppealView: View {
    let arbitrationId: Int64
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                Text("申诉将改派另一名仲裁员复核，提交后即为终局前最后一次机会。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("申诉理由（≥20 字）")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                        TextField(AfterSaleCopy.appealReasonPlaceholder, text: $reason, axis: .vertical)
                            .lineLimit(4...10)
                            .font(.vBody)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                }

                VPrimaryButton(
                    title: submitting ? AfterSaleCopy.submitLocked : AfterSaleCopy.appealCTA,
                    loading: submitting,
                    disabled: AfterSaleLogic.reasonLengthError(reason) != nil || submitting
                ) {
                    Task { await submit() }
                }
            }
            .padding(VSpace.xl)
        }
        .background(Color.vBackground)
        .navigationTitle(AfterSaleCopy.appealTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private func submit() async {
        if let err = AfterSaleLogic.reasonLengthError(reason) {
            errorMessage = err.fallbackMessage
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            _ = try await API.appealArbitration(
                id: arbitrationId,
                request: ArbitrationAppealRequest(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            ToastCenter.shared.show("申诉已提交", .success)
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
