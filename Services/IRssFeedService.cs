using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily.Services
{
    public interface IRssFeedService
    {
        List<FeedSource> Feeds { get; }
        FeedSource CurrentFeed { get; }
        List<RssItem> Items { get; }
        bool IsLoading { get; }
        string? Error { get; }

        event Action OnFeedChanged;
        event Action OnItemsUpdated;

        Task LoadFeedAsync(FeedSource feed, bool forceRefresh = false);
        Task ReloadCurrentFeedAsync();
        void SelectFeed(FeedSource feed);
        Task<RssItem> FetchFullArticleAsync(string url);
        Task InitializeCustomFeedsAsync();
        Task<List<RssItem>> FetchFeedItemsAsync(FeedSource feed);
        Task<List<LocalRssSubscription>> GetSubscriptionsAsync();
        Task SaveSubscriptionAsync(LocalRssSubscription subscription);
        Task DeleteSubscriptionAsync(string id);
        Task ReorderSubscriptionsAsync(List<LocalRssSubscription> subscriptions);
        Task<List<FeedSearchResult>> DiscoverFeedsAsync(string query);
        Task AddFeedAsync(string url, string name, string category, string userId);
        void SetItemsAndNotify(List<RssItem> items);
    }
}
