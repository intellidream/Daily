using Daily.Models.Finances;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services.Finances
{
    public interface IMacroService
    {
        /// <summary>
        /// Returns the 6 core macro pillars: Oil, Gold, DXY, Nasdaq, BTC, VIX.
        /// Uses local cache with 1-hour freshness window.
        /// </summary>
        Task<List<MacroIndicator>> GetMacroIndicatorsAsync(bool forceRefresh = false);
    }
}
