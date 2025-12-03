using Daily.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IWidgetService
    {
        Task<List<WidgetModel>> GetWidgetsAsync();
        Task AddWidgetAsync(WidgetModel widget);
        Task RemoveWidgetAsync(Guid id);
        Task UpdateWidgetAsync(WidgetModel widget);
    }
}
