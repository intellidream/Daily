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
        let currentUserId = AuthService.shared.currentUser?.id
            ?? GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id")
            ?? "guest"
        let deterministicId = generateDeterministicGuid(userId: currentUserId, url: article.link, type: type)
        
        if let idx = allSavedArticles.firstIndex(where: {
            ($0.id.lowercased() == deterministicId.lowercased() || $0.articleUrl == article.link) &&
            $0.articleType == type.rawValue
        }) {
            var item = allSavedArticles[idx]
            item.isDeleted.toggle()
            item.updatedAt = Date()
            allSavedArticles[idx] = item
            
            if currentUserId != "guest" {
                Task {
                    await pushSavedArticleToSupabase(item)
                }
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
            
            if currentUserId != "guest" {
                Task {
                    await pushSavedArticleToSupabase(newItem)
                }
            }
        }
    }
    
    // MARK: - Deterministic GUID (WinUI Parity)
    
    public func generateDeterministicGuid(userId: String, url: String, type: SavedArticleType) -> String {
        let input = "\(userId.lowercased()):\(url):\(type.rawValue)"
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        let bytes = Array(digest)
        // Convert 16 bytes MD5 hash to UUID string
        let uuidTuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidTuple).uuidString.lowercased()
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
        let session = try? await SupabaseService.shared.client.auth.session
        let userId = session?.user.id.uuidString.lowercased()
            ?? AuthService.shared.currentUser?.id
            ?? GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id")
        
        guard let effectiveUserId = userId, effectiveUserId != "guest" else {
            print("[SavedArticlesService] No authenticated user session, skipping Supabase sync.")
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let client = SupabaseService.shared.client
            let res = try await client
                .from("rss_saved_articles")
                .select()
                .eq("user_id", value: effectiveUserId)
                .execute()
            
            let response = try JSONDecoder().decode([SavedArticle].self, from: res.data)
            print("[SavedArticlesService] Successfully synced \(response.count) saved articles from Supabase.")
            
            // Merge remote items with local items
            var merged = allSavedArticles
            for remote in response {
                if let idx = merged.firstIndex(where: {
                    $0.id.lowercased() == remote.id.lowercased() ||
                    ($0.articleUrl == remote.articleUrl && $0.articleType == remote.articleType)
                }) {
                    let local = merged[idx]
                    let remoteTime = remote.updatedAt ?? remote.createdAt
                    let localTime = local.updatedAt ?? local.createdAt
                    if remoteTime >= localTime {
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
        guard article.userId != "guest" else { return }
        do {
            let client = SupabaseService.shared.client
            try await client
                .from("rss_saved_articles")
                .upsert(article)
                .execute()
            print("[SavedArticlesService] Successfully upserted article \(article.id) to Supabase.")
        } catch {
            print("[SavedArticlesService] Failed to upsert article to Supabase: \(error)")
        }
    }
}
