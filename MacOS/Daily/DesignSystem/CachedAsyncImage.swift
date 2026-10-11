import SwiftUI
import AppKit

/// High-performance in-memory image cache storing decoded `NSImage` instances for macOS.
public final class ImageCacheManager {
    public static let shared = ImageCacheManager()
    private let cache = NSCache<NSURL, NSImage>()
    
    private init() {
        cache.countLimit = 250
        cache.totalCostLimit = 120 * 1024 * 1024 // 120MB
    }
    
    public func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }
    
    public func insert(_ image: NSImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// A lightweight, zero-latency image component that checks in-memory cache synchronously before falling back to network fetch on macOS.
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var nsImage: NSImage?
    
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        if let url = url, let cached = ImageCacheManager.shared.image(for: url) {
            _nsImage = State(initialValue: cached)
        }
    }
    
    public var body: some View {
        Group {
            if let nsImage = nsImage {
                content(Image(nsImage: nsImage))
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
            self.nsImage = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                ImageCacheManager.shared.insert(image, for: url)
                await MainActor.run {
                    self.nsImage = image
                }
            }
        } catch {
            // Keep placeholder on network error
        }
    }
}
