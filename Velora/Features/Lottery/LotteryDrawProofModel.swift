import Foundation
import Combine
import UIKit

/// 开奖凭证页（DES-v1.3-06-02 §5.6 / §9）— 公开字段 + 复现说明。
@MainActor
final class LotteryDrawProofModel: ObservableObject {
    let releaseId: Int64

    @Published var proof: LotteryDrawProof?
    @Published var state: LoadState = .idle
    @Published var showReproduceGuide = false

    init(releaseId: Int64) {
        self.releaseId = releaseId
    }

    var seedPrefix: String {
        guard let seed = proof?.seed else { return "" }
        return LotteryLogic.seedPrefix(seed)
    }

    var computedSeedMatches: Bool? {
        guard let proof,
              let hash = proof.entriesHash,
              let random = proof.externalRandom,
              let seed = proof.seed else { return nil }
        let computed = LotteryLogic.computeSeed(entriesHashHex: hash, externalRandom: random)
        return computed.lowercased() == seed.lowercased()
    }

    func load() async {
        if proof == nil { state = .loading }
        do {
            proof = try await API.lotteryDrawProof(releaseId)
            state = .loaded
        } catch let e as APIError {
            if let code = LotteryErrorCode(rawValue: e.code), code == .drawNotReady {
                state = .failed(code.fallbackMessage)
            } else {
                state = .failed(e.message.isEmpty ? "加载失败" : e.message)
            }
        } catch {
            state = .failed("加载失败")
        }
    }

    func copyAllFields() {
        guard let proof else { return }
        UIPasteboard.general.string = proof.copyAllFieldsText
        ToastCenter.shared.show("已复制全部字段", .success)
    }

    func copyHash() {
        guard let hash = proof?.entriesHash, !hash.isEmpty else { return }
        UIPasteboard.general.string = hash
        ToastCenter.shared.show("已复制哈希", .success)
    }

    func copySeed() {
        guard let seed = proof?.seed, !seed.isEmpty else { return }
        UIPasteboard.general.string = seed
        ToastCenter.shared.show("已复制 seed", .success)
    }

    func copyReproduceGuide() {
        let text = ([LotteryCopy.reproduceGuide] + LotteryCopy.reproduceSteps.enumerated().map { "\($0.offset + 1). \($0.element)" })
            .joined(separator: "\n")
        UIPasteboard.general.string = text
        ToastCenter.shared.show("已复制复现说明", .success)
    }

    var reproduceGuideURL: URL? {
        let path = LotteryConfigDefaults.reproduceGuidePath
        return URL(string: path, relativeTo: AppConfig.baseURL)?.absoluteURL
    }
}
