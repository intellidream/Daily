using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Daily.Models;
using Daily.Services;

namespace Daily.ViewModels;

public class RssFeedViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IRssFeedService _service;
    private readonly int _maxItems;

    private FeedSource? _selectedFeed;
    private RssItem? _selectedItem;
    private bool _isArticleLoading;
    private bool _isDisposed;

    public ObservableCollection<FeedSource> Feeds { get; }
    public ObservableCollection<RssItem> DisplayItems { get; } = new();

    public event PropertyChangedEventHandler? PropertyChanged;

    public RssFeedViewModel(IRssFeedService service, int maxItems = 0)
    {
        _service = service;
        _maxItems = maxItems;

        Feeds = new ObservableCollection<FeedSource>(_service.Feeds);
        _selectedFeed = _service.CurrentFeed;

        RefreshCommand = new Command(async () => await _service.ReloadCurrentFeedAsync());
        ClearSelectionCommand = new Command(() => SelectedItem = null);
        OpenLinkCommand = new Command(async () => await OpenSelectedLinkAsync(), () => SelectedItem != null);

        _service.OnItemsUpdated += OnItemsUpdated;
        _service.OnFeedChanged += OnFeedChanged;

        SyncItems();

        if (_service.Items.Count == 0 && _service.CurrentFeed != null && !_service.IsLoading && string.IsNullOrEmpty(_service.Error))
        {
            _ = _service.ReloadCurrentFeedAsync();
        }
    }

    public FeedSource? SelectedFeed
    {
        get => _selectedFeed;
        set
        {
            if (SetProperty(ref _selectedFeed, value) && value != null)
            {
                _service.SelectFeed(value);
            }
        }
    }

    public RssItem? SelectedItem
    {
        get => _selectedItem;
        set
        {
            if (SetProperty(ref _selectedItem, value))
            {
                OnPropertyChanged(nameof(HasSelection));
                OnPropertyChanged(nameof(IsListVisible));
                OnPropertyChanged(nameof(IsDetailVisible));
                OnPropertyChanged(nameof(HasSelectedImage));
                ((Command)OpenLinkCommand).ChangeCanExecute();
            }
        }
    }

    public bool IsArticleLoading
    {
        get => _isArticleLoading;
        private set => SetProperty(ref _isArticleLoading, value);
    }

    public bool IsLoading => _service.IsLoading;
    public string? Error => _service.Error;
    public bool HasError => !string.IsNullOrWhiteSpace(_service.Error);

    public bool HasSelection => SelectedItem != null;
    public bool IsListVisible => SelectedItem == null;
    public bool IsDetailVisible => SelectedItem != null;
    public bool HasSelectedImage => !string.IsNullOrWhiteSpace(SelectedItem?.ImageUrl);

    public ICommand RefreshCommand { get; }
    public ICommand ClearSelectionCommand { get; }
    public ICommand OpenLinkCommand { get; }

    public async Task SelectItemAsync(RssItem item)
    {
        SelectedItem = item;

        if (!string.IsNullOrWhiteSpace(item.Link))
        {
            IsArticleLoading = true;
            var fullArticle = await _service.FetchFullArticleAsync(item.Link);
            IsArticleLoading = false;

            if (!string.IsNullOrWhiteSpace(fullArticle.Content))
            {
                SelectedItem = fullArticle;
            }
        }
    }

    private void OnItemsUpdated()
    {
        MainThread.BeginInvokeOnMainThread(() =>
        {
            SyncItems();
            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(Error));
            OnPropertyChanged(nameof(HasError));
        });
    }

    private void OnFeedChanged()
    {
        MainThread.BeginInvokeOnMainThread(() =>
        {
            SelectedFeed = _service.CurrentFeed;
            SyncItems();
        });
    }

    private void SyncItems()
    {
        DisplayItems.Clear();
        var items = _service.Items ?? new List<RssItem>();
        foreach (var item in _maxItems > 0 ? items.Take(_maxItems) : items)
        {
            DisplayItems.Add(item);
        }
    }

    private async Task OpenSelectedLinkAsync()
    {
        if (SelectedItem?.Link == null)
        {
            return;
        }

        await Launcher.OpenAsync(SelectedItem.Link);
    }

    private bool SetProperty<T>(ref T storage, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(storage, value))
        {
            return false;
        }

        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _service.OnItemsUpdated -= OnItemsUpdated;
        _service.OnFeedChanged -= OnFeedChanged;
        _isDisposed = true;
    }
}
