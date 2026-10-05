import SwiftUI
import UIKit

/// 内存 + URLCache 两级缓存的图片加载器
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: cfg)
        cache.countLimit = 400
    }

    func image(for url: URL) async -> UIImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = inflight[url] { return await t.value }
        let t = Task<UIImage?, Never> {
            guard let (data, _) = try? await session.data(from: url), let img = UIImage(data: data) else { return nil }
            let decoded = await img.byPreparingForDisplay() ?? img
            return decoded
        }
        inflight[url] = t
        let img = await t.value
        inflight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// 解析服务端返回的图片地址：绝对 URL 直接用，`/uploads/..` 拼接 baseURL
enum ImageURL {
    static func resolve(_ s: String) -> URL? {
        if s.isEmpty { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        return URL(string: s, relativeTo: AppConfig.baseURL)?.absoluteURL
    }
}

/// 远程图片视图：带骨架占位与淡入
struct RemoteImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    init(_ urlString: String, contentMode: ContentMode = .fill) {
        self.urlString = urlString
        self.contentMode = contentMode
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                } else if failed {
                    ZStack {
                        Color.vFill
                        Image(systemName: "photo")
                            .foregroundStyle(Color.vTextTertiary)
                    }
                } else {
                    VSkeleton()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: urlString) {
            image = nil; failed = false
            guard let url = ImageURL.resolve(urlString) else { failed = true; return }
            if let img = await ImageLoader.shared.image(for: url) { image = img } else { failed = true }
        }
    }
}
