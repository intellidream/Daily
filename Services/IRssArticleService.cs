using Daily.Models;

namespace Daily.Services
{
    public interface IRssArticleService
    {
        List<LocalSavedArticle> ReadLaterItems { get; }
        List<LocalSavedArticle> FavoriteItems { get; }

        event Action OnItemsChanged;

        Task InitializeAsync();
        Task SaveArticleAsync(RssItem item, string publicationName, string? publicationIconUrl, SavedArticleType type);
        Task RemoveArticleAsync(string articleUrl, SavedArticleType type);
        bool IsSaved(string articleUrl, SavedArticleType type);
        Task ToggleArticleAsync(RssItem item, string publicationName, string? publicationIconUrl, SavedArticleType type);
    }
}
