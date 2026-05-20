using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services.Finances;
using Daily.Models.Finances;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Daily_WinUI.Controls;

public sealed partial class FinancesWidgetControl : UserControl, INotifyPropertyChanged
{
    private IFinancesService _financesService;
    private IMacroService _macroService;
    private IHeatmapService _heatmapService;
    private Daily.Services.IRefreshService _refreshService;

    // View State
    public event PropertyChangedEventHandler PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

        private bool _isLoading;
    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; OnPropertyChanged(); }
    }

    private string _currentViewLabel = "World";
    public string CurrentViewLabel
    {
        get => _currentViewLabel;
        set { _currentViewLabel = value; OnPropertyChanged(); }
    }

    // World Data
    public ObservableCollection<MacroIndicator> MacroIndicators { get; } = new();
    public ObservableCollection<CountryEconomicData> HeatmapData { get; } = new();
    
    private bool _hasHeatmapData;
    public bool HasHeatmapData
    {
        get => _hasHeatmapData;
        set { _hasHeatmapData = value; OnPropertyChanged(); }
    }

    // Stocks Data
    public ObservableCollection<StockQuote> TopStocks { get; } = new();
    public ObservableCollection<StockQuote> ExtendedStocks { get; } = new();
    
    private bool _hasStocks;
    public bool HasStocks
    {
        get => _hasStocks;
        set { _hasStocks = value; OnPropertyChanged(); }
    }

    // Money Data
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
    
    private bool _hasAccounts;
    public bool HasAccounts
    {
        get => _hasAccounts;
        set { _hasAccounts = value; OnPropertyChanged(); }
    }

    public FinancesWidgetControl()
    {
        this.InitializeComponent();

        if (!Windows.ApplicationModel.DesignMode.DesignModeEnabled)
        {
            _financesService = App.Current.Services.GetRequiredService<IFinancesService>();
            _macroService = App.Current.Services.GetRequiredService<IMacroService>();
            _heatmapService = App.Current.Services.GetRequiredService<IHeatmapService>();
            _refreshService = App.Current.Services.GetRequiredService<Daily.Services.IRefreshService>();
            _refreshService.RefreshRequested += () =>
            {
                DispatcherQueue.TryEnqueue(async () =>
                {
                    await LoadDataAsync();
                });
                return Task.CompletedTask;
            };

            this.Loaded += OnLoaded;
            this.SizeChanged += OnSizeChanged;
        }
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await LoadDataAsync();
        UpdateAdaptiveState(this.ActualWidth, this.ActualHeight);
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        UpdateAdaptiveState(e.NewSize.Width, e.NewSize.Height);
    }

    private void UpdateAdaptiveState(double width, double height)
    {
        if (width <= 0 || height <= 0) return;

        bool isWide = width >= 250;
        bool isTall = height >= 250;

        if (isWide && isTall)
        {
            VisualStateManager.GoToState(this, "LargeState", false);
        }
        else if (isWide)
        {
            VisualStateManager.GoToState(this, "NormalState", false); // Wide
        }
        else if (isTall)
        {
            VisualStateManager.GoToState(this, "TallState", false);
        }
        else
        {
            VisualStateManager.GoToState(this, "SmallState", false);
        }
    }

        public async Task LoadDataAsync()
    {
        IsLoading = true;
        MacroIndicators.Clear();
        HeatmapData.Clear();
        TopStocks.Clear();
        ExtendedStocks.Clear();

        try
        {
            // 1. World Data
            var macros = await _macroService.GetMacroIndicatorsAsync();
            MacroIndicators.Clear();
            foreach (var m in macros.Take(4)) MacroIndicators.Add(m);

            var heatmap = await _heatmapService.GetGlobalHeatmapDataAsync();
            HeatmapData.Clear();
            foreach (var h in heatmap.Take(8)) HeatmapData.Add(h);
            HasHeatmapData = HeatmapData.Any();

            // 2. Money Data
            var nw = await _financesService.GetNetWorthAsync();
            NetWorthDisplay = nw.ToString("C0");

            var accounts = await _financesService.GetAccountsAsync();
            decimal cash = accounts.Sum(a => a.CurrentBalance);
            CashDisplay = cash.ToString("C0");
            
            Accounts.Clear();
            foreach (var a in accounts.Take(5)) Accounts.Add(a);
            HasAccounts = Accounts.Any();

            // 3. Stocks Data
            var portfolio = await _financesService.GetHoldingsWithQuotesAsync();
            decimal investments = portfolio.OfType<PortfolioItem>().Sum(p => p.TotalValue);
            InvestmentsDisplay = investments.ToString("C0");

            var stocksToDisplay = portfolio;
            if (!stocksToDisplay.Any())
            {
                // Fallback to defaults via API
                stocksToDisplay = await _financesService.GetStockQuotesAsync(new List<string> { "AAPL", "MSFT", "NVDA", "TSLA" });
                
                // Hard fallback if API fails
                if (!stocksToDisplay.Any())
                {
                    stocksToDisplay = new List<StockQuote>
                    {
                        new StockQuote { Symbol = "AAPL", CompanyName = "Apple", CurrentPrice = 175.50m, PercentChange = 1.2m, MarketType = "stock" },
                        new StockQuote { Symbol = "MSFT", CompanyName = "Microsoft", CurrentPrice = 330.10m, PercentChange = 0.5m, MarketType = "stock" },
                        new StockQuote { Symbol = "NVDA", CompanyName = "Nvidia", CurrentPrice = 450.25m, PercentChange = 2.1m, MarketType = "stock" },
                        new StockQuote { Symbol = "TSLA", CompanyName = "Tesla", CurrentPrice = 210.80m, PercentChange = -1.5m, MarketType = "stock" }
                    };
                }
            }

            TopStocks.Clear();
            ExtendedStocks.Clear();
            
            var top = stocksToDisplay.Take(4).ToList();
            
            var _cryptoSymbols = new List<string> { "BTC-USD", "ETH-USD", "SOL-USD", "BNB-USD", "XRP-USD", "DOGE-USD", "ADA-USD", "AVAX-USD", "DOT-USD", "LINK-USD" };
            var cryptoDefaults = await _financesService.GetStockQuotesAsync(_cryptoSymbols);
            var extended = cryptoDefaults.Take(10).ToList();

            foreach (var s in top) TopStocks.Add(s);
            foreach (var s in extended) ExtendedStocks.Add(s);
            HasStocks = TopStocks.Any();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading finance widget data: {ex}");
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void FlipView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FinancesFlipView.SelectedIndex == 0) CurrentViewLabel = "World";
        else if (FinancesFlipView.SelectedIndex == 1) CurrentViewLabel = "Stocks";
        else if (FinancesFlipView.SelectedIndex == 2) CurrentViewLabel = "Money";
    }

    private void Prev_Click(object sender, RoutedEventArgs e)
    {
        if (FinancesFlipView.SelectedIndex > 0)
            FinancesFlipView.SelectedIndex--;
        else
            FinancesFlipView.SelectedIndex = FinancesFlipView.Items.Count - 1;
    }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (FinancesFlipView.SelectedIndex < FinancesFlipView.Items.Count - 1)
            FinancesFlipView.SelectedIndex++;
        else
            FinancesFlipView.SelectedIndex = 0;
    }



    private void Header_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        HeaderGrid.Opacity = 0.8;
    }

    private void Header_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        HeaderGrid.Opacity = 1.0;
    }
}

