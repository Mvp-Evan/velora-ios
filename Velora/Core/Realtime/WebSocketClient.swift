import Foundation
import Combine

/// 服务端推送事件
struct WSEvent {
    let type: String
    let channel: String
    let data: [String: AnyCodable]
    let at: Date

    func int64(_ k: String) -> Int64? {
        switch data[k]?.value {
        case let i as Int64: return i
        case let i as Int: return Int64(i)
        case let d as Double: return Int64(d)
        case let s as String: return Int64(s)
        default: return nil
        }
    }
    func string(_ k: String) -> String? { data[k]?.value as? String }
    func bool(_ k: String) -> Bool { data[k]?.value as? Bool ?? false }
    func date(_ k: String) -> Date? {
        guard let s = string(k) else { return nil }
        return APIClient.parseDate(s)
    }
    var lotId: Int64? { int64("lot_id") }
}

/// 单连接 WebSocket 客户端：自动重连 + 重新订阅（频道 + 列表卡片）
@MainActor
final class WebSocketClient: ObservableObject {
    static let shared = WebSocketClient()

    @Published private(set) var connected = false
    /// Milliseconds to add to local wall clock to approximate server time (from WS `server_time`).
    @Published private(set) var serverTimeOffsetMs: Int64 = 0
    let events = PassthroughSubject<WSEvent, Never>()

    private var serverTimeClock = ServerTimeClock()

    private var task: URLSessionWebSocketTask?
    private var token: String?
    private var subscriptions = Set<String>()
    private var reconnectDelay: TimeInterval = 1
    private var reconnectWork: Task<Void, Never>?
    private var pingWork: Task<Void, Never>?
    private var generation = 0

    private init() {}

    func connect(token: String?) {
        self.token = token
        reconnectDelay = 1
        open()
    }

    func subscribe(_ channel: String) {
        subscriptions.insert(channel)
        sendJSON(["type": "subscribe", "channel": channel])
    }

    func unsubscribe(_ channel: String) {
        subscriptions.remove(channel)
        sendJSON(["type": "unsubscribe", "channel": channel])
    }

    func subscribeLot(_ id: Int64) { subscribe("lot:\(id)") }
    func unsubscribeLot(_ id: Int64) { unsubscribe("lot:\(id)") }

    // MARK: - Card list subscriptions (HOME-11 / T-11)

    func subscribeCards(_ lotIds: [Int64]) {
        let ids = Array(Set(lotIds)).sorted()
        guard !ids.isEmpty else { return }
        sendObject([
            "type": LotCardSubscribePolicy.subscribeEvent,
            "lot_ids": ids.map { NSNumber(value: $0) },
        ])
    }

    func unsubscribeCards(_ lotIds: [Int64]) {
        let ids = Array(Set(lotIds)).sorted()
        guard !ids.isEmpty else { return }
        sendObject([
            "type": LotCardSubscribePolicy.unsubscribeEvent,
            "lot_ids": ids.map { NSNumber(value: $0) },
        ])
    }

    func cardHeartbeat(_ lotIds: [Int64]) {
        let ids = Array(Set(lotIds)).sorted()
        guard !ids.isEmpty else { return }
        sendObject([
            "type": LotCardSubscribePolicy.heartbeatEvent,
            "lot_ids": ids.map { NSNumber(value: $0) },
        ])
    }

    // MARK: - Internals

    private func open() {
        task?.cancel(with: .goingAway, reason: nil)
        reconnectWork?.cancel(); pingWork?.cancel()
        generation += 1
        let gen = generation

        var comps = URLComponents(url: AppConfig.wsURL, resolvingAgainstBaseURL: false)!
        if let token { comps.queryItems = [URLQueryItem(name: "token", value: token)] }
        let t = URLSession.shared.webSocketTask(with: comps.url!)
        task = t
        t.resume()
        connected = true
        for ch in subscriptions { sendJSON(["type": "subscribe", "channel": ch]) }
        // Card subscriptions are owned by ListCardRealtimeSession instances; they re-sub on `connected`.
        receiveLoop(t, gen: gen)
        pingWork = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, self.generation == gen else { return }
                t.sendPing { [weak self] err in
                    if err != nil { Task { @MainActor in self?.handleDrop(gen: gen) } }
                }
            }
        }
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask, gen: Int) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                switch result {
                case .failure:
                    self.handleDrop(gen: gen)
                case .success(let msg):
                    self.reconnectDelay = 1
                    if case .string(let s) = msg, let d = s.data(using: .utf8) { self.handle(d) }
                    else if case .data(let d) = msg { self.handle(d) }
                    self.receiveLoop(t, gen: gen)
                }
            }
        }
    }

    private struct Wire: Decodable {
        let type: String
        let channel: String?
        let data: [String: AnyCodable]?
        let at: Int64?

        func int64(_ key: String) -> Int64? {
            guard let v = data?[key]?.value else { return nil }
            switch v {
            case let i as Int64: return i
            case let i as Int: return Int64(i)
            case let d as Double: return Int64(d)
            case let s as String: return Int64(s)
            default: return nil
            }
        }
    }

    private func handle(_ data: Data) {
        guard let w = try? JSONDecoder().decode(Wire.self, from: data) else { return }
        if w.type == "server_time" {
            let ms = w.int64("server_time") ?? w.at ?? 0
            serverTimeClock.applyHandshake(serverTimeMs: ms)
            serverTimeOffsetMs = serverTimeClock.offsetMs
            return
        }
        // lot_card_tick may put fields at top-level or under data.
        var payload = w.data ?? [:]
        if w.type == LotCardSubscribePolicy.tickEvent || w.type == LotCardSubscribePolicy.nackEvent {
            if let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in top where k != "type" && k != "channel" && k != "data" && k != "at" {
                    payload[k] = AnyCodable(v)
                }
            }
        }
        let ev = WSEvent(type: w.type, channel: w.channel ?? "", data: payload,
                         at: Date(timeIntervalSince1970: Double(w.at ?? 0) / 1000))
        events.send(ev)
    }

    private func handleDrop(gen: Int) {
        guard generation == gen else { return }
        connected = false
        task = nil
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        reconnectWork = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private func sendJSON(_ obj: [String: String]) {
        guard let task, let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    private func sendObject(_ obj: [String: Any]) {
        guard let task, JSONSerialization.isValidJSONObject(obj),
              let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }
}
