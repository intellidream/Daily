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
    private Daily.Services.ISyncService? _syncService;
    private readonly SemaphoreSlim _loadLock = new(1, 1);
    private readonly SemaphoreSlim _watchlistLock = new(1, 1);
    private bool _isUpdatingFromService;

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

                // Save to SQLite and Supabase only when modified by user interaction
                if (!_isUpdatingFromService)
                {
                    _ = SaveSmartLedgerAsync();
                }
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
            _syncService = App.Current.Services.GetService<Daily.Services.ISyncService>();
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
            _financesService.OnQuotesUpdated -= OnQuotesUpdated;
            _financesService.OnQuotesUpdated += OnQuotesUpdated;
            _financesService.OnSmartLedgerUpdated -= OnSmartLedgerUpdated;
            _financesService.OnSmartLedgerUpdated += OnSmartLedgerUpdated;
        }
        if (_syncService != null)
        {
            _syncService.OnFinancesPulled -= OnSmartLedgerUpdated;
            _syncService.OnFinancesPulled += OnSmartLedgerUpdated;
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
            _financesService.OnSmartLedgerUpdated -= OnSmartLedgerUpdated;
        }
        if (_syncService != null)
        {
            _syncService.OnFinancesPulled -= OnSmartLedgerUpdated;
        }
    }

    private void OnQuotesUpdated()
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            await LoadDataAsync(showLoadingSpinner: false);
        });
    }

    private void OnSmartLedgerUpdated()
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            try
            {
                var ledger = await _financesService.GetSmartLedgerAsync();
                if (ledger != null && !string.IsNullOrWhiteSpace(ledger.LedgerText) && ledger.LedgerText != _smartLedgerText)
                {
                    _isUpdatingFromService = true;
                    try
                    {
                        SmartLedgerText = ledger.LedgerText;
                    }
                    finally
                    {
                        _isUpdatingFromService = false;
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[FinancesDetailPage] OnSmartLedgerUpdated error: {ex.Message}");
            }
        });
    }

    private async Task LoadDataAsync(bool showLoadingSpinner = true, bool forceRefresh = false)
    {
        await _loadLock.WaitAsync();
        try
        {
            if (showLoadingSpinner)
            {
                IsWorldLoading = !MacroIndicators.Any();
                IsStocksLoading = !WatchlistStocks.Any();
                IsMoneyLoading = !LedgerSections.Any();
            }

            // World
            var macros = await _macroService.GetMacroIndicatorsAsync();
            var heatmap = await _heatmapService.GetGlobalHeatmapDataAsync();

            // Stocks (All stocks in watchlist)
            var portfolio = await _financesService.GetHoldingsWithQuotesAsync();
            
            var watchlistSymbols = await _financesService.GetWatchlistSymbolsAsync(forceRefresh);
            var _trackedSymbols = new List<string> 
            { 
                "AAPL", "MSFT", "NVDA", "TSLA", "GOOGL", "AMZN", "META",
                "TLV.RO", "H2O.RO", "SNG.RO", "SNP.RO",
                "ASML", "TSM", "SAP", "RMS.PA" 
            };
            var _cryptoSymbols = new List<string> { "BTC-USD", "ETH-USD", "SOL-USD", "BNB-USD", "XRP-USD", "DOGE-USD", "ADA-USD", "AVAX-USD", "DOT-USD", "LINK-USD" };
            var _forexSymbols = new List<string> { "EURUSD=X", "JPY=X", "GBPUSD=X", "AUDUSD=X" };

            var allSymbols = _trackedSymbols.Concat(watchlistSymbols).Concat(_cryptoSymbols).Concat(_forexSymbols).Distinct().ToList();
            var allStocks = await _financesService.GetStockQuotesAsync(allSymbols, forceRefresh);

            // Money
            await _financesService.ProcessRecurringTransactionsAsync();
            var ledger = await _financesService.GetSmartLedgerAsync(forceRefresh);
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
                _isUpdatingFromService = true;
                try
                {
                    _smartLedgerText = ledger.LedgerText;
                    OnPropertyChanged(nameof(SmartLedgerText));
                    UpdateParsedLedgerUI();
                }
                finally
                {
                    _isUpdatingFromService = false;
                }
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
        if (_syncService != null)
        {
            try { await _syncService.SyncAsync(Daily.Services.SyncScope.Finances); } catch { }
        }
        await LoadDataAsync(showLoadingSpinner: true, forceRefresh: true);
    }

    public async Task RefreshFromTitleBarAsync()
    {
        if (_syncService != null)
        {
            try { await _syncService.SyncAsync(Daily.Services.SyncScope.Finances); } catch { }
        }
        await LoadDataAsync(showLoadingSpinner: false, forceRefresh: true);
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
        if (_financesService == null || _isUpdatingFromService) return;
        
        // Use the parser to ensure totals are re-calculated
        var recalculated = Daily.Services.Finances.SmartLedgerParser.RecalculateTotals(_smartLedgerText);
        if (_smartLedgerText != recalculated)
        {
            _smartLedgerText = recalculated;
            OnPropertyChanged(nameof(SmartLedgerText));
            UpdateParsedLedgerUI();
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
            if (_syncService != null)
            {
                try { await _syncService.SyncAsync(Daily.Services.SyncScope.Finances); } catch { }
            }
            var ledger = await _financesService.GetSmartLedgerAsync(forceRefresh: true);
            if (ledger != null && !string.IsNullOrWhiteSpace(ledger.LedgerText))
            {
                _isUpdatingFromService = true;
                try
                {
                    _smartLedgerText = ledger.LedgerText;
                    OnPropertyChanged(nameof(SmartLedgerText));
                    UpdateParsedLedgerUI();
                }
                finally
                {
                    _isUpdatingFromService = false;
                }
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
        if (sender is Button btn && btn.Tag is SmartLedgerItem item && !item.IsPureNote)
        {
            decimal delta = item.IsScaled ? -1m : -100m;
            var newText = Daily.Services.Finances.SmartLedgerParser.AdjustItemAmount(SmartLedgerText, item, delta);
            SmartLedgerText = newText;
        }
    }

    private void ItemPlus_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is SmartLedgerItem item && !item.IsPureNote)
        {
            decimal delta = item.IsScaled ? 1m : 100m;
            var newText = Daily.Services.Finances.SmartLedgerParser.AdjustItemAmount(SmartLedgerText, item, delta);
            SmartLedgerText = newText;
        }
    }

    private async void ItemQuickAdjust_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not SmartLedgerItem item || item.IsPureNote) return;

        var stack = new StackPanel { Spacing = 14, MinWidth = 380 };
        var previewText = new TextBlock
        {
            Text = item.IsScaled
                ? $"Unitate DSL (1 = 100 Lei) · Actual: {item.FormattedCalculatedAmount}"
                : $"Sumă directă ({item.Currency}) · Actual: {item.FormattedCalculatedAmount}",
            FontSize = 12,
            Opacity = 0.75
        };
        stack.Children.Add(previewText);

        var numberBox = new TextBox
        {
            Header = item.IsScaled ? "Valoare DSL (1 = 100 Lei)" : $"Valoare ({item.Currency})",
            Text = item.FormattedRawAmount,
            PlaceholderText = "Valoare..."
        };

        void UpdatePreview()
        {
            var rawStr = (numberBox.Text ?? string.Empty).Trim().Replace(',', '.');
            if (decimal.TryParse(rawStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var val))
            {
                decimal calc = item.IsScaled ? val * 100m : val;
                string unit = item.Currency == "EUR" ? "€" : "Lei";
                previewText.Text = item.IsScaled
                    ? $"Unitate DSL: {val:0.##}  →  = {calc:N0} {unit}"
                    : $"Valoare nouă: {calc:N0} {unit}";
            }
        }
        numberBox.TextChanged += (_, _) => UpdatePreview();
        stack.Children.Add(numberBox);

        var quickButtonsPanel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Left };
        var deltas = item.IsScaled
            ? new (decimal rawDelta, string label)[] { (-5m, "-500"), (-2m, "-200"), (-1m, "-100"), (1m, "+100"), (2m, "+200"), (5m, "+500"), (10m, "+1000") }
            : new (decimal rawDelta, string label)[] { (-1000m, "-1k"), (-500m, "-500"), (500m, "+500"), (1000m, "+1k"), (5000m, "+5k") };

        foreach (var (rawDelta, label) in deltas)
        {
            var deltaBtn = new Button
            {
                Content = label,
                Padding = new Thickness(9, 4, 9, 4),
                CornerRadius = new CornerRadius(10)
            };
            deltaBtn.Click += (_, _) =>
            {
                var rawStr = (numberBox.Text ?? string.Empty).Trim().Replace(',', '.');
                if (decimal.TryParse(rawStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var currentVal))
                {
                    var nextVal = Math.Max(0m, currentVal + rawDelta);
                    numberBox.Text = nextVal % 1 == 0
                        ? ((long)nextVal).ToString(System.Globalization.CultureInfo.InvariantCulture)
                        : nextVal.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
                }
            };
            quickButtonsPanel.Children.Add(deltaBtn);
        }
        stack.Children.Add(quickButtonsPanel);

        string originalNotes = item.Notes != null && item.Notes.Count > 0 ? string.Join(" / ", item.Notes) : string.Empty;
        var noteBox = new TextBox
        {
            Header = "Notă opțională (în paranteze)",
            Text = originalNotes,
            PlaceholderText = "ex: Rz/141/Ing/10 sau C$40/B$20"
        };
        stack.Children.Add(noteBox);

        var dialog = new ContentDialog
        {
            Title = $"Adjust · {item.DisplayName}",
            PrimaryButtonText = "Save",
            SecondaryButtonText = "Delete Item",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = stack,
            XamlRoot = this.XamlRoot
        };

        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            var rawStr = (numberBox.Text ?? string.Empty).Trim().Replace(',', '.');
            if (decimal.TryParse(rawStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var newAmt))
            {
                var newText = Daily.Services.Finances.SmartLedgerParser.UpdateItemAmountAndNote(
                    SmartLedgerText,
                    item.LineIndex,
                    Math.Max(0m, newAmt),
                    noteBox.Text,
                    originalNotes);
                SmartLedgerText = newText;
            }
        }
        else if (result == ContentDialogResult.Secondary)
        {
            SmartLedgerText = Daily.Services.Finances.SmartLedgerParser.DeleteItem(SmartLedgerText, item.LineIndex);
        }
    }

    private async void AddSectionItem_Click(object sender, RoutedEventArgs e)
    {
        string sectionName = (sender as Button)?.Tag as string ?? "Outgoing";
        var section = LedgerSections.FirstOrDefault(s => string.Equals(s.Name, sectionName, StringComparison.OrdinalIgnoreCase));
        bool isScaledSection = section?.IsScaled ?? !string.Equals(sectionName, "Deposit", StringComparison.OrdinalIgnoreCase);

        var stack = new StackPanel { Spacing = 12, MinWidth = 360 };
        stack.Children.Add(new TextBlock
        {
            Text = isScaledSection
                ? $"Secțiune: {sectionName} · Unitate DSL (1 = 100 Lei)"
                : $"Secțiune: {sectionName} · Sumă directă",
            FontSize = 12,
            Opacity = 0.75
        });

        var nameBox = new TextBox
        {
            Header = "Categorie / Nume linie",
            PlaceholderText = "ex: Vacanțe, Abonamente, Economii"
        };
        var amountBox = new TextBox
        {
            Header = isScaledSection ? "Valoare DSL (ex: 10 = 1.000 Lei)" : "Sumă (ex: 5000)",
            PlaceholderText = isScaledSection ? "10" : "5000"
        };
        var noteBox = new TextBox
        {
            Header = "Notă opțională (în paranteze)",
            PlaceholderText = "ex: detaliere conturi / scadențe"
        };

        CurrencyComboBoxSetup(out var currencyCombo, isScaledSection);

        stack.Children.Add(nameBox);
        stack.Children.Add(amountBox);
        if (!isScaledSection)
        {
            stack.Children.Add(currencyCombo);
        }
        stack.Children.Add(noteBox);

        var dialog = new ContentDialog
        {
            Title = $"Add to {sectionName}",
            PrimaryButtonText = "Add Item",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = stack,
            XamlRoot = this.XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(nameBox.Text))
        {
            var rawStr = (amountBox.Text ?? string.Empty).Trim().Replace(',', '.');
            decimal.TryParse(rawStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var amount);
            string suffix = (!isScaledSection && currencyCombo.SelectedIndex == 1) ? "€" : "";
            var newText = Daily.Services.Finances.SmartLedgerParser.AddItem(
                SmartLedgerText,
                sectionName,
                nameBox.Text.Trim(),
                Math.Max(0m, amount),
                noteBox.Text,
                suffix);
            SmartLedgerText = newText;
        }
    }

    private static void CurrencyComboBoxSetup(out ComboBox combo, bool isScaledSection)
    {
        combo = new ComboBox
        {
            Header = "Monedă",
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        combo.Items.Add("Lei (RON)");
        combo.Items.Add("EUR (€)");
        combo.SelectedIndex = 0;
        combo.IsEnabled = !isScaledSection;
    }
}
