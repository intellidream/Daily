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
        
        bool IsBrowserOpen { get; }
        bool IsReaderMode { get; }
        
        event Action OnViewChanged;
        event Action<string> OnOpenUrlRequest;
        event Action OnArticleLinkChanged;
        event Action<bool> OnBrowserStateChanged;
        event Action<bool> OnReaderModeChanged;
        event Action OnReaderModeToggleRequest;
        event Action<double> OnToolbarHeightChanged;

        void NavigateTo(string view, string title = "Detail View", object? data = null);
        void RequestOpenUrl(string url);
        void SetCurrentArticle(string? link, string? title = null);
        void SetBrowserState(bool isOpen);
        void SetReaderMode(bool isEnabled);
        void ToggleReaderMode();
        void SetToolbarHeight(double height);
    }

    public class DetailNavigationService : IDetailNavigationService
    {
        public string CurrentView { get; private set; } = string.Empty;
        public string CurrentTitle { get; private set; } = "Detail View";
        public object? CurrentData { get; private set; }
        
        public string? CurrentArticleLink { get; private set; }
        public string? CurrentArticleTitle { get; private set; }
        
        public bool IsBrowserOpen { get; private set; }
        public bool IsReaderMode { get; private set; }

        public event Action OnViewChanged;
        public event Action<string> OnOpenUrlRequest;
        public event Action OnArticleLinkChanged;
        public event Action<bool> OnBrowserStateChanged;
        public event Action<bool> OnReaderModeChanged;
        public event Action OnReaderModeToggleRequest;
        public event Action<double> OnToolbarHeightChanged;

        public void NavigateTo(string view, string title = "Detail View", object? data = null)
        {
            CurrentView = view;
            CurrentTitle = title;
            CurrentData = data;
            // Reset article link on navigation change unless intended otherwise? 
            // Better to let the component clear it or keep it if it's the same view context.
            // For safety, let's NOT clear it here automatically unless we change View Type.
            if (view != "RssFeed" && view != "Media") 
            {
                CurrentArticleLink = null;
                CurrentArticleTitle = null;
            }
            
            // Explicitly close browser on main nav change
            if (IsBrowserOpen)
            {
                SetBrowserState(false);
            }

            OnViewChanged?.Invoke();
        }

        public void RequestOpenUrl(string url)
        {
            OnOpenUrlRequest?.Invoke(url);
            // Auto open browser state
            SetBrowserState(true);
        }

        public void SetCurrentArticle(string? link, string? title = null)
        {
            if (CurrentArticleLink == link) return;
            CurrentArticleLink = link;
            CurrentArticleTitle = title;
            // Reset browser when changing articles
            if (IsBrowserOpen) SetBrowserState(false);
            
            OnArticleLinkChanged?.Invoke();
        }

        public void SetBrowserState(bool isOpen)
        {
            if (IsBrowserOpen == isOpen) return;
            IsBrowserOpen = isOpen;
            
            // Reset Reader Mode on open/close
            if (!isOpen) IsReaderMode = false;
            
            OnBrowserStateChanged?.Invoke(isOpen);
        }

        public void SetReaderMode(bool isEnabled)
        {
            if (IsReaderMode == isEnabled) return;
            IsReaderMode = isEnabled;
            OnReaderModeChanged?.Invoke(isEnabled);
        }
        
        public void ToggleReaderMode()
        {
            SetReaderMode(!IsReaderMode);
            OnReaderModeToggleRequest?.Invoke();
        }

        public void SetToolbarHeight(double height)
        {
            OnToolbarHeightChanged?.Invoke(height);
        }
    }
}
