using Daily.Models;
using Daily.Services;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Daily_WinUI.Services
{
    public class WinUIWidgetService
    {
        private readonly ISettingsService _settingsService;

        public WinUIWidgetService(ISettingsService settingsService)
        {
            _settingsService = settingsService;
        }

        private List<WidgetModel> GetDefaultWidgets()
        {
            // WinUI Default Desktop Layout
            // A 2-column layout. Weather spans both columns.
            return new List<WidgetModel>
            {
                new WidgetModel { Title = "Weather", ComponentType = "WeatherWidget", ColumnSpan = 2, RowSpan = 1 },
                new WidgetModel { Title = "Finances", ComponentType = "FinancesWidget", ColumnSpan = 1, RowSpan = 1 },
                new WidgetModel { Title = "Habits", ComponentType = "HabitsWidget", ColumnSpan = 1, RowSpan = 1 },
                new WidgetModel { Title = "News", ComponentType = "RssFeedWidget", ColumnSpan = 1, RowSpan = 2 },
                new WidgetModel { Title = "Vitals", ComponentType = "HealthWidget", ColumnSpan = 1, RowSpan = 1 },
                new WidgetModel { Title = "Calendar", ComponentType = "CalendarWidget", ColumnSpan = 1, RowSpan = 1 }
            };
        }

        public Task<List<WidgetModel>> GetWidgetsAsync()
        {
            var json = _settingsService.Settings.WinUIDashboardWidgetsJson;
            List<WidgetModel> widgets;
            if (string.IsNullOrEmpty(json)) 
            {
                widgets = GetDefaultWidgets();
            }
            else
            {
                try 
                {
                    widgets = Newtonsoft.Json.JsonConvert.DeserializeObject<List<WidgetModel>>(json) ?? GetDefaultWidgets();
                }
                catch 
                {
                    widgets = GetDefaultWidgets();
                }
            }

            // Remove NewsRecommendationsWidget from the dashboard widgets list
            widgets.RemoveAll(w => w.ComponentType == "NewsRecommendationsWidget");

            return Task.FromResult(widgets);
        }

        public async Task SaveWidgetsAsync(List<WidgetModel> widgets)
        {
            _settingsService.Settings.WinUIDashboardWidgetsJson = Newtonsoft.Json.JsonConvert.SerializeObject(widgets);
            await _settingsService.SaveSettingsAsync();
        }
    }
}
