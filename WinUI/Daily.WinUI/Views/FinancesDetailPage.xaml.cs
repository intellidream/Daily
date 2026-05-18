using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services.Finances;
using Daily.Models.Finances;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace Daily_WinUI.Views;

public sealed partial class FinancesDetailPage : Page, INotifyPropertyChanged
{
    private IFinancesService _financesService;
    private IMacroService _macroService;
    private IHeatmapService _heatmapService;

    public event PropertyChangedEventHandler PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    // Loading States
    private bool _isWorldLoading;
    public bool IsWorldLoading { get => _isWorldLoading; set { _isWorldLoading = value; OnPropertyChanged(); } }

    private bool _isStocksLoading;
    public bool IsStocksLoading { get => _isStocksLoading; set { _isStocksLoading = value; OnPropertyChanged(); } }

    private bool _isMoneyLoading;
    public bool IsMoneyLoading { get => _isMoneyLoading; set { _isMoneyLoading = value; OnPropertyChanged(); } }

    // World
    public ObservableCollection<MacroIndicator> MacroIndicators { get; } = new();
    public ObservableCollection<CountryEconomicData> HeatmapData { get; } = new();

    // Stocks
    public ObservableCollection<StockQuote> WatchlistStocks { get; } = new();
    private List<StockQuote> _allWatchlistStocks = new();

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
        IsWorldLoading = true;
        IsStocksLoading = true;
        IsMoneyLoading = true;

        MacroIndicators.Clear();
        HeatmapData.Clear();
        Holdings.Clear();
        Accounts.Clear();

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
            
            var watchlistSymbols = await _financesService.GetWatchlistSymbolsAsync();
            var _trackedSymbols = new List<string> 
            { 
                "AAPL", "MSFT", "NVDA", "TSLA", "GOOGL", "AMZN", "META",
                "TLV.RO", "H2O.RO", "SNG.RO", "SNP.RO",
                "ASML", "TSM", "SAP", "RMS.PA" 
            };
            var _cryptoSymbols = new List<string> { "BTC-USD", "ETH-USD", "SOL-USD", "BNB-USD", "XRP-USD", "DOGE-USD", "ADA-USD", "AVAX-USD", "DOT-USD", "LINK-USD" };
            var _forexSymbols = new List<string> { "EURUSD=X", "JPY=X", "GBPUSD=X", "AUDUSD=X" };

            var allSymbols = _trackedSymbols.Concat(watchlistSymbols).Concat(_cryptoSymbols).Concat(_forexSymbols).Distinct().ToList();
            var allStocks = await _financesService.GetStockQuotesAsync(allSymbols);

            _allWatchlistStocks = allStocks;
            
            // Add portfolio stocks to all watchlist if not present
            foreach (var p in portfolio)
            {
                if (!_allWatchlistStocks.Any(x => x.Symbol == p.Symbol))
                {
                    _allWatchlistStocks.Add((StockQuote)p);
                }
            }
            
            string currentFilter = "stock";
            if (CryptoBtn.IsChecked == true) currentFilter = "crypto";
            else if (ForexBtn.IsChecked == true) currentFilter = "forex";
            
            FilterWatchlist(currentFilter);

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
        finally
        {
            IsWorldLoading = false;
            IsStocksLoading = false;
            IsMoneyLoading = false;
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

    private void MarketType_Click(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton btn)
        {
            StocksBtn.IsChecked = btn == StocksBtn;
            CryptoBtn.IsChecked = btn == CryptoBtn;
            ForexBtn.IsChecked = btn == ForexBtn;

            string marketType = btn.Tag?.ToString() ?? "stock";
            FilterWatchlist(marketType);
        }
    }

    private async void FilterWatchlist(string marketType)
    {
        IsStocksLoading = true;
        WatchlistStocks.Clear();
        
        // Brief delay to allow UI to render spinner
        await Task.Delay(50);
        
        var filtered = _allWatchlistStocks.Where(x => x.MarketType?.ToLower() == marketType).ToList();

        foreach (var s in filtered)
        {
            WatchlistStocks.Add(s);
        }
        
        IsStocksLoading = false;
    }
}
