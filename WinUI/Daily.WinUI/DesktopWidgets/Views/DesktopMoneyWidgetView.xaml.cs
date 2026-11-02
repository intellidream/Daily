using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services.Finances;
using Daily.Models.Finances;
using Daily_WinUI.Controls;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopMoneyWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private IFinancesService? _financesService;

        public DesktopMoneyWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            _model = model;
            _hostWindow = hostWindow;
            this.InitializeComponent();

            ApplySizeLayout();
        }

        private void ApplySizeLayout()
        {
            if (_model.Size == DesktopWidgetSize.Small)
            {
                SmallLayout.Visibility = Visibility.Visible;
                MediumLargeLayout.Visibility = Visibility.Collapsed;
            }
            else
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLargeLayout.Visibility = Visibility.Visible;
            }
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _financesService = App.Current.Services?.GetService<IFinancesService>();
                if (_financesService != null)
                {
                    _financesService.OnSmartLedgerUpdated += FinancesService_OnSmartLedgerUpdated;
                    _financesService.OnQuotesUpdated += FinancesService_OnSmartLedgerUpdated;
                }
            }
            catch { }

            RefreshData();
        }

        private void FinancesService_OnSmartLedgerUpdated()
        {
            DispatcherQueue.TryEnqueue(RefreshData);
        }

        public async void RefreshData()
        {
            if (_financesService == null)
            {
                try { _financesService = App.Current.Services?.GetService<IFinancesService>(); } catch { }
            }

            try
            {
                var snapshot = FinancesWidgetControl.SharedSnapshot;
                if (snapshot != null)
                {
                    UpdateUIFromSnapshot(snapshot);
                    return;
                }

                if (_financesService != null)
                {
                    var ledger = await _financesService.GetSmartLedgerAsync();
                    var accounts = await _financesService.GetAccountsAsync();
                    decimal totalNet = 0;

                    var cardAcc = accounts.FirstOrDefault(a => a.Name?.ToLowerInvariant().Contains("card") == true);
                    var cashAcc = accounts.FirstOrDefault(a => a.Name?.ToLowerInvariant().Contains("cash") == true);

                    decimal cardBal = cardAcc?.CurrentBalance ?? 0;
                    decimal cashBal = cashAcc?.CurrentBalance ?? 0;

                    if (accounts.Count > 0)
                    {
                        totalNet = accounts.Sum(a => a.CurrentBalance);
                    }
                    else if (ledger != null && !string.IsNullOrWhiteSpace(ledger.LedgerText))
                    {
                        var parsed = SmartLedgerParser.Parse(ledger.LedgerText);
                        totalNet = parsed.NetWorth;
                        cardBal = parsed.BalanceTotal;
                    }

                    decimal eurEst = totalNet > 0 ? totalNet / 4.97m : 0;

                    SmallNetWorthText.Text = $"{totalNet:N0} Lei";
                    SmallNetWorthEurText.Text = $"~{eurEst:N0} €";
                    SmallBalancePillText.Text = $"Card: {cardBal:N0} · Cash: {cashBal:N0}";

                    MediumNetWorthText.Text = $"{totalNet:N0} Lei";
                    MediumEurSubtitle.Text = $"~{eurEst:N0} € Net Balance";
                    CardBalanceText.Text = $"{cardBal:N0} Lei";
                    CashBalanceText.Text = $"{cashBal:N0} Lei";
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopMoneyWidget] Error refreshing: {ex.Message}");
            }
        }

        private void UpdateUIFromSnapshot(FinancesSnapshot snapshot)
        {
            SmallNetWorthText.Text = snapshot.SmartNetWorthDisplay;
            SmallNetWorthEurText.Text = snapshot.SmartNetWorthEurDisplay;
            SmallBalancePillText.Text = snapshot.SmartFlowDisplay;

            MediumNetWorthText.Text = snapshot.SmartNetWorthDisplay;
            MediumEurSubtitle.Text = $"{snapshot.SmartNetWorthEurDisplay} Net Balance";

            var cardAcc = snapshot.Accounts.FirstOrDefault(a => a.Name?.ToLowerInvariant().Contains("card") == true);
            var cashAcc = snapshot.Accounts.FirstOrDefault(a => a.Name?.ToLowerInvariant().Contains("cash") == true);

            CardBalanceText.Text = cardAcc != null ? $"{cardAcc.CurrentBalance:N0} Lei" : snapshot.SmartBalanceDisplay;
            CashBalanceText.Text = cashAcc != null ? $"{cashAcc.CurrentBalance:N0} Lei" : $"{snapshot.Cash:N0} Lei";
        }

        private async void AdjustCardPlus100_Click(object sender, RoutedEventArgs e)
        {
            await AdjustAccountAsync("Card", 100);
        }

        private async void AdjustCardMinus100_Click(object sender, RoutedEventArgs e)
        {
            await AdjustAccountAsync("Card", -100);
        }

        private async void AdjustCashPlus100_Click(object sender, RoutedEventArgs e)
        {
            await AdjustAccountAsync("Cash", 100);
        }

        private async Task AdjustAccountAsync(string accountName, decimal delta)
        {
            if (_financesService == null) return;
            try
            {
                var accounts = await _financesService.GetAccountsAsync();
                var acc = accounts.FirstOrDefault(a => a.Name?.ToLowerInvariant().Contains(accountName.ToLowerInvariant()) == true);
                if (acc != null)
                {
                    acc.CurrentBalance += delta;
                    await _financesService.AddTransactionAsync(new LocalTransaction
                    {
                        AccountId = acc.Id,
                        Amount = delta,
                        Description = $"Quick Desktop Adjust ({(delta > 0 ? "+" : "")}{delta:N0})",
                        Date = DateTime.UtcNow
                    });
                }
                else
                {
                    // Fallback to ledger adjustment
                    var ledger = await _financesService.GetSmartLedgerAsync();
                    string currentText = ledger?.LedgerText ?? "";
                    string sign = delta > 0 ? "+" : "-";
                    string newText = $"{currentText.Trim()}\n{DateTime.Now:yyyy-MM-dd} QuickAdjust {accountName} {sign}{Math.Abs(delta)} Lei";
                    await _financesService.SaveSmartLedgerAsync(newText);
                }

                RefreshData();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopMoneyWidget] Error adjusting account: {ex.Message}");
            }
        }
    }
}
