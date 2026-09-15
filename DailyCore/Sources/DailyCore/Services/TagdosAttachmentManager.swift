import Foundation
import Supabase

/// Manages local disk caching and cloud synchronization for Tagdos file/photo attachments.
public final class TagdosAttachmentManager: @unchecked Sendable {
    public static let shared = TagdosAttachmentManager()
    
    private let fileManager = FileManager.default
    private let bucketName = "tagdos-attachments"
    
    public var cacheDirectoryURL: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("TagdosAttachments", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    private init() {
        _ = cacheDirectoryURL
    }
    
    // MARK: - Local Cache Operations
    
    /// Returns the local file URL for an attachment if it exists on disk.
    public func getLocalFileURL(for attachment: TagDoAttachment) -> URL? {
        let fileName = attachment.localFileName ?? "\(attachment.id.uuidString)_\(attachment.fileName)"
        let fileURL = cacheDirectoryURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }
    
    /// Checks whether an attachment is already downloaded and present in the local cache.
    public func isDownloaded(_ attachment: TagDoAttachment) -> Bool {
        getLocalFileURL(for: attachment) != nil
    }
    
    /// Saves local raw data into the Tagdos cache directory and returns the file URL.
    public func saveLocalData(_ data: Data, for attachment: TagDoAttachment) throws -> URL {
        let fileName = attachment.localFileName ?? "\(attachment.id.uuidString)_\(attachment.fileName)"
        let targetURL = cacheDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }
    
    // MARK: - Supabase Storage Operations
    
    /// Uploads an attachment to Supabase Storage bucket `tagdos-attachments`.
    /// Returns the remote path string stored in metadata.
    public func uploadAttachment(
        _ attachment: TagDoAttachment,
        data: Data,
        userId: String
    ) async throws -> String {
        let safeFileName = attachment.fileName.replacingOccurrences(of: " ", with: "_")
        let remotePath = "\(userId)/stream_\(attachment.streamNumber)/\(attachment.id.uuidString)_\(safeFileName)"
        
        let client = SupabaseService.shared.client
        _ = try await client.storage
            .from(bucketName)
            .upload(
                remotePath,
                data: data,
                options: FileOptions(contentType: attachment.fileType, upsert: true)
            )
        
        return remotePath
    }
    
    /// Downloads an attachment on-demand from Supabase Storage and caches it locally.
    public func downloadAttachment(_ attachment: TagDoAttachment) async throws -> URL {
        guard let remotePath = attachment.remotePath, !remotePath.isEmpty else {
            throw NSError(domain: "TagdosAttachmentManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No remote path configured."])
        }
        
        let client = SupabaseService.shared.client
        let data = try await client.storage
            .from(bucketName)
            .download(path: remotePath)
        
        let localURL = try saveLocalData(data, for: attachment)
        return localURL
    }
    
    /// Deletes an attachment from both local cache and remote Supabase Storage.
    public func deleteAttachment(_ attachment: TagDoAttachment) async {
        // 1. Delete local file
        if let localURL = getLocalFileURL(for: attachment) {
            try? fileManager.removeItem(at: localURL)
        }
        
        // 2. Delete from Supabase Storage
        if let remotePath = attachment.remotePath, !remotePath.isEmpty {
            let client = SupabaseService.shared.client
            _ = try? await client.storage
                .from(bucketName)
                .remove(paths: [remotePath])
        }
    }
}
