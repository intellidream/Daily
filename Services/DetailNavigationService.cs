using System;

namespace Daily.Services
{
    public interface IDetailNavigationService
    {
        string CurrentView { get; }
        string CurrentTitle { get; }
        object? CurrentData { get; }
        string? CurrentArticleLink { get; }
        string? CurrentArticleTitle { get; }
        event Action OnViewChanged;
        event Action<string> OnOpenUrlRequest;
        event Action OnArticleLinkChanged;
        void NavigateTo(string view, string title = "Detail View", object? data = null);
        void RequestOpenUrl(string url);
        void SetCurrentArticle(string? link, string? title = null);
    }

    public class DetailNavigationService : IDetailNavigationService
    {
        public string CurrentView { get; private set; } = string.Empty;
        public string CurrentTitle { get; private set; } = "Detail View";
        public object? CurrentData { get; private set; }
        public string? CurrentArticleLink { get; private set; }
        public string? CurrentArticleTitle { get; private set; }
        public event Action OnViewChanged;
        public event Action<string> OnOpenUrlRequest;
        public event Action OnArticleLinkChanged;

        public void NavigateTo(string view, string title = "Detail View", object? data = null)
        {
            CurrentView = view;
            CurrentTitle = title;
            CurrentData = data;
            // Reset article link on navigation change unless intended otherwise? 
            // Better to let the component clear it or keep it if it's the same view context.
            // For safety, let's NOT clear it here automatically unless we change View Type.
            if (view != "RssFeed") 
            {
                CurrentArticleLink = null;
                CurrentArticleTitle = null;
            }
            
            OnViewChanged?.Invoke();
        }

        public void RequestOpenUrl(string url)
        {
            OnOpenUrlRequest?.Invoke(url);
        }

        public void SetCurrentArticle(string? link, string? title = null)
        {
            if (CurrentArticleLink == link) return;
            CurrentArticleLink = link;
            CurrentArticleTitle = title;
            OnArticleLinkChanged?.Invoke();
        }
    }
}
