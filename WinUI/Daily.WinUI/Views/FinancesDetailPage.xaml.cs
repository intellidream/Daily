using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services.Finances;
using Daily.Models.Finances;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Daily_WinUI.Views;

public sealed partial class FinancesDetailPage : Page, INotifyPropertyChanged
{
    private IFinancesService _financesService;
    private IMacroService _macroService;
    private IHeatmapService _heatmapService;

    public event PropertyChangedEventHandler PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    // World
    public ObservableCollection<MacroIndicator> MacroIndicators { get; } = new();
    public ObservableCollection<CountryEconomicData> HeatmapData { get; } = new();

    // Stocks
    public ObservableCollection<StockQuote> WatchlistStocks { get; } = new();

    // Money
    private string _netWorthDisplay = "$0";
    public string NetWorthDisplay
    {
        get => _netWorthDisplay;
        set { _netWorthDisplay = value; OnPropertyChanged(); }
    }

    private string _cashDisplay = "$0";
    public string CashDisplay
    {
        get => _cashDisplay;
        set { _cashDisplay = value; OnPropertyChanged(); }
    }

    private string _investmentsDisplay = "$0";
    public string InvestmentsDisplay
    {
        get => _investmentsDisplay;
        set { _investmentsDisplay = value; OnPropertyChanged(); }
    }

    public ObservableCollection<LocalAccount> Accounts { get; } = new();
    
    // Using object here since PortfolioItem inherits from StockQuote but we might just use StockQuote
    public ObservableCollection<object> Holdings { get; } = new();

    public FinancesDetailPage()
    {
        this.InitializeComponent();

        if (!Windows.ApplicationModel.DesignMode.DesignModeEnabled)
        {
            _financesService = App.Current.Services.GetRequiredService<IFinancesService>();
            _macroService = App.Current.Services.GetRequiredService<IMacroService>();
            _heatmapService = App.Current.Services.GetRequiredService<IHeatmapService>();
        }
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        await LoadDataAsync();
        
        // Auto-select tab based on FinancesService state
        if (_financesService.CurrentViewType == "Stocks") MainPivot.SelectedIndex = 1;
        else if (_financesService.CurrentViewType == "Money") MainPivot.SelectedIndex = 2;
        else MainPivot.SelectedIndex = 0;
    }

    private async Task LoadDataAsync()
    {
        try
        {
            // World
            var macros = await _macroService.GetMacroIndicatorsAsync();
            MacroIndicators.Clear();
            foreach (var m in macros) MacroIndicators.Add(m);

            var heatmap = await _heatmapService.GetGlobalHeatmapDataAsync();
            HeatmapData.Clear();
            foreach (var h in heatmap) HeatmapData.Add(h);

            // Stocks (All stocks in watchlist)
            var portfolio = await _financesService.GetHoldingsWithQuotesAsync();
            var allStocks = await _financesService.GetStockQuotesAsync(new List<string> { "AAPL", "MSFT", "NVDA", "TSLA", "BTC-USD", "ETH-USD" }); // Fallback or mock list
            
            // Hard fallback if API fails
            if (!allStocks.Any())
            {
                allStocks = new List<StockQuote>
                {
                    new StockQuote { Symbol = "AAPL", CompanyName = "Apple", CurrentPrice = 175.50m, PercentChange = 1.2m, MarketType = "stock" },
                    new StockQuote { Symbol = "MSFT", CompanyName = "Microsoft", CurrentPrice = 330.10m, PercentChange = 0.5m, MarketType = "stock" },
                    new StockQuote { Symbol = "NVDA", CompanyName = "Nvidia", CurrentPrice = 450.25m, PercentChange = 2.1m, MarketType = "stock" },
                    new StockQuote { Symbol = "TSLA", CompanyName = "Tesla", CurrentPrice = 210.80m, PercentChange = -1.5m, MarketType = "stock" },
                    new StockQuote { Symbol = "BTC-USD", CompanyName = "Bitcoin", CurrentPrice = 45000.00m, PercentChange = 3.5m, MarketType = "crypto" },
                    new StockQuote { Symbol = "ETH-USD", CompanyName = "Ethereum", CurrentPrice = 2500.00m, PercentChange = 4.2m, MarketType = "crypto" }
                };
            }
            
            WatchlistStocks.Clear();
            foreach (var s in allStocks) WatchlistStocks.Add(s);
            
            // Add portfolio stocks to watchlist if not present
            foreach (var p in portfolio)
            {
                if (!WatchlistStocks.Any(x => x.Symbol == p.Symbol))
                {
                    WatchlistStocks.Add(p);
                }
            }

            // Money
            var nw = await _financesService.GetNetWorthAsync();
            NetWorthDisplay = nw.ToString("C0");

            var accounts = await _financesService.GetAccountsAsync();
            decimal cash = accounts.Sum(a => a.CurrentBalance);
            CashDisplay = cash.ToString("C0");
            
            Accounts.Clear();
            foreach (var a in accounts) Accounts.Add(a);

            decimal investments = portfolio.OfType<PortfolioItem>().Sum(p => p.TotalValue);
            InvestmentsDisplay = investments.ToString("C0");

            Holdings.Clear();
            foreach (var p in portfolio) Holdings.Add(p);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading finances detail: {ex}");
        }
    }

    private async void RefreshBtn_Click(object sender, RoutedEventArgs e)
    {
        await LoadDataAsync();
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (this.Frame.CanGoBack)
        {
            this.Frame.GoBack();
        }
        else
        {
            this.Frame.Navigate(typeof(MainPage));
        }
    }
}
