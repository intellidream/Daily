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

    // Money / Smart Ledger
    private string _formattedNetWorth = "0 Lei";
    public string FormattedNetWorth
    {
        get => _formattedNetWorth;
        set { _formattedNetWorth = value; OnPropertyChanged(); }
    }

    private string _formattedNetWorthEUR = "~0 €";
    public string FormattedNetWorthEUR
    {
        get => _formattedNetWorthEUR;
        set { _formattedNetWorthEUR = value; OnPropertyChanged(); }
    }

    private string _formattedDeposits = "0 Lei";
    public string FormattedDeposits
    {
        get => _formattedDeposits;
        set { _formattedDeposits = value; OnPropertyChanged(); }
    }

    private string _formattedBalance = "0 Lei";
    public string FormattedBalance
    {
        get => _formattedBalance;
        set { _formattedBalance = value; OnPropertyChanged(); }
    }

    private string _formattedIncoming = "0 Lei";
    public string FormattedIncoming
    {
        get => _formattedIncoming;
        set { _formattedIncoming = value; OnPropertyChanged(); }
    }

    private string _formattedDentist = "0 Lei";
    public string FormattedDentist
    {
        get => _formattedDentist;
        set { _formattedDentist = value; OnPropertyChanged(); }
    }

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

    public ObservableCollection<SmartLedgerSection> LedgerSections { get; } = new();
    public ParsedSmartLedger? CurrentParsedLedger { get; private set; }

    public ObservableCollection<LocalAccount> Accounts { get; } = new();
    
    // Using object here since PortfolioItem inherits from StockQuote but we might just use StockQuote
    public ObservableCollection<object> Holdings { get; } = new();

    public ObservableCollection<Daily.Models.Finances.LocalLedgerTransaction> LedgerTransactions { get; } = new();

    // Smart Ledger Text
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
                
                // Parse AST and update sections & headers
                UpdateParsedLedgerUI();

                // Save to SQLite and Supabase
                _ = SaveSmartLedgerAsync();
            }
        }
    }

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
        if (this.Frame != App.Current?.MainWindow?.RootFrame)
        {
            if (BackButton != null) BackButton.Visibility = Visibility.Collapsed;
            if (PopOutButton != null) PopOutButton.Visibility = Visibility.Collapsed;
        }

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
            await _financesService.ProcessRecurringTransactionsAsync();
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
                UpdateParsedLedgerUI();
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
                var transactions = await _financesService.GetLedgerTransactionsAsync();
                LedgerTransactions.Clear();
                foreach (var tx in transactions) LedgerTransactions.Add(tx);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error loading ledger transactions: {ex.Message}");
            }

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
        if (this.Frame?.CanGoBack == true)
        {
            this.Frame.GoBack();
        }
        else
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(1);
            }
            else
            {
                this.Frame?.Navigate(typeof(MainPage));
            }
        }
    }

    private void PopOutButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current?.MainWindow is MainWindow mw)
        {
            mw.OpenDetailWindow(typeof(FinancesDetailPage));
            mw.NavigateToTab(1);
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

    private void UpdateParsedLedgerUI()
    {
        if (string.IsNullOrWhiteSpace(_smartLedgerText))
        {
            LedgerSections.Clear();
            FormattedNetWorth = "0 Lei";
            FormattedNetWorthEUR = "~0 €";
            FormattedDeposits = "0 Lei";
            FormattedBalance = "0 Lei";
            FormattedIncoming = "0 Lei";
            FormattedDentist = "0 Lei";
            return;
        }

        var parsed = Daily.Services.Finances.SmartLedgerParser.Parse(_smartLedgerText);
        CurrentParsedLedger = parsed;

        FormattedNetWorth = parsed.FormattedNetWorth;
        FormattedNetWorthEUR = $"~{parsed.NetWorthEUR:N0} €";
        FormattedDeposits = $"{parsed.DepositTotal:N0} Lei";
        FormattedBalance = $"{parsed.BalanceTotal:N0} Lei";
        FormattedIncoming = $"{parsed.IncomingTotal:N0} Lei";
        FormattedDentist = $"{parsed.DentistTotal:N0} Lei";

        LedgerSections.Clear();
        foreach (var s in parsed.Sections)
        {
            LedgerSections.Add(s);
        }
    }

    private async void EditRawDsl_Click(object sender, RoutedEventArgs e)
    {
        var textBox = new TextBox
        {
            Text = SmartLedgerText,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
            MinHeight = 400,
            MinWidth = 550
        };
        ScrollViewer.SetVerticalScrollBarVisibility(textBox, ScrollBarVisibility.Auto);

        var dialog = new ContentDialog
        {
            Title = "Edit Smart Ledger DSL",
            PrimaryButtonText = "Save & Recalculate",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = textBox,
            XamlRoot = this.XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            SmartLedgerText = textBox.Text;
        }
    }

    private async void RefreshLedger_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            IsMoneyLoading = true;
            var ledger = await _financesService.GetSmartLedgerAsync();
            if (ledger != null && !string.IsNullOrWhiteSpace(ledger.LedgerText))
            {
                _smartLedgerText = ledger.LedgerText;
                OnPropertyChanged(nameof(SmartLedgerText));
                UpdateParsedLedgerUI();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error refreshing ledger: {ex.Message}");
        }
        finally
        {
            IsMoneyLoading = false;
        }
    }

    private void ItemMinus_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is SmartLedgerItem item)
        {
            decimal delta = item.IsScaled ? -1m : -100m;
            var newText = Daily.Services.Finances.SmartLedgerParser.AdjustItemAmount(SmartLedgerText, item, delta);
            SmartLedgerText = newText;
        }
    }

    private void ItemPlus_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is SmartLedgerItem item)
        {
            decimal delta = item.IsScaled ? 1m : 100m;
            var newText = Daily.Services.Finances.SmartLedgerParser.AdjustItemAmount(SmartLedgerText, item, delta);
            SmartLedgerText = newText;
        }
    }

    private async void ItemQuickAdjust_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not SmartLedgerItem item) return;

        var stack = new StackPanel { Spacing = 16, MinWidth = 320 };
        stack.Children.Add(new TextBlock 
        { 
            Text = $"Current: {item.DisplayName} = {item.RawAmount} ({item.FormattedCalculatedAmount})", 
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold 
        });

        var numberBox = new TextBox
        {
            Text = item.RawAmount.ToString(),
            PlaceholderText = "New raw amount..."
        };
        stack.Children.Add(numberBox);

        var quickButtonsPanel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        var deltas = item.IsScaled ? new decimal[] { -5, -1, 1, 5 } : new decimal[] { -500, -100, 100, 500 };
        foreach (var d in deltas)
        {
            var deltaBtn = new Button 
            { 
                Content = d > 0 ? $"+{d}" : $"{d}", 
                Padding = new Thickness(10, 4, 10, 4) 
            };
            deltaBtn.Click += (s, args) =>
            {
                if (decimal.TryParse(numberBox.Text, out var currentVal))
                {
                    numberBox.Text = Math.Max(0, currentVal + d).ToString();
                }
            };
            quickButtonsPanel.Children.Add(deltaBtn);
        }
        stack.Children.Add(quickButtonsPanel);

        var dialog = new ContentDialog
        {
            Title = $"Quick Adjust · {item.DisplayName}",
            PrimaryButtonText = "Set Amount",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = stack,
            XamlRoot = this.XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            if (decimal.TryParse(numberBox.Text, out var newAmt))
            {
                var newText = Daily.Services.Finances.SmartLedgerParser.SetItemAmount(SmartLedgerText, item, newAmt);
                SmartLedgerText = newText;
            }
        }
    }

    private async void AddSectionItem_Click(object sender, RoutedEventArgs e)
    {
        string sectionName = (sender as Button)?.Tag as string ?? "Outgoing";

        var stack = new StackPanel { Spacing = 12, MinWidth = 320 };
        stack.Children.Add(new TextBlock { Text = $"Add item to section: {sectionName}", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });

        var nameBox = new TextBox { PlaceholderText = "Item name (e.g. Netflix, Sala, Bonus)" };
        var amountBox = new TextBox { PlaceholderText = "Amount (e.g. 50 or 100)" };
        var scaledCheck = new CheckBox { Content = "Scaled item (e.g. daily/multiplier like Tigari)", IsChecked = false };

        stack.Children.Add(nameBox);
        stack.Children.Add(amountBox);
        stack.Children.Add(scaledCheck);

        var dialog = new ContentDialog
        {
            Title = "Add Ledger Item",
            PrimaryButtonText = "Add Item",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = stack,
            XamlRoot = this.XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(nameBox.Text))
        {
            decimal.TryParse(amountBox.Text, out var amount);
            var newText = Daily.Services.Finances.SmartLedgerParser.AddItem(
                SmartLedgerText, 
                sectionName, 
                nameBox.Text.Trim(), 
                amount, 
                "Lei", 
                scaledCheck.IsChecked == true);
            SmartLedgerText = newText;
        }
    }
}
