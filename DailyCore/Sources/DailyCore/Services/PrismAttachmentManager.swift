import Foundation
import Supabase
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

/// Manages local disk caching, client-side image downscaling/compression (max 1600px JPEG ~120 KB),
/// and on-demand Supabase Storage transfers for `prism-clips`.
public final class PrismAttachmentManager: @unchecked Sendable {
    public static let shared = PrismAttachmentManager()

    private let fileManager = FileManager.default
    public let bucketName = "prism-clips"

    public var cacheDirectoryURL: URL {
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GroupDefaults.suiteName) {
            let dir = container.appendingPathComponent("Library/Caches/PrismClips", isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("PrismClips", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        _ = cacheDirectoryURL
    }

    // MARK: - Compression & Downscaling (Zero Egress Waste)

    public struct CompressedImagePayload: Sendable {
        public let data: Data
        public let mimeType: String
        public let fileExtension: String
        public let width: Int
        public let height: Int
    }

    /// Downscales raw image data or snapshot bytes to max 1600px on the longest edge and encodes as lean JPEG (0.82 quality).
    public func compressImageData(_ rawData: Data, maxPixelSize: Int = 1600, quality: Double = 0.82) -> CompressedImagePayload? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }

        return encodeCGImage(cgImage, quality: quality)
        #else
        return CompressedImagePayload(data: rawData, mimeType: "image/jpeg", fileExtension: "jpg", width: 0, height: 0)
        #endif
    }

    #if canImport(ImageIO)
    public func encodeCGImage(_ cgImage: CGImage, quality: Double = 0.82) -> CompressedImagePayload? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, destOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return CompressedImagePayload(
            data: mutableData as Data,
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: cgImage.width,
            height: cgImage.height
        )
    }
    #endif

    // MARK: - Local Disk Cache

    public func localFileURL(for clipId: UUID, ext: String = "jpg") -> URL {
        cacheDirectoryURL.appendingPathComponent("\(clipId.uuidString.lowercased()).\(ext)")
    }

    public func existingLocalFileURL(for clip: PrismClip) -> URL? {
        for ext in ["jpg", "webp", "png"] {
            let candidate = localFileURL(for: clip.id, ext: ext)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    public func saveLocalImageData(_ data: Data, for clipId: UUID, ext: String = "jpg") throws -> URL {
        let url = localFileURL(for: clipId, ext: ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Supabase Storage Operations

    public func uploadClipImage(
        clipId: UUID,
        data: Data,
        mimeType: String = "image/jpeg",
        ext: String = "jpg",
        userId: String
    ) async throws -> String {
        let remotePath = "\(userId.lowercased())/\(clipId.uuidString.lowercased()).\(ext)"
        let client = SupabaseService.shared.client
        _ = try await client.storage
            .from(bucketName)
            .upload(
                remotePath,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: true)
            )
        return remotePath
    }

    public func downloadClipImage(for clip: PrismClip) async throws -> URL {
        if let cached = existingLocalFileURL(for: clip) {
            return cached
        }

        if let storagePath = clip.storagePath, !storagePath.isEmpty {
            let ext = (storagePath as NSString).pathExtension.isEmpty ? "jpg" : (storagePath as NSString).pathExtension.lowercased()
            let data = try await SupabaseService.shared.client.storage
                .from(bucketName)
                .download(path: storagePath)
            return try saveLocalImageData(data, for: clip.id, ext: ext)
        }

        if let previewUrlStr = clip.previewImageUrl, let previewUrl = URL(string: previewUrlStr) {
            let (data, _) = try await URLSession.shared.data(from: previewUrl)
            if let compressed = compressImageData(data) {
                return try saveLocalImageData(compressed.data, for: clip.id, ext: compressed.fileExtension)
            }
            return try saveLocalImageData(data, for: clip.id, ext: "jpg")
        }

        throw NSError(domain: "PrismAttachmentManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No image source available for clip"])
    }

    public func deleteClipAssets(for clip: PrismClip) async {
        for ext in ["jpg", "webp", "png"] {
            let url = localFileURL(for: clip.id, ext: ext)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }

        if let remotePath = clip.storagePath, !remotePath.isEmpty {
            _ = try? await SupabaseService.shared.client.storage
                .from(bucketName)
                .remove(paths: [remotePath])
        }
    }
}
