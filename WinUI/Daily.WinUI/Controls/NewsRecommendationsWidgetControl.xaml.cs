using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily_WinUI.Services;
using Daily_WinUI.Views;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.Controls
{
    public sealed partial class NewsRecommendationsWidgetControl : UserControl
    {
        private SmartBriefingService? _briefingService;
        private List<NewsRecommendationData> _recs = new();

        public NewsRecommendationsWidgetControl()
        {
            this.InitializeComponent();
        }

        public void Populate(List<NewsRecommendationData> recs)
        {
            _recs = recs ?? new List<NewsRecommendationData>();
            if (_recs.Count > 0)
            {
                RecommendationsItemsControl.ItemsSource = _recs.Take(5).ToList();
                RecommendationsScrollViewer.Visibility = Visibility.Visible;
                NoDataText.Visibility = Visibility.Collapsed;
            }
            else
            {
                NoDataText.Visibility = Visibility.Visible;
                RecommendationsScrollViewer.Visibility = Visibility.Collapsed;
            }
            LoadingRing.IsActive = false;
            LoadingRing.Visibility = Visibility.Collapsed;
        }

        private async void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            if (_recs != null && _recs.Count > 0)
            {
                // Already populated by parent overlay
                return;
            }

            try
            {
                _briefingService = App.Current.Services.GetService<SmartBriefingService>();
                if (_briefingService != null)
                {
                    // Generate brief data (this handles fallback to static if empty)
                    var data = await _briefingService.GenerateBriefingDataAsync("User");
                    Populate(data.NewsRecommendations);
                }
                else
                {
                    NoDataText.Visibility = Visibility.Visible;
                    LoadingRing.IsActive = false;
                    LoadingRing.Visibility = Visibility.Collapsed;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[NewsRecommendationsWidgetControl] Error: {ex.Message}");
                NoDataText.Visibility = Visibility.Visible;
                LoadingRing.IsActive = false;
                LoadingRing.Visibility = Visibility.Collapsed;
            }
        }

        private void RecGrid_PointerEntered(object sender, PointerRoutedEventArgs e)
        {
            if (sender is Grid grid)
            {
                grid.Opacity = 0.75;
            }
        }

        private void RecGrid_PointerExited(object sender, PointerRoutedEventArgs e)
        {
            if (sender is Grid grid)
            {
                grid.Opacity = 1.0;
            }
        }

        private void RecGrid_Tapped(object sender, TappedRoutedEventArgs e)
        {
            if (sender is FrameworkElement element && element.DataContext is NewsRecommendationData rec)
            {
                if (rec.RssItem != null)
                {
                    MainPage.Current?.OpenDetailWindow(typeof(RssFeedDetailPage), rec.RssItem);
                }
            }
        }
    }

    public class HandCursorGrid : Grid
    {
        public HandCursorGrid()
        {
            this.Loaded += (s, e) =>
            {
                try
                {
                    this.ProtectedCursor = Microsoft.UI.Input.InputSystemCursor.Create(Microsoft.UI.Input.InputSystemCursorShape.Hand);
                }
                catch { }
            };
        }
    }
}
