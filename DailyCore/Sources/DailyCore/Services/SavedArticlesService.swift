import Foundation
import CryptoKit
import Supabase

/// Manages Read Later and Favorite articles with local offline persistence and Supabase cross-platform synchronization.
@MainActor
public final class SavedArticlesService: ObservableObject {
    public static let shared = SavedArticlesService()
    
    @Published public private(set) var readLaterArticles: [SavedArticle] = []
    @Published public private(set) var favoriteArticles: [SavedArticle] = []
    @Published public private(set) var isSyncing = false
    
    private let localStorageKey = "dayone_saved_articles_cache_v1"
    private var allSavedArticles: [SavedArticle] = [] {
        didSet {
            updateFilteredLists()
            saveToLocalStorage()
        }
    }
    
    public init() {
        loadFromLocalStorage()
        Task {
            await syncWithSupabase()
        }
    }
    
    // MARK: - Query Status
    
    public func isReadLater(url: String) -> Bool {
        readLaterArticles.contains { $0.articleUrl == url && !$0.isDeleted }
    }
    
    public func isFavorite(url: String) -> Bool {
        favoriteArticles.contains { $0.articleUrl == url && !$0.isDeleted }
    }
    
    // MARK: - Toggles
    
    public func toggleReadLater(for article: NewsArticle) {
        toggle(article: article, type: .readLater)
    }
    
    public func toggleFavorite(for article: NewsArticle) {
        toggle(article: article, type: .favorite)
    }
    
    private func toggle(article: NewsArticle, type: SavedArticleType) {
        let currentUserId = AuthService.shared.currentUser?.id ?? "guest"
        let deterministicId = generateDeterministicGuid(userId: currentUserId, url: article.link, type: type)
        
        if let idx = allSavedArticles.firstIndex(where: { $0.articleUrl == article.link && $0.articleType == type.rawValue }) {
            var item = allSavedArticles[idx]
            item.isDeleted.toggle()
            item.updatedAt = Date()
            allSavedArticles[idx] = item
            
            Task {
                await pushSavedArticleToSupabase(item)
            }
        } else {
            let newItem = SavedArticle(
                id: deterministicId,
                userId: currentUserId,
                articleUrl: article.link,
                title: article.title,
                imageUrl: article.imageUrl,
                description: article.description,
                author: article.author,
                publicationName: article.publicationName ?? "News",
                publicationIconUrl: article.publicationIconUrl,
                articleType: type,
                articleDate: article.publishDate,
                createdAt: Date(),
                updatedAt: Date(),
                isDeleted: false
            )
            allSavedArticles.append(newItem)
            
            Task {
                await pushSavedArticleToSupabase(newItem)
            }
        }
    }
    
    // MARK: - Deterministic GUID (WinUI Parity)
    
    public func generateDeterministicGuid(userId: String, url: String, type: SavedArticleType) -> String {
        let input = "\(userId):\(url):\(type.rawValue)"
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        let bytes = Array(digest)
        // Convert 16 bytes MD5 hash to UUID string
        let uuidTuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidTuple).uuidString
    }
    
    // MARK: - Filtering & Persistence
    
    private func updateFilteredLists() {
        readLaterArticles = allSavedArticles
            .filter { $0.articleType == SavedArticleType.readLater.rawValue && !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
        
        favoriteArticles = allSavedArticles
            .filter { $0.articleType == SavedArticleType.favorite.rawValue && !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    private func saveToLocalStorage() {
        do {
            let data = try JSONEncoder().encode(allSavedArticles)
            GroupDefaults.shared.userDefaults.set(data, forKey: localStorageKey)
        } catch {
            print("[SavedArticlesService] Failed to save local cache: \(error)")
        }
    }
    
    private func loadFromLocalStorage() {
        guard let data = GroupDefaults.shared.userDefaults.data(forKey: localStorageKey) else { return }
        do {
            allSavedArticles = try JSONDecoder().decode([SavedArticle].self, from: data)
            updateFilteredLists()
        } catch {
            print("[SavedArticlesService] Failed to load local cache: \(error)")
        }
    }
    
    // MARK: - Supabase Synchronization
    
    public func syncWithSupabase() async {
        guard let user = AuthService.shared.currentUser else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let client = SupabaseService.shared.client
            let res = try await client
                .from("rss_saved_articles")
                .select()
                .eq("user_id", value: user.id)
                .execute()
            
            let response = try JSONDecoder().decode([SavedArticle].self, from: res.data)
            
            // Merge remote items with local items
            var merged = allSavedArticles
            for remote in response {
                if let idx = merged.firstIndex(where: { $0.id == remote.id }) {
                    // Update if remote is newer
                    if let remoteUpdated = remote.updatedAt,
                       let localUpdated = merged[idx].updatedAt,
                       remoteUpdated > localUpdated {
                        merged[idx] = remote
                    }
                } else {
                    merged.append(remote)
                }
            }
            
            allSavedArticles = merged
        } catch {
            print("[SavedArticlesService] Supabase sync error: \(error)")
        }
    }
    
    private func pushSavedArticleToSupabase(_ article: SavedArticle) async {
        guard AuthService.shared.isAuthenticated else { return }
        do {
            let client = SupabaseService.shared.client
            try await client
                .from("rss_saved_articles")
                .upsert(article)
                .execute()
        } catch {
            print("[SavedArticlesService] Failed to upsert article to Supabase: \(error)")
        }
    }
}
