import SwiftUI

/// Buyer apply form (DES-v1.3-09-02 §5.1 / §9).
struct AfterSaleApplyView: View {
    @StateObject private var model: AfterSaleApplyModel
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((AfterSale) -> Void)?

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
                Text(AfterSaleCopy.applyEmptyHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                typePicker
                claimPicker
                if model.claim == .partial {
                    amountField
                } else {
                    VKeyValue(key: "退款金额", value: model.claimAmountCents.display)
                        .font(.vBody)
                }
                reasonField

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
        .onChange(of: model.type) { _, _ in model.onTypeChange() }
        .onChange(of: model.claim) { _, _ in model.onClaimChange() }
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
}
