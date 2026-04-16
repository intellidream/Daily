using Daily.Models;
using System.Diagnostics;

namespace Daily.Services
{
    public class RssArticleService : IRssArticleService
    {
        private readonly IDatabaseService _databaseService;
        private readonly Supabase.Client _supabase;
        private bool _initialized = false;

        public List<LocalSavedArticle> ReadLaterItems { get; private set; } = new();
        public List<LocalSavedArticle> FavoriteItems { get; private set; } = new();

        public event Action? OnItemsChanged;

        public RssArticleService(IDatabaseService databaseService, Supabase.Client supabase)
        {
            _databaseService = databaseService;
            _supabase = supabase;
        }

        private string? GetUserId() => _supabase.Auth.CurrentUser?.Id;

        public async Task InitializeAsync()
        {
            if (_initialized) return;
            await _databaseService.InitializeAsync();
            await RefreshLocalCacheAsync();
            _initialized = true;
        }

        private async Task RefreshLocalCacheAsync()
        {
            var userId = GetUserId();
            if (userId == null)
            {
                ReadLaterItems = new();
                FavoriteItems = new();
                return;
            }

            var all = await _databaseService.Connection.Table<LocalSavedArticle>()
                .Where(a => a.UserId == userId && !a.IsDeleted)
                .ToListAsync();

            ReadLaterItems = all
                .Where(a => a.ArticleType == "ReadLater")
                .OrderByDescending(a => a.CreatedAt)
                .ToList();

            FavoriteItems = all
                .Where(a => a.ArticleType == "Favorite")
                .OrderByDescending(a => a.CreatedAt)
                .ToList();
        }

        public async Task SaveArticleAsync(RssItem item, string publicationName, string? publicationIconUrl, SavedArticleType type)
        {
            var userId = GetUserId();
            if (userId == null) return;

            await _databaseService.InitializeAsync();

            var articleType = type == SavedArticleType.ReadLater ? "ReadLater" : "Favorite";

            // Check if already exists (same URL + type + user)
            var existing = await _databaseService.Connection.Table<LocalSavedArticle>()
                .Where(a => a.UserId == userId && a.ArticleUrl == item.Link && a.ArticleType == articleType)
                .FirstOrDefaultAsync();

            if (existing != null)
            {
                if (existing.IsDeleted)
                {
                    // Re-enable soft-deleted entry
                    existing.IsDeleted = false;
                    existing.UpdatedAt = DateTime.UtcNow;
                    existing.SyncedAt = null; // Mark dirty
                    await _databaseService.Connection.UpdateAsync(existing);
                }
                else
                {
                    return; // Already saved
                }
            }
            else
            {
                var saved = new LocalSavedArticle
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = userId,
                    ArticleUrl = item.Link,
                    Title = item.Title,
                    ImageUrl = item.ImageUrl,
                    Description = item.Description,
                    Author = item.Author,
                    PublicationName = publicationName,
                    PublicationIconUrl = publicationIconUrl,
                    ArticleType = articleType,
                    ArticleDate = item.PublishDate,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    SyncedAt = null // Dirty
                };

                await _databaseService.Connection.InsertAsync(saved);
            }

            await RefreshLocalCacheAsync();
            OnItemsChanged?.Invoke();
            Console.WriteLine($"[RssArticleService] Saved article ({articleType}): {item.Title}");
        }

        public async Task RemoveArticleAsync(string articleUrl, SavedArticleType type)
        {
            var userId = GetUserId();
            if (userId == null) return;

            await _databaseService.InitializeAsync();

            var articleType = type == SavedArticleType.ReadLater ? "ReadLater" : "Favorite";

            var existing = await _databaseService.Connection.Table<LocalSavedArticle>()
                .Where(a => a.UserId == userId && a.ArticleUrl == articleUrl && a.ArticleType == articleType)
                .FirstOrDefaultAsync();

            if (existing != null)
            {
                existing.IsDeleted = true;
                existing.UpdatedAt = DateTime.UtcNow;
                existing.SyncedAt = null; // Mark dirty
                await _databaseService.Connection.UpdateAsync(existing);
            }

            await RefreshLocalCacheAsync();
            OnItemsChanged?.Invoke();
            Console.WriteLine($"[RssArticleService] Removed article ({articleType}): {articleUrl}");
        }

        public bool IsSaved(string articleUrl, SavedArticleType type)
        {
            var list = type == SavedArticleType.ReadLater ? ReadLaterItems : FavoriteItems;
            return list.Any(a => a.ArticleUrl == articleUrl);
        }

        public async Task ToggleArticleAsync(RssItem item, string publicationName, string? publicationIconUrl, SavedArticleType type)
        {
            if (IsSaved(item.Link, type))
            {
                await RemoveArticleAsync(item.Link, type);
            }
            else
            {
                await SaveArticleAsync(item, item.PublicationName ?? publicationName, item.PublicationIconUrl ?? publicationIconUrl, type);
            }
        }
    }
}
