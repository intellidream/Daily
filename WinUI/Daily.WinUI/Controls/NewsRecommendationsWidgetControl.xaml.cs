using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily_WinUI.Services;
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

        private async void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _briefingService = App.Current.Services.GetService<SmartBriefingService>();
                if (_briefingService != null)
                {
                    // Generate brief data (this handles fallback to static if empty)
                    var data = await _briefingService.GenerateBriefingDataAsync("User");
                    _recs = data.NewsRecommendations;
                    
                    if (_recs != null && _recs.Count >= 2)
                    {
                        Rec1Title.Text = _recs[0].Title;
                        Rec1Reason.Text = _recs[0].Reason;
                        Rec1Source.Text = _recs[0].Source;

                        Rec2Title.Text = _recs[1].Title;
                        Rec2Reason.Text = _recs[1].Reason;
                        Rec2Source.Text = _recs[1].Source;

                        ContentPanel.Visibility = Visibility.Visible;
                        NoDataText.Visibility = Visibility.Collapsed;
                    }
                    else
                    {
                        NoDataText.Visibility = Visibility.Visible;
                        ContentPanel.Visibility = Visibility.Collapsed;
                    }
                }
                else
                {
                    NoDataText.Visibility = Visibility.Visible;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[NewsRecommendationsWidgetControl] Error: {ex.Message}");
                NoDataText.Visibility = Visibility.Visible;
            }
            finally
            {
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
            // Standard action: open the RSS feed list
            if (App.Current.MainWindow is MainWindow mw)
            {
                mw.DispatcherQueue.TryEnqueue(() =>
                {
                    // If we want to navigate or alert, we can.
                    // For now, it behaves as a visual recommendations widget.
                });
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
