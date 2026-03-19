using Daily.Models.Finances;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services.Finances
{
    public interface IHeatmapService
    {
        /// <summary>
        /// Returns economic data for major economies, used to render the Global Heatmap.
        /// Data is cached in SQLite with a 24-hour freshness window.
        /// </summary>
        Task<List<CountryEconomicData>> GetGlobalHeatmapDataAsync(bool forceRefresh = false);
    }
}
