using Daily.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Controls
{
    public class WidgetTemplateSelector : DataTemplateSelector
    {
        public DataTemplate WeatherTemplate { get; set; } = null!;
        public DataTemplate FinancesTemplate { get; set; } = null!;
        public DataTemplate HabitsTemplate { get; set; } = null!;
        public DataTemplate HealthTemplate { get; set; } = null!;
        public DataTemplate CalendarTemplate { get; set; } = null!;
        public DataTemplate RssFeedTemplate { get; set; } = null!;
        public DataTemplate NotesTemplate { get; set; } = null!;
        public DataTemplate MediaTemplate { get; set; } = null!;
        public DataTemplate SystemInfoTemplate { get; set; } = null!;
        public DataTemplate NewsRecommendationsTemplate { get; set; } = null!;

        protected override DataTemplate SelectTemplateCore(object item, DependencyObject container)
        {
            if (item is WidgetModel widget)
            {
                switch (widget.ComponentType)
                {
                    case "WeatherWidget": return WeatherTemplate;
                    case "FinancesWidget": return FinancesTemplate;
                    case "HabitsWidget": return HabitsTemplate;
                    case "HealthWidget": return HealthTemplate;
                    case "CalendarWidget": return CalendarTemplate;
                    case "RssFeedWidget": return RssFeedTemplate;
                    case "NotesWidget": return NotesTemplate;
                    case "MediaWidget": return MediaTemplate;
                    case "SystemInfoWidget": return SystemInfoTemplate;
                    case "NewsRecommendationsWidget": return NewsRecommendationsTemplate;
                }
            }
            return base.SelectTemplateCore(item, container);
        }
    }
}
