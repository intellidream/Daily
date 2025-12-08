using System;

namespace Daily.Services
{
    public interface IDetailNavigationService
    {
        string CurrentView { get; }
        string CurrentTitle { get; }
        object? CurrentData { get; }
        event Action OnViewChanged;
        void NavigateTo(string view, string title = "Detail View", object? data = null);
    }

    public class DetailNavigationService : IDetailNavigationService
    {
        public string CurrentView { get; private set; } = string.Empty;
        public string CurrentTitle { get; private set; } = "Detail View";
        public object? CurrentData { get; private set; }
        public event Action OnViewChanged;

        public void NavigateTo(string view, string title = "Detail View", object? data = null)
        {
            CurrentView = view;
            CurrentTitle = title;
            CurrentData = data;
            OnViewChanged?.Invoke();
        }
    }
}
