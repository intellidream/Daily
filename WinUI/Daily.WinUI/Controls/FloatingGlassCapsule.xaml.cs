using System;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Daily_WinUI.Controls
{
    public sealed partial class FloatingGlassCapsule : UserControl
    {
        private int _selectedTabIndex = 1;

        public event EventHandler<int>? TabSelected;

        public int SelectedTabIndex => _selectedTabIndex;

        public FloatingGlassCapsule()
        {
            this.InitializeComponent();
            this.ActualThemeChanged += (_, _) => UpdateVisualState();
            UpdateVisualState();
        }

        private void TabButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tagStr && int.TryParse(tagStr, out int index))
            {
                SetSelectedTab(index);
                TabSelected?.Invoke(this, index);
            }
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
            var activeGradient = Resources["ActiveTabGradientBrush"] as Brush ?? new SolidColorBrush(Color.FromArgb(0xCC, 0x00, 0x78, 0xD4));
            var activeBorder = new SolidColorBrush(Color.FromArgb(0x99, 0x00, 0xE5, 0xFF));
            var transparentBrush = new SolidColorBrush(Colors.Transparent);
            var activeTextBrush = new SolidColorBrush(Colors.White);

            var inactiveBrush = isLight
                ? new SolidColorBrush(Color.FromArgb(0x99, 0x1A, 0x1A, 0x1A))
                : new SolidColorBrush(Color.FromArgb(0xB3, 0xFF, 0xFF, 0xFF));

            for (int i = 1; i <= 8; i++)
            {
                var button = FindName($"TabButton{i}") as Button;
                var icon = FindName($"TabIcon{i}") as FontIcon;
                var text = FindName($"TabText{i}") as TextBlock;

                if (button == null || icon == null || text == null) continue;

                bool isActive = (i == _selectedTabIndex);

                if (isActive)
                {
                    button.Background = activeGradient;
                    button.BorderBrush = activeBorder;
                    text.Visibility = Visibility.Visible;
                    text.Foreground = activeTextBrush;
                    icon.Foreground = activeTextBrush;
                }
                else
                {
                    button.Background = transparentBrush;
                    button.BorderBrush = transparentBrush;
                    text.Visibility = Visibility.Collapsed;
                    text.Foreground = inactiveBrush;
                    icon.Foreground = inactiveBrush;
                }
            }
        }
    }
}
