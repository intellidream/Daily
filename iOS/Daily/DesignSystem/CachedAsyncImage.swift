import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// High-performance in-memory image cache storing decoded `UIImage` textures to avoid main-thread image decoding hitches.
public final class ImageCacheManager {
    public static let shared = ImageCacheManager()
    private let cache = NSCache<NSURL, UIImage>()
    
    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 60 * 1024 * 1024 // 60MB
    }
    
    public func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }
    
    public func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// A lightweight, zero-latency image component that checks in-memory cache synchronously before falling back to network fetch.
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var uiImage: UIImage?
    
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        if let url = url, let cached = ImageCacheManager.shared.image(for: url) {
            _uiImage = State(initialValue: cached)
        }
    }
    
    public var body: some View {
        Group {
            if let uiImage = uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }
    
    private func loadImage() async {
        guard let url = url else { return }
        if let cached = ImageCacheManager.shared.image(for: url) {
            self.uiImage = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                ImageCacheManager.shared.insert(image, for: url)
                await MainActor.run {
                    self.uiImage = image
                }
            }
        } catch {
            // Keep placeholder on network error
        }
    }
}
