import SwiftUI

/// Confirm + POST block helper (DES-v1.3-10-02 RISK-07 / §9).
@MainActor
enum BlockUserAction {
    static func block(
        userId: Int64,
        blockerId: Int64? = nil
    ) async -> Bool {
        let blocker = blockerId ?? SessionStore.shared.user?.id
        if let err = RiskLogic.createBlockGate(
            blockerId: blocker,
            blockedId: userId,
            isLoggedIn: SessionStore.shared.isLoggedIn
        ) {
            ToastCenter.shared.show(err.fallbackMessage, .error)
            return false
        }
        do {
            _ = try await API.blockUser(userId)
            ToastCenter.shared.show(RiskCopy.blockSuccess, .success)
            return true
        } catch {
            if let api = error as? APIError, let mapped = RiskErrorCode.normalize(api.code) {
                ToastCenter.shared.show(mapped.fallbackMessage, .error)
            } else {
                ToastCenter.shared.error(error)
            }
            return false
        }
    }
}

/// Reusable confirmation dialog + sheet host for report/block from chat / profiles.
struct PeerRiskActionsModifier: ViewModifier {
    let peerId: Int64
    let peerName: String
    @Binding var showReport: Bool
    @Binding var showBlockConfirm: Bool
    var onBlocked: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showReport) {
                ReportSheetView(
                    targetType: .user,
                    targetId: peerId,
                    peerName: peerName
                )
            }
            .confirmationDialog(
                RiskCopy.blockConfirmTitle,
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button(RiskCopy.blockAction, role: .destructive) {
                    Task {
                        if await BlockUserAction.block(userId: peerId) {
                            onBlocked?()
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(RiskCopy.blockConfirmMessage)
            }
    }
}

extension View {
    func peerRiskActions(
        peerId: Int64,
        peerName: String,
        showReport: Binding<Bool>,
        showBlockConfirm: Binding<Bool>,
        onBlocked: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PeerRiskActionsModifier(
                peerId: peerId,
                peerName: peerName,
                showReport: showReport,
                showBlockConfirm: showBlockConfirm,
                onBlocked: onBlocked
            )
        )
    }
}
