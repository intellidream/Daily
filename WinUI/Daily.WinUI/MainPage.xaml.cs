using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Daily_WinUI.Views;
using Daily_WinUI.Services;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI;

public sealed partial class MainPage : Page
{
    private readonly Dictionary<System.Type, DetailWindow> _openWindows = new();
    private readonly WinUIAuthService _authService;
    private readonly WinUIWidgetService _widgetService;
    private System.Collections.ObjectModel.ObservableCollection<Daily.Models.WidgetModel> _widgets;

    public MainPage()
    {
        InitializeComponent();
        _authService = App.Current.Services.GetRequiredService<WinUIAuthService>();
        _widgetService = App.Current.Services.GetRequiredService<WinUIWidgetService>();
        Loaded += MainPage_Loaded;
        Unloaded += (_, _) => WeatherBannerService.WeatherConditionChanged -= OnWeatherConditionChanged;
        WeatherBannerService.WeatherConditionChanged += OnWeatherConditionChanged;
        // Replay last known condition if weather already loaded before this page
        if (WeatherBannerService.LastIconCode is { } code)
            OnWeatherConditionChanged(code);
    }

    private void OnWeatherConditionChanged(string iconCode)
    {
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Normal, () =>
        {
            TopBarBanner.SetCondition(iconCode);
        });
    }

    private async void MainPage_Loaded(object sender, RoutedEventArgs e)
    {
        UpdateUserUI();
        await LoadWidgetsAsync();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await LoadWidgetsAsync();
    }

    private async System.Threading.Tasks.Task LoadWidgetsAsync()
    {
        var widgetList = await _widgetService.GetWidgetsAsync();
        _widgets = new System.Collections.ObjectModel.ObservableCollection<Daily.Models.WidgetModel>(widgetList);
        WidgetGridView.ItemsSource = _widgets;
    }

    private void UpdateUserUI()
    {
        var email       = _authService.CurrentUserEmail;
        var displayName = email?.Split('@').FirstOrDefault() ?? "U";
        var avatarUrl   = _authService.CurrentUserAvatarUrl;
        var isAuth      = _authService.IsAuthenticated;

        // Push state to the OS title bar controls hosted in MainWindow
        if (XamlRoot?.Content is FrameworkElement root &&
            root.XamlRoot != null &&
            App.Current.MainWindow is MainWindow mw)
        {
            mw.UpdateTitleBarUser(email ?? string.Empty, displayName, avatarUrl, isAuth);
        }
    }

    private void ThemeToggleButton_Click(object sender, RoutedEventArgs e)
        => ApplyThemeToggle();

    public void ApplyThemeToggle()
    {
        var root = this.XamlRoot?.Content as FrameworkElement;
        if (root == null) return;

        bool goingLight = root.RequestedTheme == ElementTheme.Dark || root.RequestedTheme == ElementTheme.Default;
        var newTheme = goingLight ? ElementTheme.Light : ElementTheme.Dark;

        // Apply to main window
        root.RequestedTheme = newTheme;

        // Propagate to all open detail windows
        foreach (var win in _openWindows.Values)
            win.ApplyTheme(newTheme);

        // Sync title bar theme button icon/text
        App.Current.MainWindow?.UpdateThemeIcon(isDark: !goingLight);
    }

    private async void SignOut_Click(object sender, RoutedEventArgs e)
        => await HandleSignOutAsync();

    public async Task HandleSignOutAsync()
    {
        if (_authService.IsAuthenticated)
            await _authService.SignOutAsync();

        Frame?.Navigate(typeof(LoginPage));
    }

    private void WidgetGridView_ContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.Item is Daily.Models.WidgetModel widget && args.ItemContainer is GridViewItem itemContainer)
        {
            // Set the VariableSizedWrapGrid spans based on the widget model
            VariableSizedWrapGrid.SetColumnSpan(itemContainer, widget.ColumnSpan);
            VariableSizedWrapGrid.SetRowSpan(itemContainer, widget.RowSpan);

            // Important: We need to set the width and height of the container to stretch so the content fills the cell(s)
            itemContainer.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            itemContainer.VerticalContentAlignment = VerticalAlignment.Stretch;
        }
    }

    private Daily.Models.WidgetModel _draggedWidget;

    private void WidgetGridView_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (WidgetGridView.ActualWidth > 0)
        {
            var panel = WidgetGridView.ItemsPanelRoot as VariableSizedWrapGrid;
            if (panel != null)
            {
                // VariableSizedWrapGrid.ItemWidth is the total cell width including margins.
                // To perfectly fill the GridView, we simply divide by 2.
                panel.ItemWidth = System.Math.Floor(WidgetGridView.ActualWidth / 2);
            }
        }
    }

    private void WidgetGridView_DragItemsStarting(object sender, DragItemsStartingEventArgs e)
    {
        if (e.Items != null && e.Items.Count > 0 && e.Items[0] is Daily.Models.WidgetModel widget)
        {
            _draggedWidget = widget;
        }
    }

    private void WidgetGridView_DragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move;
    }

    private async void WidgetGridView_Drop(object sender, DragEventArgs e)
    {
        if (_draggedWidget == null) return;

        DependencyObject current = e.OriginalSource as DependencyObject;
        Daily.Models.WidgetModel targetWidget = null;
        
        while (current != null)
        {
            if (current is FrameworkElement fe && fe.DataContext is Daily.Models.WidgetModel w)
            {
                targetWidget = w;
                break;
            }
            current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current);
        }

        if (targetWidget == null)
        {
            var pos = e.GetPosition(WidgetGridView);
            foreach (var w in _widgets)
            {
                if (WidgetGridView.ContainerFromItem(w) is UIElement container)
                {
                    var transform = container.TransformToVisual(WidgetGridView);
                    var bounds = transform.TransformBounds(new Windows.Foundation.Rect(0, 0, container.RenderSize.Width, container.RenderSize.Height));
                    bounds.X -= 20;
                    bounds.Y -= 20;
                    bounds.Width += 40;
                    bounds.Height += 40;
                    if (bounds.Contains(pos))
                    {
                        targetWidget = w;
                        break;
                    }
                }
            }
        }

        if (targetWidget != null && targetWidget != _draggedWidget)
        {
            int draggedIndex = _widgets.IndexOf(_draggedWidget);
            int targetIndex = _widgets.IndexOf(targetWidget);

            if (draggedIndex >= 0 && targetIndex >= 0)
            {
                _widgets.RemoveAt(draggedIndex);
                _widgets.Insert(targetIndex, _draggedWidget);

                // UpdateLayout is no longer strictly needed for spans because DashboardGridView handles it,
                // but we call it to ensure visual refresh.
                WidgetGridView.UpdateLayout();
                await _widgetService.SaveWidgetsAsync(_widgets.ToList());
            }
        }
        
        _draggedWidget = null;
    }

    private async void WidgetResize_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem menuItem && menuItem.DataContext is Daily.Models.WidgetModel widget)
        {
            var tag = menuItem.Tag?.ToString();
            if (tag == "1x1") { widget.ColumnSpan = 1; widget.RowSpan = 1; }
            else if (tag == "2x1") { widget.ColumnSpan = 2; widget.RowSpan = 1; }
            else if (tag == "1x2") { widget.ColumnSpan = 1; widget.RowSpan = 2; }
            else if (tag == "2x2") { widget.ColumnSpan = 2; widget.RowSpan = 2; }

            // Re-insert to force DashboardGridView to prepare the container again
            int index = _widgets.IndexOf(widget);
            if (index >= 0)
            {
                _widgets.RemoveAt(index);
                _widgets.Insert(index, widget);
                
                // Save the new layout sizes
                _ = _widgetService.SaveWidgetsAsync(_widgets.ToList());
            }
            
            await _widgetService.SaveWidgetsAsync(_widgets.ToList());
        }
    }

    
    private void Widget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // Ignore taps if they originated inside a ListView or Button (like the RSS news items)
        DependencyObject current = e.OriginalSource as DependencyObject;
        while (current != null)
        {
            if (current is ListViewItem || current is Button) return;
            current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current);
        }

        if (sender is FrameworkElement fe && fe.DataContext is Daily.Models.WidgetModel widget)
        {
            switch (widget.ComponentType)
            {
                case "WeatherWidget":
                    OpenDetailWindow(typeof(WeatherDetailPage));
                    break;
                case "RssFeedWidget":
                    OpenDetailWindow(typeof(RssFeedDetailPage));
                    break;
                case "FinancesWidget":
                    break;
                case "HabitsWidget":
                    OpenDetailWindow(typeof(HabitsDetailPage));
                    break;
                case "HealthWidget":
                    break;
            }
        }
    }

    private void RssFeedWidget_ArticleTapped(object sender, Daily.Models.RssItem e)
    {
        OpenDetailWindow(typeof(RssFeedDetailPage), e);
    }
    private void OpenDetailWindow(System.Type pageType, object parameter = null)
    {
        if (_openWindows.TryGetValue(pageType, out var existingWindow))
        {
            if (parameter != null) existingWindow.NavigateTo(pageType, parameter);
            existingWindow.Activate();
            return;
        }

        var window = new DetailWindow();
        window.Closed += (s, ev) => { _openWindows.Remove(pageType); };
        _openWindows[pageType] = window;
        window.NavigateTo(pageType, parameter);
        // Inherit current theme
        var currentTheme = (this.XamlRoot?.Content as FrameworkElement)?.RequestedTheme ?? ElementTheme.Default;
        if (currentTheme != ElementTheme.Default) window.ApplyTheme(currentTheme);
        window.Activate();
    }
}

public class DashboardGridView : GridView
{
    protected override void PrepareContainerForItemOverride(DependencyObject element, object item)
    {
        base.PrepareContainerForItemOverride(element, item);
        if (item is Daily.Models.WidgetModel widget && element is GridViewItem itemContainer)
        {
            // Apply immediately (might be dropped by VariableSizedWrapGrid layout pass)
            VariableSizedWrapGrid.SetColumnSpan(itemContainer, widget.ColumnSpan);
            VariableSizedWrapGrid.SetRowSpan(itemContainer, widget.RowSpan);

            itemContainer.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            itemContainer.VerticalContentAlignment = VerticalAlignment.Stretch;

            // GUARANTEE the sizes stick by forcefully re-injecting them once the item is fully loaded into the Visual Tree
            itemContainer.Loaded += (s, e) =>
            {
                VariableSizedWrapGrid.SetColumnSpan(itemContainer, widget.ColumnSpan);
                VariableSizedWrapGrid.SetRowSpan(itemContainer, widget.RowSpan);
                
                var panel = this.ItemsPanelRoot as VariableSizedWrapGrid;
                panel?.InvalidateMeasure();
            };
        }
    }
}
