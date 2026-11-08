import SwiftUI

/// 降级弹窗：失去哪些权益、在途订单不受影响、如何申诉（DES-v1.3-05-01 §9）。
struct ProxyDowngradeSheet: View {
    let notice: ProxyDowngradeNotice
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    VCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(notice.title).font(.vTitle(22))
                            Text("\(notice.from.displayLabel) → \(notice.to.displayLabel)")
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                    }

                    VCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已关闭权益").font(.vHeadline)
                            if notice.lostTitles.isEmpty {
                                Text("无额外能力关闭").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            } else {
                                ForEach(notice.lostTitles, id: \.self) { title in
                                    Label(title, systemImage: "xmark.circle")
                                        .font(.vCaption)
                                        .foregroundStyle(Color.vPrimary)
                                }
                            }
                        }
                    }

                    VCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(notice.ordersSafe)
                                .font(.vBody)
                                .foregroundStyle(Color.vText)
                            Text(notice.appealHint)
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("权益变更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
