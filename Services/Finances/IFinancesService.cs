
using Daily.Models.Finances;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services.Finances
{
    public interface IFinancesService
    {
        string CurrentViewType { get; set; }
        event Action OnViewTypeChanged;
        event Action OnQuotesUpdated;
        
        Task<List<StockQuote>> GetStockQuotesAsync(List<string> symbols);
        Task<MoneyData> GetMoneyDataAsync();

        // Smart Ledger
        Task<LocalSmartLedger?> GetSmartLedgerAsync();
        Task SaveSmartLedgerAsync(string ledgerText);
        Task<List<LocalLedgerTransaction>> GetLedgerTransactionsAsync();
        Task SaveLedgerTransactionAsync(LocalLedgerTransaction transaction);

        // Money Features
        Task<List<LocalAccount>> GetAccountsAsync();
        Task AddAccountAsync(LocalAccount account);
        Task<List<LocalTransaction>> GetTransactionsAsync(string accountId);
        Task AddTransactionAsync(LocalTransaction transaction);

        // Portfolio Features
        Task<decimal> GetNetWorthAsync();
        Task<List<StockQuote>> GetHoldingsWithQuotesAsync();

        // Watchlist
        Task<List<string>> GetWatchlistSymbolsAsync();
    }
}
