using System;

namespace Daily.Services
{
    public interface IDetailNavigationService
    {
        string CurrentView { get; }
        object? CurrentData { get; }
        event Action OnViewChanged;
        void NavigateTo(string view, object? data = null);
    }

    public class DetailNavigationService : IDetailNavigationService
    {
        public string CurrentView { get; private set; } = string.Empty;
        public object? CurrentData { get; private set; }
        public event Action OnViewChanged;

        public void NavigateTo(string view, object? data = null)
        {
            CurrentView = view;
            CurrentData = data;
            OnViewChanged?.Invoke();
        }
    }
}
