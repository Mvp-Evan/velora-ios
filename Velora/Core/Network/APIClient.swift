import Foundation

enum HTTPMethod: String { case GET, POST, PUT, PATCH, DELETE }

struct APIError: LocalizedError, Identifiable {
    let id = UUID()
    let code: String
    let message: String
    let status: Int

    var errorDescription: String? { message }
    static func network(_ e: Error) -> APIError { APIError(code: "network", message: "网络连接失败，请检查网络", status: 0) }
    static let decoding = APIError(code: "decoding", message: "数据解析失败", status: 0)
    var isUnauthorized: Bool { status == 401 }
}

/// 请求体可以是 Encodable 或 multipart
enum RequestBody {
    case json(Encodable)
    case multipart(files: [(field: String, filename: String, mime: String, data: Data)])
    case none
}

/// 统一的 REST 客户端：async/await、snake_case 解码、401 自动刷新
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var refreshTask: Task<Bool, Never>?

    /// 由 SessionStore 注入
    var tokenProvider: (() -> String?)?
    var refreshHandler: (() async -> Bool)?

    init(session: URLSession = .shared) { self.session = session }

    func configure(tokenProvider: @escaping () -> String?, refreshHandler: @escaping () async -> Bool) {
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
    }

    /// 解析服务端 RFC3339 时间（兼容有/无小数秒）
    nonisolated static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let dt = APIClient.parseDate(s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Public

    func request<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [String: String?] = [:],
                               body: RequestBody = .none, auth: Bool = true, retry: Bool = true) async throws -> T {
        let req = try buildRequest(method, path, query: query, body: body, auth: auth)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw APIError.network(error) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, auth, retry, let refresh = refreshHandler {
            if await runRefresh(refresh) {
                return try await request(method, path, query: query, body: body, auth: auth, retry: false)
            }
        }
        if (200..<300).contains(status) {
            if T.self == Empty.self { return Empty() as! T }
            do {
                let env = try Self.decoder.decode(Envelope<T>.self, from: data)
                if let d = env.data { return d }
                if let e = env.error { throw APIError(code: e.code, message: e.message, status: status) }
                // data may legitimately be null (e.g. no tax profile)
                if let opt = Optional<Any>.none as? T { return opt }
                throw APIError.decoding
            } catch let e as APIError { throw e } catch {
                #if DEBUG
                print("[api] decode error \(path): \(error)\n\(String(data: data, encoding: .utf8) ?? "")")
                #endif
                throw APIError.decoding
            }
        }
        if let env = try? Self.decoder.decode(Envelope<Empty>.self, from: data), let e = env.error {
            throw APIError(code: e.code, message: e.message, status: status)
        }
        throw APIError(code: "http_\(status)", message: "请求失败 (\(status))", status: status)
    }

    /// 返回可空 data 的接口（如 GET /me/tax-profile）
    func requestOptional<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [String: String?] = [:], body: RequestBody = .none) async throws -> T? {
        let req = try buildRequest(method, path, query: query, body: body, auth: true)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, let refresh = refreshHandler, await runRefresh(refresh) {
            return try await requestOptional(method, path, query: query, body: body)
        }
        guard (200..<300).contains(status) else {
            if let env = try? Self.decoder.decode(Envelope<Empty>.self, from: data), let e = env.error {
                throw APIError(code: e.code, message: e.message, status: status)
            }
            throw APIError(code: "http_\(status)", message: "请求失败 (\(status))", status: status)
        }
        return try Self.decoder.decode(Envelope<T>.self, from: data).data
    }

    func download(_ path: String) async throws -> Data {
        let req = try buildRequest(.GET, path, query: [:], body: .none, auth: true)
        let (data, resp) = try await session.data(for: req)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { throw APIError(code: "download", message: "下载失败", status: 0) }
        return data
    }

    // MARK: - Internals

    private func runRefresh(_ refresh: @escaping () async -> Bool) async -> Bool {
        if let t = refreshTask { return await t.value }
        let t = Task { await refresh() }
        refreshTask = t
        let ok = await t.value
        refreshTask = nil
        return ok
    }

    private func buildRequest(_ method: HTTPMethod, _ path: String, query: [String: String?], body: RequestBody, auth: Bool) throws -> URLRequest {
        var comps = URLComponents(url: AppConfig.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method.rawValue
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth, let tok = tokenProvider?() { req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization") }
        switch body {
        case .none: break
        case .json(let enc):
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(AnyEncodable(enc))
        case .multipart(let files):
            let boundary = "velora-\(UUID().uuidString)"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var d = Data()
            for f in files {
                d.append("--\(boundary)\r\n".data(using: .utf8)!)
                d.append("Content-Disposition: form-data; name=\"\(f.field)\"; filename=\"\(f.filename)\"\r\n".data(using: .utf8)!)
                d.append("Content-Type: \(f.mime)\r\n\r\n".data(using: .utf8)!)
                d.append(f.data)
                d.append("\r\n".data(using: .utf8)!)
            }
            d.append("--\(boundary)--\r\n".data(using: .utf8)!)
            req.httpBody = d
        }
        return req
    }
}

struct AnyEncodable: Encodable {
    let wrapped: Encodable
    init(_ w: Encodable) { wrapped = w }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}

/// 松散字典作为 JSON body（key 原样输出，不做 snake_case 转换）
struct JSONDict: Encodable, ExpressibleByDictionaryLiteral {
    let dict: [String: Any?]
    init(_ d: [String: Any?]) { dict = d }
    init(dictionaryLiteral elements: (String, Any?)...) { dict = Dictionary(uniqueKeysWithValues: elements) }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (k, v) in dict {
            guard let v else { try c.encodeNil(forKey: DynamicKey(stringValue: k)!); continue }
            let key = DynamicKey(stringValue: k)!
            switch v {
            case let s as String: try c.encode(s, forKey: key)
            case let i as Int: try c.encode(i, forKey: key)
            case let i as Int64: try c.encode(i, forKey: key)
            case let d as Double: try c.encode(d, forKey: key)
            case let b as Bool: try c.encode(b, forKey: key)
            case let a as [String]: try c.encode(a, forKey: key)
            case let dt as Date: try c.encode(dt, forKey: key)
            default: try c.encode(String(describing: v), forKey: key)
            }
        }
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
