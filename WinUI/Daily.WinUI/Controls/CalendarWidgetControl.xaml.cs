using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily_WinUI.Services;
using Daily.Models;

namespace Daily_WinUI.Controls
{
    public class CalendarWidgetItem : INotifyPropertyChanged
    {
        public string Id { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Details { get; set; } = string.Empty;
        public DateTime SortDate { get; set; }
        public string Color { get; set; } = "#512BD4";
        public bool IsTodo { get; set; }
        
        private bool _isCompleted;
        public bool IsCompleted
        {
            get => _isCompleted;
            set
            {
                if (_isCompleted != value)
                {
                    _isCompleted = value;
                    OnPropertyChanged();
                }
            }
        }
        
        public string IconGlyph { get; set; } = string.Empty;
 
        public Microsoft.UI.Xaml.Media.Brush ColorBrush
        {
            get
            {
                try
                {
                    string hex = Color.Replace("#", "");
                    byte a = 255;
                    byte r = 255;
                    byte g = 255;
                    byte b = 255;
                    if (hex.Length == 8)
                    {
                        a = Convert.ToByte(hex.Substring(0, 2), 16);
                        r = Convert.ToByte(hex.Substring(2, 2), 16);
                        g = Convert.ToByte(hex.Substring(4, 2), 16);
                        b = Convert.ToByte(hex.Substring(6, 2), 16);
                    }
                    else if (hex.Length == 6)
                    {
                        r = Convert.ToByte(hex.Substring(0, 2), 16);
                        g = Convert.ToByte(hex.Substring(2, 2), 16);
                        b = Convert.ToByte(hex.Substring(4, 2), 16);
                    }
                    return new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(a, r, g, b));
                }
                catch
                {
                    return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
                }
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected void OnPropertyChanged([CallerMemberName] string? name = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    public sealed partial class CalendarWidgetControl : UserControl, INotifyPropertyChanged
    {
        private ICalendarService? _calendarService;
        private Daily.Services.IRefreshService? _refreshService;
        private readonly SemaphoreSlim _loadLock = new(1, 1);
        private bool _isLoading;

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

        public bool IsLoading
        {
            get => _isLoading;
            set { _isLoading = value; OnPropertyChanged(); }
        }

        public ObservableCollection<CalendarWidgetItem> UpcomingItems { get; } = new();
        public ObservableCollection<CalendarWidgetItem> SmallItems { get; } = new();
        public ObservableCollection<CalendarWidgetItem> NormalItems { get; } = new();

        private bool _hasSmallItems;
        public bool HasSmallItems
        {
            get => _hasSmallItems;
            set { _hasSmallItems = value; OnPropertyChanged(); }
        }

        private bool _hasNormalItems;
        public bool HasNormalItems
        {
            get => _hasNormalItems;
            set { _hasNormalItems = value; OnPropertyChanged(); }
        }

        private bool _hasUpcomingItems;
        public bool HasUpcomingItems
        {
            get => _hasUpcomingItems;
            set { _hasUpcomingItems = value; OnPropertyChanged(); }
        }

        public string TodayMonth => DateTime.Today.ToString("MMM").ToUpperInvariant();
        public string TodayDayNumber => DateTime.Today.Day.ToString();
        public string TodayDayName => DateTime.Today.ToString("dddd");

        public CalendarWidgetControl()
        {
            this.InitializeComponent();

            if (!Windows.ApplicationModel.DesignMode.DesignModeEnabled)
            {
                _calendarService = App.Current.Services.GetRequiredService<ICalendarService>();
                _refreshService = App.Current.Services.GetRequiredService<Daily.Services.IRefreshService>();

                this.Loaded += OnLoaded;
                this.Unloaded += OnUnloaded;
                this.SizeChanged += OnSizeChanged;
            }
        }

        private async void OnLoaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested += OnRefreshRequested;
            }
            if (_calendarService != null)
            {
                _calendarService.OnCalendarDataChanged += OnCalendarDataChanged;
            }
            await LoadDataAsync();
            UpdateAdaptiveState(this.ActualWidth, this.ActualHeight);
        }

        private void OnUnloaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested -= OnRefreshRequested;
            }
            if (_calendarService != null)
            {
                _calendarService.OnCalendarDataChanged -= OnCalendarDataChanged;
            }
        }

        private void OnCalendarDataChanged()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                await LoadDataAsync(showSpinner: false);
            });
        }

        private Task OnRefreshRequested()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                await LoadDataAsync();
            });
            return Task.CompletedTask;
        }

        private void OnSizeChanged(object sender, SizeChangedEventArgs e)
        {
            UpdateAdaptiveState(e.NewSize.Width, e.NewSize.Height);
        }

        private void UpdateAdaptiveState(double width, double height)
        {
            if (width <= 0 || height <= 0) return;

            bool isWide = width >= 450;
            bool isTall = height >= 250;

            if (isWide && isTall)
            {
                VisualStateManager.GoToState(this, "LargeState", false);
            }
            else if (isWide)
            {
                VisualStateManager.GoToState(this, "NormalState", false); // Wide
            }
            else if (isTall)
            {
                VisualStateManager.GoToState(this, "TallState", false);
            }
            else
            {
                VisualStateManager.GoToState(this, "SmallState", false);
            }
        }

        public async Task RefreshAsync() => await LoadDataAsync();

        private async Task LoadDataAsync(bool showSpinner = true)
        {
            if (_calendarService == null) return;

            await _loadLock.WaitAsync();
            try
            {
                if (showSpinner)
                {
                    IsLoading = true;
                }

                // Load events (next 7 days) and todos
                var events = await _calendarService.GetCachedEventsAsync(DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(7));
                var todos = await _calendarService.GetCachedTodosAsync();

                var combinedList = new List<CalendarWidgetItem>();

                // Add active events
                foreach (var ev in events)
                {
                    combinedList.Add(new CalendarWidgetItem
                    {
                        Id = ev.Id,
                        Title = ev.Title,
                        Details = ev.IsAllDay ? "All Day" : $"{ev.Start.ToLocalTime():t} - {ev.End.ToLocalTime():t}",
                        SortDate = ev.Start,
                        Color = string.IsNullOrEmpty(ev.Color) ? "#512BD4" : ev.Color,
                        IsTodo = false,
                        IsCompleted = false,
                        IconGlyph = "\xE787;" // Calendar icon
                    });
                }

                // Add uncompleted todos
                foreach (var td in todos)
                {
                    if (td.IsCompleted) continue;
                    combinedList.Add(new CalendarWidgetItem
                    {
                        Id = td.Id,
                        Title = td.Title,
                        Details = td.DueDate.HasValue ? $"Due {td.DueDate.Value.ToLocalTime():g}" : "No due date",
                        SortDate = td.DueDate ?? DateTime.MaxValue,
                        Color = string.IsNullOrEmpty(td.Color) ? "#107C41" : td.Color, // Default tasks green
                        IsTodo = true,
                        IsCompleted = false,
                        IconGlyph = "\xE710;" // Add/task list icon or check list icon "\xE75C"
                    });
                }

                // Sort by date. Items with max value sort dates (no due date tasks) go last. Limit to top 15.
                var sorted = combinedList.OrderBy(x => x.SortDate).Take(15).ToList();

                UpcomingItems.Clear();
                foreach (var item in sorted)
                {
                    UpcomingItems.Add(item);
                }

                SmallItems.Clear();
                if (sorted.Count > 0)
                {
                    SmallItems.Add(sorted[0]);
                }

                NormalItems.Clear();
                foreach (var item in sorted.Take(2))
                {
                    NormalItems.Add(item);
                }

                HasSmallItems = SmallItems.Count > 0;
                HasNormalItems = NormalItems.Count > 0;
                HasUpcomingItems = UpcomingItems.Count > 0;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarWidget] LoadDataAsync error: {ex.Message}");
            }
            finally
            {
                if (showSpinner)
                {
                    IsLoading = false;
                }
                _loadLock.Release();
            }
        }

        private async void Todo_Checked(object sender, RoutedEventArgs e)
        {
            if (_calendarService == null || sender is not CheckBox cb || cb.DataContext is not CalendarWidgetItem item) return;
            
            // Mark completed in background
            item.IsCompleted = true;
            await _calendarService.CompleteTodoAsync(item.Id);
            
            // Give a short delay for animation, then reload
            await Task.Delay(400);
            await LoadDataAsync(showSpinner: false);
        }
    }
}
