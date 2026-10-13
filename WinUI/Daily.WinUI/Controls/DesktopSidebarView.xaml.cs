using System;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Daily_WinUI.Controls
{
    public sealed partial class DesktopSidebarView : UserControl
    {
        private int _selectedTabIndex = 1;

        public event EventHandler<int>? TabSelected;
        public event EventHandler? CollapseRequested;
        public event EventHandler? SyncRequested;
        public event EventHandler? SettingsRequested;

        public int SelectedTabIndex => _selectedTabIndex;

        public DesktopSidebarView()
        {
            this.InitializeComponent();
            this.ActualThemeChanged += (_, _) => UpdateVisualState();
            UpdateVisualState();
        }

        private void CollapseSidebarButton_Click(object sender, RoutedEventArgs e)
        {
            CollapseRequested?.Invoke(this, EventArgs.Empty);
        }

        private void SidebarItem_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tagStr && int.TryParse(tagStr, out int index))
            {
                SetSelectedTab(index);
                TabSelected?.Invoke(this, index);
            }
        }

        private void SidebarSyncButton_Click(object sender, RoutedEventArgs e)
        {
            SyncRequested?.Invoke(this, EventArgs.Empty);
        }

        private void SidebarSettingsButton_Click(object sender, RoutedEventArgs e)
        {
            SettingsRequested?.Invoke(this, EventArgs.Empty);
        }

        public void SetSelectedTab(int tabIndex)
        {
            if (tabIndex < 1 || tabIndex > 8) return;
            _selectedTabIndex = tabIndex;
            UpdateVisualState();
        }

        private void UpdateVisualState()
        {
            var isLight = (this.ActualTheme == ElementTheme.Light);
            var activeBg = Resources["SidebarActiveTabBrush"] as Brush ?? new SolidColorBrush(Color.FromArgb(0x40, 0x00, 0x78, 0xD4));
            var transparentBrush = new SolidColorBrush(Colors.Transparent);
            var activeIconBrush = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF));
            
            var fgBrush = isLight
                ? new SolidColorBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A))
                : new SolidColorBrush(Colors.White);

            var mutedBrush = isLight
                ? new SolidColorBrush(Color.FromArgb(0xBB, 0x1A, 0x1A, 0x1A))
                : new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));

            for (int i = 1; i <= 8; i++)
            {
                var item = FindName($"SidebarItem{i}") as Button;
                var icon = FindName($"SidebarIcon{i}") as FontIcon;
                var text = FindName($"SidebarText{i}") as TextBlock;

                if (item == null || icon == null || text == null) continue;

                bool isActive = (i == _selectedTabIndex);

                if (isActive)
                {
                    item.Background = activeBg;
                    icon.Foreground = activeIconBrush;
                    text.Foreground = fgBrush;
                    text.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
                }
                else
                {
                    item.Background = transparentBrush;
                    icon.Foreground = mutedBrush;
                    text.Foreground = mutedBrush;
                    text.FontWeight = Microsoft.UI.Text.FontWeights.Normal;
                }
            }
        }
    }
}
