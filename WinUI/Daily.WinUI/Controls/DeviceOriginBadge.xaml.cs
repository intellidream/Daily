using Daily.Models.Health;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Daily_WinUI.Controls
{
    public sealed partial class DeviceOriginBadge : UserControl
    {
        public static readonly DependencyProperty DeviceNameProperty =
            DependencyProperty.Register(
                nameof(DeviceName),
                typeof(string),
                typeof(DeviceOriginBadge),
                new PropertyMetadata(null, OnDeviceNameChanged));

        public static readonly DependencyProperty CompactProperty =
            DependencyProperty.Register(
                nameof(Compact),
                typeof(bool),
                typeof(DeviceOriginBadge),
                new PropertyMetadata(false, OnCompactChanged));

        public static readonly DependencyProperty IsCompactProperty =
            DependencyProperty.Register(
                nameof(IsCompact),
                typeof(bool),
                typeof(DeviceOriginBadge),
                new PropertyMetadata(false, (d, e) => { if (d is DeviceOriginBadge b) b.Compact = (bool)e.NewValue; }));

        public string? DeviceName
        {
            get => (string?)GetValue(DeviceNameProperty);
            set => SetValue(DeviceNameProperty, value);
        }

        public bool Compact
        {
            get => (bool)GetValue(CompactProperty);
            set => SetValue(CompactProperty, value);
        }

        public bool IsCompact
        {
            get => (bool)GetValue(IsCompactProperty);
            set => SetValue(IsCompactProperty, value);
        }

        public DeviceOriginBadge()
        {
            InitializeComponent();
        }

        private static void OnDeviceNameChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is DeviceOriginBadge badge)
            {
                badge.UpdateBadge();
            }
        }

        private static void OnCompactChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is DeviceOriginBadge badge)
            {
                badge.UpdateBadge();
            }
        }

        private void UpdateBadge()
        {
            var raw = DeviceName?.Trim();
            if (string.IsNullOrEmpty(raw))
            {
                BadgeContainer.Visibility = Visibility.Collapsed;
                return;
            }

            var source = DeviceSource.From(raw);
            if (source.IsVirtualEngine)
            {
                BadgeContainer.Visibility = Visibility.Collapsed;
                return;
            }

            var color = DeviceColorPalette.ParseColor(source.ColorHex);

            // Styling
            var bgBrush = new SolidColorBrush(Color.FromArgb(36, color.R, color.G, color.B));
            var borderBrush = new SolidColorBrush(Color.FromArgb(90, color.R, color.G, color.B));
            var fgBrush = new SolidColorBrush(color);

            BadgeContainer.Background = bgBrush;
            BadgeContainer.BorderBrush = borderBrush;
            BadgeContainer.Visibility = Visibility.Visible;

            ColorDot.Fill = fgBrush;
            HardwareIcon.Glyph = source.SegoeGlyph;
            HardwareIcon.Foreground = fgBrush;
            DeviceLabel.Text = source.DisplayName;
            DeviceLabel.Foreground = fgBrush;

            if (Compact)
            {
                BadgeContainer.Padding = new Thickness(6, 2, 6, 2);
                ColorDot.Width = 5;
                ColorDot.Height = 5;
                HardwareIcon.FontSize = 9;
                DeviceLabel.FontSize = 10;
                DeviceLabel.MaxWidth = 110;
            }
            else
            {
                BadgeContainer.Padding = new Thickness(8, 3, 8, 3);
                ColorDot.Width = 7;
                ColorDot.Height = 7;
                HardwareIcon.FontSize = 11;
                DeviceLabel.FontSize = 11;
                DeviceLabel.MaxWidth = 160;
            }
        }
    }
}
