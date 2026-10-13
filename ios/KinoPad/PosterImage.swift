import SwiftUI
import UIKit

enum PosterImageRequestFactory {
    static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 20
        )
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://kino.watch/", forHTTPHeaderField: "Referer")
        request.setValue("WooF.Play/0.3.6 (\(AppDevice.platformName); iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

private actor PosterImagePipeline {
    static let shared = PosterImagePipeline()

    private let memoryCache = NSCache<NSURL, NSData>()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 160 * 1_024 * 1_024
        )
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }

        let (data, response) = try await session.data(for: PosterImageRequestFactory.makeRequest(for: url))
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty
        else { throw URLError(.badServerResponse) }

        memoryCache.setObject(data as NSData, forKey: url as NSURL)
        return data
    }
}

struct PosterImage: View {
    let urls: [URL]
    var placeholderSystemImage = "film"

    @State private var image: UIImage?

    init(url: URL?, placeholderSystemImage: String = "film") {
        urls = url.map { [$0] } ?? []
        self.placeholderSystemImage = placeholderSystemImage
    }

    init(urls: [URL], placeholderSystemImage: String = "film") {
        self.urls = urls
        self.placeholderSystemImage = placeholderSystemImage
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [KinoPadTheme.sidebar, KinoPadTheme.canvas],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: placeholderSystemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
        .task(id: urls) {
            image = nil
            for url in urls {
                guard !Task.isCancelled else { return }
                if let data = try? await PosterImagePipeline.shared.data(for: url),
                   let decoded = UIImage(data: data) {
                    image = decoded
                    return
                }
            }
        }
    }
}
