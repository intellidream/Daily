using Daily.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class WidgetService : IWidgetService
    {
        private readonly List<WidgetModel> _widgets;

        public WidgetService()
        {
            _widgets = new List<WidgetModel>
            {
                // Default widgets
                new WidgetModel { Title = "Weather", ComponentType = "WeatherWidget", RowSpan = 2 },
                new WidgetModel { Title = "Calendar", ComponentType = "CalendarWidget", RowSpan = 2 },
                new WidgetModel { Title = "Notes", ComponentType = "NotesWidget" },
                new WidgetModel { Title = "News", ComponentType = "RssFeedWidget", RowSpan = 2 },
                new WidgetModel { Title = "System Info", ComponentType = "SystemInfoWidget" }
            };
        }

        public Task<List<WidgetModel>> GetWidgetsAsync()
        {
            return Task.FromResult(_widgets);
        }

        public Task AddWidgetAsync(WidgetModel widget)
        {
            _widgets.Add(widget);
            return Task.CompletedTask;
        }

        public Task RemoveWidgetAsync(Guid id)
        {
            var widget = _widgets.FirstOrDefault(w => w.Id == id);
            if (widget != null)
            {
                _widgets.Remove(widget);
            }
            return Task.CompletedTask;
        }

        public Task UpdateWidgetAsync(WidgetModel widget)
        {
            // In-memory, so reference update is enough if it's the same object, 
            // but for safety we could replace it.
            var index = _widgets.FindIndex(w => w.Id == widget.Id);
            if (index != -1)
            {
                _widgets[index] = widget;
            }
            return Task.CompletedTask;
        }
    }
}
