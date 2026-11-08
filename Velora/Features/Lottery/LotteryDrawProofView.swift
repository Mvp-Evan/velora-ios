import SwiftUI

/// 开奖凭证：公开字段、脱敏名单、复现说明链接/复制（DES-v1.3-06-02 §5.6 / §9 / B-06）。
struct LotteryDrawProofView: View {
    let releaseId: Int64

    @StateObject private var model: LotteryDrawProofModel

    init(releaseId: Int64) {
        self.releaseId = releaseId
        _model = StateObject(wrappedValue: LotteryDrawProofModel(releaseId: releaseId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let msg):
                VErrorView(message: msg) { Task { await model.load() } }
            case .loaded:
                if let proof = model.proof {
                    content(proof)
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(LotteryCopy.proofTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(LotteryCopy.copyAllFields) { model.copyAllFields() }
                    Button(LotteryCopy.copyHash) { model.copyHash() }
                    Button(LotteryCopy.copySeed) { model.copySeed() }
                    Button(LotteryCopy.reproduceGuide) { model.showReproduceGuide = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $model.showReproduceGuide) {
            reproduceSheet
        }
    }

    private func content(_ proof: LotteryDrawProof) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                if proof.isLegalReviewed {
                    Text(LotteryCopy.legalReviewedBadge)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.vGold.opacity(0.12), in: Capsule())
                }

                if let title = proof.title, !title.isEmpty {
                    Text(title)
                        .font(.vTitle(22))
                        .foregroundStyle(Color.vText)
                }

                fieldsCard(proof)
                actionsRow
                listCard(title: "中签名单", rows: proof.winners)
                listCard(title: "候补名单", rows: proof.waitlist)
                reproduceCard
            }
            .padding(VSpace.l)
            .padding(.bottom, VSpace.xl)
        }
        .refreshable { await model.load() }
    }

    private func fieldsCard(_ proof: LotteryDrawProof) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                field("算法版本", proof.resolvedAlgorithmVersion)
                field("报名人数", proof.entriesCount.map(String.init) ?? "—")
                field("N / M", "\(proof.n ?? 0) / \(proof.m ?? 0)")
                field("名单哈希", proof.entriesHash ?? "—", mono: true)
                field("外部随机源", proof.externalSource ?? "—")
                field("外部引用", proof.externalRef ?? "—")
                field("外部随机值", proof.externalRandom ?? "—", mono: true)
                field("seed", proof.seed ?? "—", mono: true)
                if !model.seedPrefix.isEmpty {
                    field("seed 前缀", model.seedPrefix, mono: true)
                }
                if let match = model.computedSeedMatches {
                    field("本地复算", match ? "与公示 seed 一致" : "与公示 seed 不一致")
                }
                if let drawnAt = proof.drawnAt {
                    field("开奖时间", drawnAt.shortText)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func field(_ title: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.vMicro)
                .foregroundStyle(Color.vTextTertiary)
            Text(value)
                .font(mono ? .vCaption.monospaced() : .vBody)
                .foregroundStyle(Color.vText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button(LotteryCopy.copyAllFields) { model.copyAllFields() }
                .font(.vCaptionMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            Button(LotteryCopy.reproduceGuide) { model.showReproduceGuide = true }
                .font(.vCaptionMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.vPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                .foregroundStyle(Color.vPrimary)
        }
        .buttonStyle(.plain)
    }

    private func listCard(title: String, rows: [LotteryMaskedParticipant]) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text(title)
                    .font(.vHeadline)
                if rows.isEmpty {
                    Text("暂无")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                } else {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.rank.map { "#\($0)" } ?? "—")
                                .font(.vCaption.monospacedDigit())
                                .foregroundStyle(Color.vTextSecondary)
                                .frame(width: 40, alignment: .leading)
                            Text(row.displayName)
                                .font(.vBody)
                                .foregroundStyle(Color.vText)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("名次 \(row.rank ?? 0)，\(row.displayName)")
                    }
                }
            }
        }
    }

    private var reproduceCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(LotteryCopy.reproduceGuide)
                    .font(.vHeadline)
                ForEach(Array(LotteryCopy.reproduceSteps.enumerated()), id: \.offset) { idx, step in
                    Text("\(idx + 1). \(step)")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = model.reproduceGuideURL {
                    Link(destination: url) {
                        Text("打开复现说明页")
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vPrimary)
                    }
                }
                Button("复制复现说明") { model.copyReproduceGuide() }
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vPrimary)
            }
        }
    }

    private var reproduceSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.m) {
                    ForEach(Array(LotteryCopy.reproduceSteps.enumerated()), id: \.offset) { idx, step in
                        Text("\(idx + 1). \(step)")
                            .font(.vBody)
                            .foregroundStyle(Color.vText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle(LotteryCopy.reproduceGuide)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { model.showReproduceGuide = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("复制") { model.copyReproduceGuide() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
