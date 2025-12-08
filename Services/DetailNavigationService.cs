using System;

namespace Daily.Services
{
    public interface IDetailNavigationService
    {
        string CurrentView { get; }
        string CurrentTitle { get; }
        object? CurrentData { get; }
        event Action OnViewChanged;
        event Action<string> OnOpenUrlRequest;
        void NavigateTo(string view, string title = "Detail View", object? data = null);
        void RequestOpenUrl(string url);
    }

    public class DetailNavigationService : IDetailNavigationService
    {
        public string CurrentView { get; private set; } = string.Empty;
        public string CurrentTitle { get; private set; } = "Detail View";
        public object? CurrentData { get; private set; }
        public event Action OnViewChanged;
        public event Action<string> OnOpenUrlRequest;

        public void NavigateTo(string view, string title = "Detail View", object? data = null)
        {
            CurrentView = view;
            CurrentTitle = title;
            CurrentData = data;
            OnViewChanged?.Invoke();
        }

        public void RequestOpenUrl(string url)
        {
            OnOpenUrlRequest?.Invoke(url);
        }
    }
}
