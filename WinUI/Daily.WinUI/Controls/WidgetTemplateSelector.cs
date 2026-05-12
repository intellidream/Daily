using Daily.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Controls
{
    public class WidgetTemplateSelector : DataTemplateSelector
    {
        public DataTemplate WeatherTemplate { get; set; }
        public DataTemplate FinancesTemplate { get; set; }
        public DataTemplate HabitsTemplate { get; set; }
        public DataTemplate HealthTemplate { get; set; }
        public DataTemplate CalendarTemplate { get; set; }
        public DataTemplate RssFeedTemplate { get; set; }
        public DataTemplate NotesTemplate { get; set; }
        public DataTemplate MediaTemplate { get; set; }
        public DataTemplate SystemInfoTemplate { get; set; }

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
                }
            }
            return base.SelectTemplateCore(item, container);
        }
    }
}
