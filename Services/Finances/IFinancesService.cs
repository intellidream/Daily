
using Daily.Models.Finances;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services.Finances
{
    public interface IFinancesService
    {
        string CurrentViewType { get; set; }
        event Action OnViewTypeChanged;
        
        Task<List<StockQuote>> GetStockQuotesAsync(List<string> symbols);
        Task<MoneyData> GetMoneyDataAsync();

        // Money Features
        Task<List<LocalAccount>> GetAccountsAsync();
        Task AddAccountAsync(LocalAccount account);
        Task<List<LocalTransaction>> GetTransactionsAsync(string accountId);
        Task AddTransactionAsync(LocalTransaction transaction);
    }
}
