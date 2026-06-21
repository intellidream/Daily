using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services.Finances;
using Daily.Models.Finances;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Controls.Primitives;
using System.Threading;
using System.Threading.Tasks;

namespace Daily_WinUI.Views;

public sealed partial class FinancesDetailPage : Page, INotifyPropertyChanged
{
    private IFinancesService _financesService;
    private IMacroService _macroService;
    private IHeatmapService _heatmapService;
    private readonly SemaphoreSlim _loadLock = new(1, 1);
    private readonly SemaphoreSlim _watchlistLock = new(1, 1);

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

    // Smart Ledger
    private string _smartLedgerText = string.Empty;
    public string SmartLedgerText
    {
        get => _smartLedgerText;
        set 
        { 
            if (_smartLedgerText != value)
            {
                _smartLedgerText = value; 
                OnPropertyChanged(); 
                
                // Auto-save and recalculate headers
                _ = SaveSmartLedgerAsync();
                UpdateSmartLedgerHeaders();
            }
        }
    }

    public ObservableCollection<string> SmartLedgerChatHistory { get; } = new();

    public FinancesDetailPage()
    {
        this.InitializeComponent();

        if (!Windows.ApplicationModel.DesignMode.DesignModeEnabled)
        {
            _financesService = App.Current.Services.GetRequiredService<IFinancesService>();
            _macroService = App.Current.Services.GetRequiredService<IMacroService>();
            _heatmapService = App.Current.Services.GetRequiredService<IHeatmapService>();
            this.Unloaded += Page_Unloaded;
        }
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        if (_financesService != null)
        {
            _financesService.OnQuotesUpdated += OnQuotesUpdated;
        }
        await LoadDataAsync();
        
        // Auto-select tab based on FinancesService state
        if (_financesService.CurrentViewType == "Stocks") MainPivot.SelectedIndex = 1;
        else if (_financesService.CurrentViewType == "Money") MainPivot.SelectedIndex = 2;
        else MainPivot.SelectedIndex = 0;
    }

    private void Page_Unloaded(object sender, RoutedEventArgs e)
    {
        if (_financesService != null)
        {
            _financesService.OnQuotesUpdated -= OnQuotesUpdated;
        }
    }

    private void OnQuotesUpdated()
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            await LoadDataAsync(showLoadingSpinner: false);
        });
    }

    private async Task LoadDataAsync(bool showLoadingSpinner = true)
    {
        await _loadLock.WaitAsync();
        try
        {
            if (showLoadingSpinner)
            {
                IsWorldLoading = true;
                IsStocksLoading = true;
                IsMoneyLoading = true;

                MacroIndicators.Clear();
                HeatmapData.Clear();
                Holdings.Clear();
                Accounts.Clear();
            }

            // World
            var macros = await _macroService.GetMacroIndicatorsAsync();
            var heatmap = await _heatmapService.GetGlobalHeatmapDataAsync();

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

            // Money
            var ledger = await _financesService.GetSmartLedgerAsync();
            var nw = await _financesService.GetNetWorthAsync();
            var accounts = await _financesService.GetAccountsAsync();

            // Synchronously update the UI lists/properties at the very end
            MacroIndicators.Clear();
            foreach (var m in macros) MacroIndicators.Add(m);

            HeatmapData.Clear();
            foreach (var h in heatmap) HeatmapData.Add(h);

            _allWatchlistStocks = allStocks;
            
            // Add portfolio stocks to all watchlist if not present
            foreach (var p in portfolio)
            {
                if (!_allWatchlistStocks.Any(x => x.Symbol == p.Symbol))
                {
                    _allWatchlistStocks.Add((StockQuote)p);
                }
            }
            
            _ = FilterWatchlistAsync(StocksBtn.IsChecked == true ? "stock" : CryptoBtn.IsChecked == true ? "crypto" : "forex", showLoadingSpinner: false);

            if (ledger != null)
            {
                _smartLedgerText = ledger.LedgerText;
                OnPropertyChanged(nameof(SmartLedgerText));
                UpdateSmartLedgerHeaders();
            }
            
            NetWorthDisplay = nw.ToString("C0");

            decimal cash = accounts.Sum(a => a.CurrentBalance);
            CashDisplay = cash.ToString("C0");
            
            Accounts.Clear();
            foreach (var a in accounts) Accounts.Add(a);

            decimal investments = portfolio.OfType<PortfolioItem>().Sum(p => p.TotalValue);
            InvestmentsDisplay = investments.ToString("C0");

            Holdings.Clear();
            foreach (var p in portfolio) Holdings.Add(p);

            try
            {
                var behaviorService = App.Current.Services.GetService<Daily_WinUI.Services.IBehaviorService>();
                if (behaviorService != null)
                {
                    string metadata = $"{{\"netWorth\":{nw},\"cash\":{cash},\"investments\":{investments}}}";
                    _ = behaviorService.TrackEventAsync("Finances", "ViewPortfolio", metadata);
                }
            }
            catch { }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading finances detail: {ex}");
        }
        finally
        {
            if (showLoadingSpinner)
            {
                IsWorldLoading = false;
                IsStocksLoading = false;
                IsMoneyLoading = false;
            }
            _loadLock.Release();
        }
    }

    private async void RefreshBtn_Click(object sender, RoutedEventArgs e)
    {
        await LoadDataAsync();
    }

    public async Task RefreshFromTitleBarAsync()
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
            _ = FilterWatchlistAsync(marketType);

            try
            {
                var behaviorService = App.Current.Services.GetService<Daily_WinUI.Services.IBehaviorService>();
                if (behaviorService != null)
                {
                    string metadata = $"{{\"marketType\":\"{marketType}\"}}";
                    _ = behaviorService.TrackEventAsync("Finances", "FilterMarket", metadata);
                }
            }
            catch { }
        }
    }

    private async Task FilterWatchlistAsync(string marketType, bool showLoadingSpinner = true)
    {
        if (showLoadingSpinner)
        {
            IsStocksLoading = true;
        }
        await _watchlistLock.WaitAsync();
        try
        {
            WatchlistStocks.Clear();
            
            if (showLoadingSpinner)
            {
                // Brief delay to allow UI to render spinner
                await Task.Delay(50);
            }
            
            var filtered = _allWatchlistStocks.Where(x => x.MarketType?.ToLower() == marketType).ToList();

            foreach (var s in filtered)
            {
                WatchlistStocks.Add(s);
            }
        }
        finally
        {
            _watchlistLock.Release();
            if (showLoadingSpinner)
            {
                IsStocksLoading = false;
            }
        }
    }

    private async Task SaveSmartLedgerAsync()
    {
        if (_financesService == null) return;
        
        // Use the parser to ensure totals are re-calculated
        var recalculated = Daily.Services.Finances.SmartLedgerParser.RecalculateTotals(_smartLedgerText);
        if (_smartLedgerText != recalculated)
        {
            _smartLedgerText = recalculated;
            OnPropertyChanged(nameof(SmartLedgerText));
        }

        await _financesService.SaveSmartLedgerAsync(_smartLedgerText);
    }

    private void UpdateSmartLedgerHeaders()
    {
        var headers = Daily.Services.Finances.SmartLedgerParser.ExtractHeaders(_smartLedgerText);
        NetWorthDisplay = headers.NetWorth;
        CashDisplay = headers.Cash;
        InvestmentsDisplay = headers.Investments;
    }

    private void LedgerChatInput_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            SendLedgerChatBtn_Click(sender, null);
            e.Handled = true;
        }
    }

    private async void SendLedgerChatBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(LedgerChatInput.Text)) return;
        
        string userText = LedgerChatInput.Text;
        LedgerChatInput.Text = string.Empty;
        
        SmartLedgerChatHistory.Add($"You: {userText}");
        SmartLedgerChatHistory.Add("AI: Processing...");
        
        try 
        {
            var briefingEngine = App.Current.Services.GetRequiredService<Daily_WinUI.Services.ISmartBriefingEngine>();
            
            // System prompt instructing to output JSON command
            string prompt = $@"
You are a financial AI assistant. The user will tell you about an expense or a transfer they made.
Return a JSON command using this structure ONLY: {{ ""action"": ""transfer"", ""source"": ""Card"", ""target"": ""Mega"", ""amount"": 5 }}
If the source is not specified, assume 'Card'. If it's a new income, assume target is 'Card' and action is 'transfer'.
Just the JSON, nothing else.

User Input: {userText}
";
            
            var aiResponse = await briefingEngine.GenerateBriefingAsync(prompt);
            SmartLedgerChatHistory[^1] = $"AI: {aiResponse}";
            
            // Try parse JSON
            var options = new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            var command = System.Text.Json.JsonSerializer.Deserialize<Daily.Services.Finances.SmartLedgerParser.LedgerCommand>(aiResponse, options);
            
            if (command != null && command.action != null)
            {
                var newText = Daily.Services.Finances.SmartLedgerParser.ExecuteCommand(SmartLedgerText, command);
                SmartLedgerText = newText; // Triggers setter, which saves and recalculates
                SmartLedgerChatHistory.Add($"AI: Updated ledger successfully.");
            }
        }
        catch (Exception ex)
        {
            SmartLedgerChatHistory[^1] = $"AI: Failed to process command.";
            System.Diagnostics.Debug.WriteLine($"Smart Ledger AI error: {ex}");
        }
    }
}
