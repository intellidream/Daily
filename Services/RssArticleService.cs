using Daily.Models;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class RssArticleService : IRssArticleService
    {
        private readonly IDatabaseService _databaseService;
        private readonly Supabase.Client _supabase;
        private readonly ISyncService _syncService;
        private bool _initialized = false;

        public List<LocalSavedArticle> ReadLaterItems { get; private set; } = new();
        public List<LocalSavedArticle> FavoriteItems { get; private set; } = new();

        public event Action? OnItemsChanged;

        public RssArticleService(IDatabaseService databaseService, Supabase.Client supabase, ISyncService syncService)
        {
            _databaseService = databaseService;
            _supabase = supabase;
            _syncService = syncService;
        }

        private string? GetUserId() => _supabase.Auth.CurrentUser?.Id;

        private Guid GenerateGuid(string input)
        {
            using (MD5 md5 = MD5.Create())
            {
                byte[] hash = md5.ComputeHash(Encoding.UTF8.GetBytes(input));
                return new Guid(hash);
            }
        }

        private async Task DeduplicateSavedArticlesAsync()
        {
            var userId = GetUserId();
            if (userId == null) return;

            try
            {
                // Fetch all non-deleted saved articles for the user
                var all = await _databaseService.Connection.Table<LocalSavedArticle>()
                    .Where(a => a.UserId == userId && !a.IsDeleted)
                    .ToListAsync();

                // Group by ArticleUrl and ArticleType to find duplicates
                var groups = all.GroupBy(a => (a.ArticleUrl, a.ArticleType))
                                .Where(g => g.Count() > 1)
                                .ToList();

                if (!groups.Any()) return;

                Console.WriteLine($"[RssArticleService] Found {groups.Count} duplicated saved article groups. Starting deduplication...");

                var toInsert = new List<LocalSavedArticle>();
                var toUpdate = new List<LocalSavedArticle>();

                foreach (var group in groups)
                {
                    var articleUrl = group.Key.ArticleUrl;
                    var articleType = group.Key.ArticleType;
                    var deterministicId = GenerateGuid(userId + ":" + articleUrl + ":" + articleType).ToString();

                    var items = group.ToList();
                    var canonical = items.FirstOrDefault(x => x.Id == deterministicId);

                    if (canonical == null)
                    {
                        // Select the best item (newest UpdatedAt or CreatedAt)
                        var best = items.OrderByDescending(x => x.UpdatedAt ?? x.CreatedAt).First();

                        // Create canonical entry with the deterministic GUID
                        canonical = new LocalSavedArticle
                        {
                            Id = deterministicId,
                            UserId = best.UserId,
                            ArticleUrl = best.ArticleUrl,
                            Title = best.Title,
                            ImageUrl = best.ImageUrl,
                            Description = best.Description,
                            Author = best.Author,
                            PublicationName = best.PublicationName,
                            PublicationIconUrl = best.PublicationIconUrl,
                            ArticleType = best.ArticleType,
                            ArticleDate = best.ArticleDate,
                            CreatedAt = best.CreatedAt,
                            UpdatedAt = DateTime.UtcNow,
                            SyncedAt = null // Needs to sync to Supabase
                        };
                        toInsert.Add(canonical);
                    }

                    // Mark all other duplicates as deleted
                    foreach (var item in items)
                    {
                        if (item.Id != deterministicId)
                        {
                            item.IsDeleted = true;
                            item.UpdatedAt = DateTime.UtcNow;
                            item.SyncedAt = null; // Needs to sync deletion to Supabase
                            toUpdate.Add(item);
                        }
                    }
                }

                if (toInsert.Any() || toUpdate.Any())
                {
                    await _databaseService.Connection.RunInTransactionAsync(tran =>
                    {
                        foreach (var item in toInsert)
                        {
                            tran.InsertOrReplace(item);
                        }
                        foreach (var item in toUpdate)
                        {
                            tran.Update(item);
                        }
                    });
                    Console.WriteLine($"[RssArticleService] Deduplicated: inserted/replaced {toInsert.Count} canonical entries and marked {toUpdate.Count} duplicates as deleted.");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[RssArticleService] Deduplication failed: {ex.Message}");
            }
        }

        public async Task InitializeAsync()
        {
            if (_initialized) return;
            await _databaseService.InitializeAsync();
            await DeduplicateSavedArticlesAsync();
            await RefreshLocalCacheAsync();

            _syncService.OnSavedArticlesPulled += () =>
            {
                _ = Task.Run(async () =>
                {
                    await RefreshLocalCacheAsync();
                    OnItemsChanged?.Invoke();
                });
            };

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
                var id = GenerateGuid(userId + ":" + item.Link + ":" + articleType).ToString();
                var saved = new LocalSavedArticle
                {
                    Id = id,
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

                await _databaseService.Connection.InsertOrReplaceAsync(saved);
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
