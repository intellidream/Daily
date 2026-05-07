using Daily.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class WidgetService : IWidgetService
    {
        private readonly ISettingsService _settingsService;

        public WidgetService(ISettingsService settingsService)
        {
            _settingsService = settingsService;
        }

        private List<WidgetModel> GetDefaultWidgets()
        {
            return new List<WidgetModel>
            {
                new WidgetModel { Title = "Weather", ComponentType = "WeatherWidget", RowSpan = 2 },
                new WidgetModel { Title = "Bubbles", ComponentType = "HabitsWidget", RowSpan = 3 },
                new WidgetModel { Title = "Vitals", ComponentType = "HealthWidget", RowSpan = 2 },
                new WidgetModel { Title = "Finances", ComponentType = "FinancesWidget", RowSpan = 2 },
                new WidgetModel { Title = "Calendar", ComponentType = "CalendarWidget", RowSpan = 2 },
                new WidgetModel { Title = "Notes", ComponentType = "NotesWidget" },
                new WidgetModel { Title = "Feeds", ComponentType = "RssFeedWidget", RowSpan = 2 },
                new WidgetModel { Title = "Media", ComponentType = "MediaWidget", RowSpan = 2 },
                new WidgetModel { Title = "System Info", ComponentType = "SystemInfoWidget" }
            };
        }

        public Task<List<WidgetModel>> GetWidgetsAsync()
        {
             var json = _settingsService.Settings.DashboardWidgetsJson;
             if (string.IsNullOrEmpty(json)) 
             {
                 return Task.FromResult(GetDefaultWidgets());
             }
             try 
             {
                 var widgets = System.Text.Json.JsonSerializer.Deserialize<List<WidgetModel>>(json);
                 return Task.FromResult(widgets ?? GetDefaultWidgets());
             }
             catch 
             {
                 return Task.FromResult(GetDefaultWidgets());
             }
        }

        public async Task AddWidgetAsync(WidgetModel widget)
        {
            var widgets = await GetWidgetsAsync();
            widgets.Add(widget);
            await SaveWidgetsAsync(widgets);
        }

        public async Task RemoveWidgetAsync(Guid id)
        {
            var widgets = await GetWidgetsAsync();
            widgets.RemoveAll(w => w.Id == id);
            await SaveWidgetsAsync(widgets);
        }

        public async Task UpdateWidgetAsync(WidgetModel widget)
        {
            var widgets = await GetWidgetsAsync();
            var index = widgets.FindIndex(w => w.Id == widget.Id);
            if (index != -1)
            {
                widgets[index] = widget;
                await SaveWidgetsAsync(widgets);
            }
        }

        private async Task SaveWidgetsAsync(List<WidgetModel> widgets)
        {
            _settingsService.Settings.DashboardWidgetsJson = System.Text.Json.JsonSerializer.Serialize(widgets);
            await _settingsService.SaveSettingsAsync();
        }
    }
}
