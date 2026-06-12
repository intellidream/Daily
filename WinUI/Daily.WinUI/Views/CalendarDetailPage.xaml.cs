using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Sockets;
using Daily_WinUI.Services;
using Daily.Configuration;
using Daily.Models;
using Daily.Services;
using Daily.Services.Auth;
using Syncfusion.UI.Xaml.Scheduler;
using Windows.System;

namespace Daily_WinUI.Views
{
    public class DisplayAccount : INotifyPropertyChanged
    {
        public string Id { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string AccountType { get; set; } = string.Empty;
        public string Color { get; set; } = "#512BD4";
        public int DisplayOrder { get; set; }

        private string _customName = string.Empty;
        public string CustomName
        {
            get => _customName;
            set
            {
                if (_customName != value)
                {
                    _customName = value;
                    OnPropertyChanged();
                    RefreshComputedProperties();
                }
            }
        }

        private string _identifiedName = string.Empty;
        public string IdentifiedName
        {
            get => _identifiedName;
            set
            {
                if (_identifiedName != value)
                {
                    _identifiedName = value;
                    OnPropertyChanged();
                    RefreshComputedProperties();
                }
            }
        }

        private bool _isActive;
        public bool IsActive
        {
            get => _isActive;
            set
            {
                if (_isActive != value)
                {
                    _isActive = value;
                    OnPropertyChanged();
                }
            }
        }

        private bool _isEditing;
        public bool IsEditing
        {
            get => _isEditing;
            set
            {
                if (_isEditing != value)
                {
                    _isEditing = value;
                    OnPropertyChanged();
                    OnPropertyChanged(nameof(EditModeVisibility));
                    OnPropertyChanged(nameof(ViewModeVisibility));
                }
            }
        }

        public Visibility EditModeVisibility => IsEditing ? Visibility.Visible : Visibility.Collapsed;
        public Visibility ViewModeVisibility => IsEditing ? Visibility.Collapsed : Visibility.Visible;

        public bool HasCustomName => !string.IsNullOrEmpty(CustomName);
        public Visibility CustomNameVisibility => HasCustomName ? Visibility.Visible : Visibility.Collapsed;
        public Visibility NoCustomNameVisibility => HasCustomName ? Visibility.Collapsed : Visibility.Visible;

        public void RefreshComputedProperties()
        {
            OnPropertyChanged(nameof(HasCustomName));
            OnPropertyChanged(nameof(CustomNameVisibility));
            OnPropertyChanged(nameof(NoCustomNameVisibility));
        }

        public string IconGlyph => AccountType.ToLowerInvariant() switch
        {
            "google" => "\uEC1F", // brand-google
            "yahoo" => "\uED73",  // brand-yahoo
            _ => "\uECD8"         // brand-windows
        };

        public Microsoft.UI.Xaml.Media.Brush ColorBrush => GetSolidBrush(Color);

        private static SolidColorBrush GetSolidBrush(string hex)
        {
            try
            {
                hex = hex.Replace("#", "");
                byte a = 255;
                byte r = 255;
                byte g = 255;
                byte b = 255;
                if (hex.Length == 8)
                {
                    a = Convert.ToByte(hex.Substring(0, 2), 16);
                    r = Convert.ToByte(hex.Substring(2, 2), 16);
                    g = Convert.ToByte(hex.Substring(4, 2), 16);
                    b = Convert.ToByte(hex.Substring(6, 2), 16);
                }
                else if (hex.Length == 6)
                {
                    r = Convert.ToByte(hex.Substring(0, 2), 16);
                    g = Convert.ToByte(hex.Substring(2, 2), 16);
                    b = Convert.ToByte(hex.Substring(4, 2), 16);
                }
                return new SolidColorBrush(Windows.UI.Color.FromArgb(a, r, g, b));
            }
            catch
            {
                return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected void OnPropertyChanged([CallerMemberName] string? name = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    public class CalendarAppointment
    {
        public string Id { get; set; } = string.Empty;
        public string Subject { get; set; } = string.Empty;
        public DateTime StartTime { get; set; }
        public DateTime EndTime { get; set; }
        public Microsoft.UI.Xaml.Media.Brush AppointmentBackground { get; set; } = new SolidColorBrush(Microsoft.UI.Colors.Blue);
        public bool IsAllDay { get; set; }
        public string Notes { get; set; } = string.Empty;
        public string Location { get; set; } = string.Empty;
        public bool IsTodo { get; set; }
        public bool IsCompleted { get; set; }
    }

    public sealed partial class CalendarDetailPage : Page, INotifyPropertyChanged
    {
        private readonly ICalendarService _calendarService;
        private readonly HttpClient _httpClient;
        private bool _isLoading;
        private bool _isInitialized = false;
        private bool _isUpdatingAccountsList = false;
        private DateTime _currentStartDate;
        private DateTime _currentEndDate;
        private Storyboard? _sidebarStoryboard;

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

        public bool IsLoading
        {
            get => _isLoading;
            set { _isLoading = value; OnPropertyChanged(); }
        }

        public ObservableCollection<DisplayAccount> Accounts { get; } = new();
        public ObservableCollection<CalendarAppointment> Appointments { get; } = new();

        public List<string> ColorPresets { get; } = new()
        {
            "#512BD4", // Purple
            "#0078D4", // Blue
            "#107C41", // Green
            "#D83B01", // Orange
            "#E81123", // Red
            "#FFB900", // Yellow
            "#00B7C3", // Teal
            "#D01B70", // Pink
            "#7F7DFF", // Lavender
            "#FF6B6B", // Coral
            "#00A389"  // Mint
        };

        public CalendarDetailPage()
        {
            this.InitializeComponent();
            _calendarService = App.Current.Services.GetRequiredService<ICalendarService>();
            _httpClient = App.Current.Services.GetRequiredService<HttpClient>();
            Accounts.CollectionChanged += Accounts_CollectionChanged;
            _isInitialized = true;
        }

        protected override async void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            _calendarService.OnCalendarDataChanged += OnCalendarDataChanged;

            var isOpened = LoadSidebarState();
            ToggleSidebarBtn.IsChecked = isOpened;
            if (isOpened)
            {
                if (SidebarContainer != null)
                {
                    SidebarContainer.Width = 360;
                    SidebarContainer.Opacity = 1.0;
                    SidebarContainer.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
                }
            }
            else
            {
                if (SidebarContainer != null)
                {
                    SidebarContainer.Width = 0;
                    SidebarContainer.Opacity = 0.0;
                    SidebarContainer.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
                }
            }

            // Restore Scheduler View Type
            var viewTypeStr = LoadSchedulerViewType();
            Scheduler.ViewType = viewTypeStr switch
            {
                "Day" => SchedulerViewType.Day,
                "Week" => SchedulerViewType.Week,
                "WorkWeek" => SchedulerViewType.WorkWeek,
                "Month" => SchedulerViewType.Month,
                _ => SchedulerViewType.Month
            };
            UpdateSwitcherButtonsVisuals(viewTypeStr);

            await LoadDataAsync();
        }

        protected override void OnNavigatedFrom(NavigationEventArgs e)
        {
            base.OnNavigatedFrom(e);
            _calendarService.OnCalendarDataChanged -= OnCalendarDataChanged;
        }

        private void OnCalendarDataChanged()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                await LoadDataAsync();
            });
        }

        public async Task RefreshFromTitleBarAsync()
        {
            await LoadDataAsync();
            await _calendarService.SyncAllCalendarsAsync();
        }

        private async Task LoadDataAsync()
        {
            IsLoading = true;
            try
            {
                // Load accounts
                var rawAccounts = await _calendarService.GetAccountsAsync();
                _isUpdatingAccountsList = true;
                try
                {
                    Accounts.Clear();
                    foreach (var ra in rawAccounts)
                    {
                        Accounts.Add(new DisplayAccount
                        {
                            Id = ra.Id,
                            Email = ra.Email,
                            AccountType = ra.AccountType,
                            Color = string.IsNullOrEmpty(ra.Color) ? "#512BD4" : ra.Color,
                            IsActive = ra.IsActive,
                            CustomName = ra.CustomName,
                            IdentifiedName = ra.IdentifiedName,
                            DisplayOrder = ra.DisplayOrder
                        });
                    }
                }
                finally
                {
                    _isUpdatingAccountsList = false;
                }

                // Load events (within range of scheduler, e.g. -60 days to +90 days)
                var start = DateTime.UtcNow.AddDays(-60);
                var end = DateTime.UtcNow.AddDays(90);
                var events = await _calendarService.GetCachedEventsAsync(start, end);
                var todos = await _calendarService.GetCachedTodosAsync();

                Appointments.Clear();

                // Map events
                foreach (var ev in events)
                {
                    Appointments.Add(new CalendarAppointment
                    {
                        Id = ev.Id,
                        Subject = ev.Title,
                        StartTime = ev.Start.ToLocalTime(),
                        EndTime = ev.End.ToLocalTime(),
                        AppointmentBackground = GetSolidBrush(ev.Color),
                        IsAllDay = ev.IsAllDay,
                        Notes = ev.Description,
                        Location = ev.Location,
                        IsTodo = false
                    });
                }

                // Map tasks as all-day items
                foreach (var td in todos)
                {
                    Appointments.Add(new CalendarAppointment
                    {
                        Id = td.Id,
                        Subject = $"{(td.IsCompleted ? "✓ " : "☐ ")}{td.Title}",
                        StartTime = (td.DueDate ?? DateTime.Today).Date,
                        EndTime = (td.DueDate ?? DateTime.Today).Date.AddHours(23).AddMinutes(59),
                        AppointmentBackground = GetSolidBrush(td.Color),
                        IsAllDay = true,
                        Notes = td.Notes + $"\nImportance: {td.Importance}",
                        IsTodo = true,
                        IsCompleted = td.IsCompleted
                    });
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarDetailPage] LoadDataAsync error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async void AccountActive_Toggled(object sender, RoutedEventArgs e)
        {
            if (IsLoading) return;
            if (sender is ToggleSwitch ts && ts.DataContext is DisplayAccount acc)
            {
                await _calendarService.ToggleAccountActiveAsync(acc.Id, ts.IsOn);
            }
        }

        private async void ColorPreset_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is DisplayAccount acc && btn.DataContext is string hexColor)
            {
                await _calendarService.UpdateAccountColorAsync(acc.Id, hexColor);
                await LoadDataAsync();
            }
        }

        private void EditAccount_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is DisplayAccount acc)
            {
                acc.IsEditing = true;
            }
        }

        private async void SaveCustomName_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is DisplayAccount acc)
            {
                var grid = FindParent<Grid>(btn);
                var textBox = grid?.Children.OfType<TextBox>().FirstOrDefault();
                if (textBox != null)
                {
                    acc.CustomName = textBox.Text.Trim();
                }
                await _calendarService.UpdateAccountCustomNameAsync(acc.Id, acc.CustomName);
                acc.IsEditing = false;
                acc.RefreshComputedProperties();
            }
        }

        private void CancelEdit_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is DisplayAccount acc)
            {
                acc.IsEditing = false;
            }
        }

        private async void CustomNameTextBox_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (sender is TextBox textBox && textBox.DataContext is DisplayAccount acc)
            {
                if (e.Key == Windows.System.VirtualKey.Enter)
                {
                    acc.CustomName = textBox.Text.Trim();
                    await _calendarService.UpdateAccountCustomNameAsync(acc.Id, acc.CustomName);
                    acc.IsEditing = false;
                    acc.RefreshComputedProperties();
                    e.Handled = true;
                }
                else if (e.Key == Windows.System.VirtualKey.Escape)
                {
                    acc.IsEditing = false;
                    e.Handled = true;
                }
            }
        }

        private static T? FindParent<T>(DependencyObject child) where T : DependencyObject
        {
            DependencyObject parentObject = VisualTreeHelper.GetParent(child);
            if (parentObject == null) return null;
            if (parentObject is T parent) return parent;
            return FindParent<T>(parentObject);
        }

        private async void DeleteAccount_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is DisplayAccount acc)
            {
                var dialog = new ContentDialog
                {
                    Title = "Disconnect Calendar",
                    Content = $"Are you sure you want to disconnect {acc.Email}?",
                    PrimaryButtonText = "Disconnect",
                    CloseButtonText = "Cancel",
                    DefaultButton = ContentDialogButton.Close,
                    XamlRoot = this.XamlRoot
                };

                var res = await dialog.ShowAsync();
                if (res == ContentDialogResult.Primary)
                {
                    await _calendarService.DeleteAccountAsync(acc.Id);
                    await LoadDataAsync();
                }
            }
        }

        private static int GetRandomUnusedPort()
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            var port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }

        private async void ConnectGoogle_Click(object sender, RoutedEventArgs e)
        {
            IsLoading = true;
            HttpListener? listener = null;
            try
            {
                var port = GetRandomUnusedPort();
                var redirectUri = $"http://localhost:{port}/";
                var state = Guid.NewGuid().ToString();

                listener = new HttpListener();
                listener.Prefixes.Add(redirectUri);
                listener.Start();

                var authUrl = $"https://accounts.google.com/o/oauth2/v2/auth?client_id={Secrets.WindowsClientId}&redirect_uri={Uri.EscapeDataString(redirectUri)}&response_type=code&scope={Uri.EscapeDataString("https://www.googleapis.com/auth/calendar.readonly")}&access_type=offline&prompt=select_account&state={state}";

                await Launcher.LaunchUriAsync(new Uri(authUrl));

                // Wait for OAuth callback (up to 2 minutes)
                var contextTask = listener.GetContextAsync();
                var completedTask = await Task.WhenAny(contextTask, Task.Delay(TimeSpan.FromMinutes(2)));

                if (completedTask == contextTask)
                {
                    var context = await contextTask;
                    var request = context.Request;
                    var code = request.QueryString["code"];

                    // Respond to user in browser
                    var response = context.Response;
                    string responseString = "<html><body style='font-family: sans-serif; text-align: center; padding-top: 50px;'><h1>Authentication Successful!</h1><p>You can close this window and return to Daily now.</p></body></html>";
                    var buffer = System.Text.Encoding.UTF8.GetBytes(responseString);
                    response.ContentLength64 = buffer.Length;
                    response.OutputStream.Write(buffer, 0, buffer.Length);
                    response.OutputStream.Close();
                    await Task.Delay(1000); // Give browser time to read response before closing socket

                    if (!string.IsNullOrEmpty(code))
                    {
                        // Exchange code
                        var content = new FormUrlEncodedContent(new[]
                        {
                            new KeyValuePair<string, string>("client_id", Secrets.WindowsClientId),
                            new KeyValuePair<string, string>("client_secret", Secrets.WindowsClientSecret),
                            new KeyValuePair<string, string>("code", code),
                            new KeyValuePair<string, string>("redirect_uri", redirectUri),
                            new KeyValuePair<string, string>("grant_type", "authorization_code")
                        });

                        var tokenResponse = await _httpClient.PostAsync("https://oauth2.googleapis.com/token", content);
                        if (tokenResponse.IsSuccessStatusCode)
                        {
                            var json = await tokenResponse.Content.ReadAsStringAsync();
                            using var doc = JsonDocument.Parse(json);
                            var root = doc.RootElement;
                            var accessToken = root.GetProperty("access_token").GetString() ?? "";
                            var refreshToken = root.GetProperty("refresh_token").GetString() ?? "";
                            var expiresIn = root.GetProperty("expires_in").GetInt32();

                            // Fetch calendar email (primary calendar metadata)
                            var calReq = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/calendar/v3/calendars/primary");
                            calReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                            var calResp = await _httpClient.SendAsync(calReq);
                            var email = "Google Calendar";

                            if (calResp.IsSuccessStatusCode)
                            {
                                var calJson = await calResp.Content.ReadAsStringAsync();
                                using var calDoc = JsonDocument.Parse(calJson);
                                email = calDoc.RootElement.GetProperty("id").GetString() ?? email;
                            }

                            // Encrypt and save
                            var userSession = App.SupabaseClient.Auth.CurrentSession;
                            var userId = userSession?.User?.Id ?? "local_user";

                            var encryptedAccessToken = EncryptionHelper.Encrypt(accessToken, userId);
                            var encryptedRefreshToken = EncryptionHelper.Encrypt(refreshToken, userId);

                            var account = new LocalCalendarAccount
                            {
                                Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                                UserId = userId,
                                Email = email,
                                AccountType = "Google",
                                AccessToken = encryptedAccessToken,
                                RefreshToken = encryptedRefreshToken,
                                TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn),
                                Color = "#0078D4",
                                IsActive = true,
                                UpdatedAt = DateTime.UtcNow
                            };

                            await _calendarService.AddAccountAsync(account);
                            await LoadDataAsync();
                        }
                        else
                        {
                            var errorDetails = await tokenResponse.Content.ReadAsStringAsync();
                            throw new Exception($"Failed to exchange token: {errorDetails}");
                        }
                    }
                }
                else
                {
                    throw new TimeoutException("OAuth callback timed out after 2 minutes.");
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[Google OAuth] Connection failed: {ex}");
                Console.WriteLine($"[Google OAuth] Connection failed: {ex}");
                ShowErrorDialog("Google OAuth Link Failed", ex.Message);
            }
            finally
            {
                IsLoading = false;
                try
                {
                    listener?.Close();
                }
                catch { }
            }
        }

        private async void ConnectMicrosoft_Click(object sender, RoutedEventArgs e)
        {
            IsLoading = true;
            try
            {
                var codeVerifier = GenerateCodeVerifier();
                var codeChallenge = GenerateCodeChallenge(codeVerifier);

                var authUrl = $"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id={Secrets.MicrosoftClientId}&response_type=code&redirect_uri={Uri.EscapeDataString("com.intellidream.daily.desktop://login-callback")}&response_mode=query&scope={Uri.EscapeDataString("offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Calendars.Read https://graph.microsoft.com/Tasks.Read")}&prompt=select_account&code_challenge={codeChallenge}&code_challenge_method=S256";

                WinUIAuthService.OAuthCallbackTcs = new TaskCompletionSource<string>();
                await Launcher.LaunchUriAsync(new Uri(authUrl));

                var completedTask = await Task.WhenAny(WinUIAuthService.OAuthCallbackTcs.Task, Task.Delay(TimeSpan.FromMinutes(2)));
                if (completedTask == WinUIAuthService.OAuthCallbackTcs.Task)
                {
                    var code = await WinUIAuthService.OAuthCallbackTcs.Task;

                    // Exchange code
                    var content = new FormUrlEncodedContent(new[]
                    {
                        new KeyValuePair<string, string>("client_id", Secrets.MicrosoftClientId),
                        new KeyValuePair<string, string>("code", code),
                        new KeyValuePair<string, string>("redirect_uri", "com.intellidream.daily.desktop://login-callback"),
                        new KeyValuePair<string, string>("grant_type", "authorization_code"),
                        new KeyValuePair<string, string>("code_verifier", codeVerifier)
                    });

                    var response = await _httpClient.PostAsync("https://login.microsoftonline.com/common/oauth2/v2.0/token", content);
                    if (response.IsSuccessStatusCode)
                    {
                        var json = await response.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        var root = doc.RootElement;
                        var accessToken = root.GetProperty("access_token").GetString() ?? "";
                        var refreshToken = root.GetProperty("refresh_token").GetString() ?? "";
                        var expiresIn = root.GetProperty("expires_in").GetInt32();

                        // Fetch Microsoft user info
                        var meReq = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me");
                        meReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                        var meResp = await _httpClient.SendAsync(meReq);
                        var email = "Outlook Calendar";
                        var accountType = "MicrosoftPersonal";                        if (meResp.IsSuccessStatusCode)
                        {
                            var meJson = await meResp.Content.ReadAsStringAsync();
                            using var meDoc = JsonDocument.Parse(meJson);
                            var meRoot = meDoc.RootElement;
                            
                            email = meRoot.TryGetProperty("mail", out var m) ? m.GetString() ?? email : email;
                            if (email == "Outlook Calendar" && meRoot.TryGetProperty("userPrincipalName", out var upn))
                            {
                                email = upn.GetString() ?? email;
                            }
                        }

                        // Fallback/Verify via primary calendar owner address (under Calendars.Read scope)
                        if (email == "Outlook Calendar" || string.IsNullOrEmpty(email))
                        {
                            try
                            {
                                var calReq = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me/calendar");
                                calReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                                var calResp = await _httpClient.SendAsync(calReq);
                                if (calResp.IsSuccessStatusCode)
                                {
                                    var calJson = await calResp.Content.ReadAsStringAsync();
                                    using var calDoc = JsonDocument.Parse(calJson);
                                    if (calDoc.RootElement.TryGetProperty("owner", out var owner) && 
                                        owner.TryGetProperty("address", out var addr))
                                    {
                                        email = addr.GetString() ?? email;
                                    }
                                }
                            }
                            catch { }
                        }

                        // Determine tenant/type
                        if (email != "Outlook Calendar" && !string.IsNullOrEmpty(email))
                        {
                            if (email.EndsWith(".onmicrosoft.com") || (!email.EndsWith("@outlook.com") && !email.EndsWith("@hotmail.com") && !email.EndsWith("@live.com")))
                            {
                                accountType = "MicrosoftWork";
                            }
                        }

                        // Encrypt and save
                        var userSession = App.SupabaseClient.Auth.CurrentSession;
                        var userId = userSession?.User?.Id ?? "local_user";

                        var encryptedAccessToken = EncryptionHelper.Encrypt(accessToken, userId);
                        var encryptedRefreshToken = EncryptionHelper.Encrypt(refreshToken, userId);

                        var account = new LocalCalendarAccount
                        {
                            Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                            UserId = userId,
                            Email = email,
                            AccountType = accountType,
                            AccessToken = encryptedAccessToken,
                            RefreshToken = encryptedRefreshToken,
                            TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn),
                            Color = "#107C41",
                            IsActive = true,
                            UpdatedAt = DateTime.UtcNow
                        };

                        await _calendarService.AddAccountAsync(account);
                        await LoadDataAsync();
                    }
                }
            }
            catch (Exception ex)
            {
                ShowErrorDialog("Microsoft Link Failed", ex.Message);
            }
            finally
            {
                IsLoading = false;
                WinUIAuthService.OAuthCallbackTcs = null;
            }
        }

        private static string GenerateCodeVerifier()
        {
            var bytes = new byte[32];
            using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
            {
                rng.GetBytes(bytes);
            }
            return Base64UrlEncode(bytes);
        }

        private static string GenerateCodeChallenge(string codeVerifier)
        {
            using (var sha256 = System.Security.Cryptography.SHA256.Create())
            {
                var bytes = System.Text.Encoding.UTF8.GetBytes(codeVerifier);
                var hash = sha256.ComputeHash(bytes);
                return Base64UrlEncode(hash);
            }
        }

        private static string Base64UrlEncode(byte[] bytes)
        {
            return Convert.ToBase64String(bytes)
                .Replace("+", "-")
                .Replace("/", "_")
                .TrimEnd('=');
        }

        private async void ConnectYahoo_Click(object sender, RoutedEventArgs e)
        {
            var pivot = new Pivot { Width = 360 };

            // Tab 1: App Password
            var appPasswordPanel = new StackPanel { Spacing = 8, Margin = new Thickness(0, 10, 0, 0) };
            appPasswordPanel.Children.Add(new TextBlock
            {
                Text = "To connect, please generate a 16-character App Password on your Yahoo Account Security page.",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 13
            });

            var linkBtn = new HyperlinkButton
            {
                Content = "Open Yahoo Account Security Settings",
                NavigateUri = new Uri("https://login.yahoo.com/account/security"),
                Padding = new Thickness(0),
                Margin = new Thickness(0, 0, 0, 8),
                FontSize = 12
            };
            appPasswordPanel.Children.Add(linkBtn);

            var appEmailInput = new TextBox { PlaceholderText = "Yahoo Email Address", Header = "Email Address", Margin = new Thickness(0, 0, 0, 4) };
            var appPasswordInput = new PasswordBox { PlaceholderText = "16-character App Password", Header = "Yahoo App Password" };
            appPasswordPanel.Children.Add(appEmailInput);
            appPasswordPanel.Children.Add(appPasswordInput);

            var item1 = new PivotItem { Header = "App Password", Content = appPasswordPanel };
            pivot.Items.Add(item1);

            // Tab 2: Developer OAuth
            var oauthPanel = new StackPanel { Spacing = 8, Margin = new Thickness(0, 10, 0, 0) };
            TextBox urlInputRef = null;

            if (string.IsNullOrEmpty(Secrets.YahooClientId) || string.IsNullOrEmpty(Secrets.YahooClientSecret))
            {
                oauthPanel.Children.Add(new TextBlock
                {
                    Text = "Yahoo Developer Credentials Required",
                    FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                    FontSize = 14,
                    Margin = new Thickness(0, 0, 0, 4)
                });
                oauthPanel.Children.Add(new TextBlock
                {
                    Text = "Please register an Installed Application on developer.yahoo.com, set Redirect URI to https://localhost:50389/, select Calendar Read/Write and OpenID permissions, then update Secrets.cs.",
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 12,
                    Opacity = 0.8
                });
            }
            else
            {
                oauthPanel.Children.Add(new TextBlock
                {
                    Text = "Click the button below to authorize Daily in your browser, then copy and paste the redirected URL below.",
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 13
                });

                var state = Guid.NewGuid().ToString();
                var redirectUri = string.IsNullOrEmpty(Secrets.YahooRedirectUri) ? "https://localhost:50389/" : Secrets.YahooRedirectUri;
                var authUrl = $"https://api.login.yahoo.com/oauth2/request_auth?client_id={Secrets.YahooClientId}&redirect_uri={Uri.EscapeDataString(redirectUri)}&response_type=code&scope={Uri.EscapeDataString("openid email ycal-r ycal-w")}&state={state}";

                var authButton = new Button
                {
                    Content = "Open Browser to Authorize",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    Style = (Style)Application.Current.Resources["AccentButtonStyle"]
                };
                authButton.Click += async (s, args) =>
                {
                    await Launcher.LaunchUriAsync(new Uri(authUrl));
                };
                oauthPanel.Children.Add(authButton);

                urlInputRef = new TextBox
                {
                    PlaceholderText = "Paste the redirect URL here...",
                    Header = "Redirect URL",
                    TextWrapping = TextWrapping.Wrap
                };
                oauthPanel.Children.Add(urlInputRef);
            }

            var item2 = new PivotItem { Header = "Developer OAuth", Content = oauthPanel };
            pivot.Items.Add(item2);

            var dialog = new ContentDialog
            {
                Title = "Connect Yahoo Calendar",
                Content = pivot,
                PrimaryButtonText = "Connect",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                XamlRoot = this.XamlRoot
            };

            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary)
            {
                var selectedItem = pivot.SelectedItem as PivotItem;
                if (selectedItem?.Header?.ToString() == "App Password")
                {
                    var email = appEmailInput.Text.Trim();
                    var password = appPasswordInput.Password.Trim();

                    if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password))
                    {
                        ShowErrorDialog("Yahoo Link Failed", "Email and app password are required.");
                        return;
                    }

                    IsLoading = true;
                    try
                    {
                        // Validate Yahoo CalDAV connection with a quick query
                        var baseAddress = "https://caldav.calendar.yahoo.com";
                        var propfindXml = @"<d:propfind xmlns:d=""DAV:""><d:prop></d:prop></d:propfind>";
                        var propRequest = new HttpRequestMessage(new HttpMethod("PROPFIND"), $"{baseAddress}/dav/{email}/Calendar");
                        propRequest.Headers.TryAddWithoutValidation("Depth", "1");
                        
                        var authBytes = Encoding.UTF8.GetBytes($"{email}:{password}");
                        propRequest.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
                        propRequest.Content = new StringContent(propfindXml, Encoding.UTF8, "text/xml");

                        var response = await _httpClient.SendAsync(propRequest);
                        if (response.IsSuccessStatusCode)
                        {
                            var userSession = App.SupabaseClient.Auth.CurrentSession;
                            var userId = userSession?.User?.Id ?? "local_user";

                            // Encrypt password (stored in AccessToken, RefreshToken is empty)
                            var encryptedPassword = EncryptionHelper.Encrypt(password, userId);

                            var account = new LocalCalendarAccount
                            {
                                Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                                UserId = userId,
                                Email = email,
                                AccountType = "Yahoo",
                                AccessToken = encryptedPassword,
                                RefreshToken = string.Empty,
                                TokenExpiresAt = DateTime.MaxValue,
                                Color = "#6001d2", // Yahoo Purple
                                IsActive = true,
                                UpdatedAt = DateTime.UtcNow
                            };

                            await _calendarService.AddAccountAsync(account);
                            await LoadDataAsync();
                        }
                        else
                        {
                            ShowErrorDialog("Yahoo Link Failed", $"CalDAV server returned HTTP {response.StatusCode}. Please verify your email and App Password.");
                        }
                    }
                    catch (Exception ex)
                    {
                        ShowErrorDialog("Yahoo Link Failed", ex.Message);
                    }
                    finally
                    {
                        IsLoading = false;
                    }
                }
                else // Developer OAuth
                {
                    if (urlInputRef == null)
                    {
                        ShowErrorDialog("Yahoo Link Failed", "Developer credentials not configured.");
                        return;
                    }

                    var pastedText = urlInputRef.Text.Trim();
                    if (string.IsNullOrEmpty(pastedText))
                    {
                        ShowErrorDialog("Yahoo Link Failed", "Redirect URL or code is required.");
                        return;
                    }

                    string code = pastedText;
                    if (pastedText.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            var uri = new Uri(pastedText);
                            var query = uri.Query.TrimStart('?');
                            var parts = query.Split('&');
                            foreach (var part in parts)
                            {
                                var kv = part.Split('=');
                                if (kv.Length == 2 && kv[0] == "code")
                                {
                                    code = Uri.UnescapeDataString(kv[1]);
                                    break;
                                }
                            }
                        }
                        catch (Exception ex)
                        {
                            ShowErrorDialog("Yahoo Link Failed", "Could not parse code from the pasted URL: " + ex.Message);
                            return;
                        }
                    }

                    IsLoading = true;
                    try
                    {
                        var redirectUri = string.IsNullOrEmpty(Secrets.YahooRedirectUri) ? "https://localhost:50389/" : Secrets.YahooRedirectUri;
                        var content = new FormUrlEncodedContent(new[]
                        {
                            new KeyValuePair<string, string>("client_id", Secrets.YahooClientId),
                            new KeyValuePair<string, string>("client_secret", Secrets.YahooClientSecret),
                            new KeyValuePair<string, string>("code", code),
                            new KeyValuePair<string, string>("redirect_uri", redirectUri),
                            new KeyValuePair<string, string>("grant_type", "authorization_code")
                        });

                        var request = new HttpRequestMessage(HttpMethod.Post, "https://api.login.yahoo.com/oauth2/get_token");
                        request.Content = content;

                        var authBytes = Encoding.UTF8.GetBytes($"{Secrets.YahooClientId}:{Secrets.YahooClientSecret}");
                        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));

                        var response = await _httpClient.SendAsync(request);
                        if (!response.IsSuccessStatusCode)
                        {
                            var errorBody = await response.Content.ReadAsStringAsync();
                            throw new Exception($"Failed to exchange token. HTTP {response.StatusCode}: {errorBody}");
                        }

                        var json = await response.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        var root = doc.RootElement;
                        var accessToken = root.GetProperty("access_token").GetString() ?? "";
                        var refreshToken = root.GetProperty("refresh_token").GetString() ?? "";
                        var expiresIn = root.GetProperty("expires_in").GetInt32();

                        var infoReq = new HttpRequestMessage(HttpMethod.Get, "https://api.login.yahoo.com/openid/v1/userinfo");
                        infoReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                        var infoResp = await _httpClient.SendAsync(infoReq);
                        var email = "Yahoo Calendar";

                        if (infoResp.IsSuccessStatusCode)
                        {
                            var infoJson = await infoResp.Content.ReadAsStringAsync();
                            using var infoDoc = JsonDocument.Parse(infoJson);
                            var infoRoot = infoDoc.RootElement;
                            if (infoRoot.TryGetProperty("email", out var emailProp))
                            {
                                email = emailProp.GetString() ?? email;
                            }
                        }

                        var userSession = App.SupabaseClient.Auth.CurrentSession;
                        var userId = userSession?.User?.Id ?? "local_user";

                        var encryptedAccessToken = EncryptionHelper.Encrypt(accessToken, userId);
                        var encryptedRefreshToken = EncryptionHelper.Encrypt(refreshToken, userId);

                        var account = new LocalCalendarAccount
                        {
                            Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                            UserId = userId,
                            Email = email,
                            AccountType = "Yahoo",
                            AccessToken = encryptedAccessToken,
                            RefreshToken = encryptedRefreshToken,
                            TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn),
                            Color = "#6001d2",
                            IsActive = true,
                            UpdatedAt = DateTime.UtcNow
                        };

                        await _calendarService.AddAccountAsync(account);
                        await LoadDataAsync();
                    }
                    catch (Exception ex)
                    {
                        ShowErrorDialog("Yahoo Link Failed", ex.Message);
                    }
                    finally
                    {
                        IsLoading = false;
                    }
                }
            }
        }

        private async void ShowErrorDialog(string title, string message)
        {
            var dialog = new ContentDialog
            {
                Title = title,
                Content = message,
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }

        private static SolidColorBrush GetSolidBrush(string hex)
        {
            try
            {
                hex = hex.Replace("#", "");
                byte a = 255;
                uint rgba = Convert.ToUInt32(hex, 16);
                if (hex.Length == 8)
                {
                    return new SolidColorBrush(Windows.UI.Color.FromArgb((byte)((rgba >> 24) & 0xFF), (byte)((rgba >> 16) & 0xFF), (byte)((rgba >> 8) & 0xFF), (byte)(rgba & 0xFF)));
                }
                else
                {
                    return new SolidColorBrush(Windows.UI.Color.FromArgb(255, (byte)((rgba >> 16) & 0xFF), (byte)((rgba >> 8) & 0xFF), (byte)(rgba & 0xFF)));
                }
            }
            catch
            {
                return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            }
        }

        private void SaveSidebarState(bool isOpened)
        {
            if (!_isInitialized) return; // Guard against events fired during XAML initialization
            
            try
            {
                var localSettings = Windows.Storage.ApplicationData.Current.LocalSettings;
                localSettings.Values["CalendarSidebarState"] = isOpened ? "open" : "closed";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarDetailPage] SaveSidebarState error: {ex.Message}");
                // Fallback to text file
                try
                {
                    var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                    Directory.CreateDirectory(appDataPath);
                    var file = Path.Combine(appDataPath, "CalendarSidebarState.txt");
                    File.WriteAllText(file, isOpened ? "open" : "closed");
                }
                catch { }
            }
        }

        private bool LoadSidebarState()
        {
            try
            {
                var localSettings = Windows.Storage.ApplicationData.Current.LocalSettings;
                if (localSettings.Values.TryGetValue("CalendarSidebarState", out var val) && val is string state)
                {
                    return state == "open";
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarDetailPage] LoadSidebarState error: {ex.Message}");
            }

            // Fallback to text file
            try
            {
                var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                var file = Path.Combine(appDataPath, "CalendarSidebarState.txt");
                if (File.Exists(file))
                {
                    var txt = File.ReadAllText(file).Trim().ToLowerInvariant();
                    return txt == "open";
                }
            }
            catch { }

            return true; // default value
        }

        private void AnimateSidebar(bool open)
        {
            if (SidebarContainer == null) return;

            // Capture current states before stopping any active animation to prevent reversion
            double startWidth = open ? 0 : 360;
            double startOpacity = open ? 0.0 : 1.0;

            if (SidebarContainer.Visibility == Visibility.Visible)
            {
                startWidth = SidebarContainer.ActualWidth;
                startOpacity = SidebarContainer.Opacity;
            }

            if (_sidebarStoryboard != null)
            {
                _sidebarStoryboard.Stop();
            }

            _sidebarStoryboard = new Storyboard();

            var widthAnimation = new DoubleAnimation();
            widthAnimation.Duration = new Duration(TimeSpan.FromMilliseconds(250));
            widthAnimation.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut };
            Storyboard.SetTarget(widthAnimation, SidebarContainer);
            Storyboard.SetTargetProperty(widthAnimation, "Width");

            var opacityAnimation = new DoubleAnimation();
            opacityAnimation.Duration = new Duration(TimeSpan.FromMilliseconds(200));
            opacityAnimation.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut };
            Storyboard.SetTarget(opacityAnimation, SidebarContainer);
            Storyboard.SetTargetProperty(opacityAnimation, "Opacity");

            if (open)
            {
                SidebarContainer.Visibility = Visibility.Visible;
                widthAnimation.From = startWidth;
                widthAnimation.To = 360;

                opacityAnimation.From = startOpacity;
                opacityAnimation.To = 1.0;

                _sidebarStoryboard.Children.Add(widthAnimation);
                _sidebarStoryboard.Children.Add(opacityAnimation);
                _sidebarStoryboard.Begin();
            }
            else
            {
                widthAnimation.From = startWidth;
                widthAnimation.To = 0;

                opacityAnimation.From = startOpacity;
                opacityAnimation.To = 0.0;

                _sidebarStoryboard.Children.Add(widthAnimation);
                _sidebarStoryboard.Children.Add(opacityAnimation);

                _sidebarStoryboard.Completed += (s, ev) =>
                {
                    if (!open)
                    {
                        SidebarContainer.Visibility = Visibility.Collapsed;
                    }
                };
                _sidebarStoryboard.Begin();
            }
        }

        private void ToggleSidebar_Checked(object sender, RoutedEventArgs e)
        {
            AnimateSidebar(true);
            SaveSidebarState(true);
        }

        private void ToggleSidebar_Unchecked(object sender, RoutedEventArgs e)
        {
            AnimateSidebar(false);
            SaveSidebarState(false);
        }

        private async void Accounts_DragItemsCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
        {
            var accountIds = Accounts.Select(x => x.Id).ToList();
            await _calendarService.UpdateAccountsOrderAsync(accountIds);
        }

        private async void Accounts_CollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
        {
            if (_isUpdatingAccountsList) return;
            var accountIds = Accounts.Select(x => x.Id).ToList();
            await _calendarService.UpdateAccountsOrderAsync(accountIds);
        }

        private void Today_Click(object sender, RoutedEventArgs e)
        {
            Scheduler.DisplayDate = DateTime.Today;
        }

        private void Prev_Click(object sender, RoutedEventArgs e)
        {
            Scheduler.Backward();
        }

        private void Next_Click(object sender, RoutedEventArgs e)
        {
            Scheduler.Forward();
        }

        private void Scheduler_ViewChanged(object sender, ViewChangedEventArgs e)
        {
            UpdateDateText(e.NewValue.ActualStartDate, e.NewValue.ActualEndDate);
        }

        private void UpdateDateText(DateTime start, DateTime end)
        {
            _currentStartDate = start;
            _currentEndDate = end;

            if (SchedulerDateText == null) return;

            double availableWidth = this.ActualWidth;
            if (ToggleSidebarBtn != null && ToggleSidebarBtn.IsChecked == true)
            {
                availableWidth -= 360;
            }
            bool isSmall = availableWidth < 700;

            if (Scheduler.ViewType == SchedulerViewType.Month)
            {
                var midDate = start.AddDays((end - start).Days / 2);
                SchedulerDateText.Text = isSmall ? midDate.ToString("MMM yyyy") : midDate.ToString("MMMM yyyy");
            }
            else if (Scheduler.ViewType == SchedulerViewType.Day)
            {
                SchedulerDateText.Text = isSmall ? Scheduler.DisplayDate.ToString("MMM dd, yy") : Scheduler.DisplayDate.ToString("MMMM dd, yyyy");
            }
            else // Week, WorkWeek
            {
                if (isSmall)
                {
                    if (start.Year != end.Year)
                    {
                        SchedulerDateText.Text = $"{start:MM/dd/yy} - {end:MM/dd/yy}";
                    }
                    else if (start.Month != end.Month)
                    {
                        SchedulerDateText.Text = $"{start:MMM dd} - {end:MMM dd}";
                    }
                    else
                    {
                        SchedulerDateText.Text = $"{start:MMM dd} - {end:dd}";
                    }
                }
                else
                {
                    if (start.Year != end.Year)
                    {
                        SchedulerDateText.Text = $"{start:MMM dd, yyyy} - {end:MMM dd, yyyy}";
                    }
                    else if (start.Month != end.Month)
                    {
                        SchedulerDateText.Text = $"{start:MMM dd} - {end:MMM dd, yyyy}";
                    }
                    else
                    {
                        SchedulerDateText.Text = $"{start:MMM dd} - {end:dd, yyyy}";
                    }
                }
            }

            // Sync HeaderCalendarView date selection silently (prevent re-triggering loop)
            if (HeaderCalendarView != null)
            {
                HeaderCalendarView.SelectedDatesChanged -= HeaderCalendarView_SelectedDatesChanged;
                HeaderCalendarView.SelectedDates.Clear();
                HeaderCalendarView.SelectedDates.Add(Scheduler.DisplayDate);
                HeaderCalendarView.SelectedDatesChanged += HeaderCalendarView_SelectedDatesChanged;
            }
        }

        private void HeaderCalendarView_SelectedDatesChanged(CalendarView sender, CalendarViewSelectedDatesChangedEventArgs args)
        {
            if (args.AddedDates.Count > 0)
            {
                var selectedDate = args.AddedDates[0].DateTime;
                Scheduler.DisplayDate = selectedDate;
                if (CalendarFlyout != null)
                {
                    CalendarFlyout.Hide();
                }
            }
        }

        private void ViewSwitcher_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string viewTypeStr)
            {
                Scheduler.ViewType = viewTypeStr switch
                {
                    "Day" => SchedulerViewType.Day,
                    "Week" => SchedulerViewType.Week,
                    "WorkWeek" => SchedulerViewType.WorkWeek,
                    "Month" => SchedulerViewType.Month,
                    _ => SchedulerViewType.Month
                };
                UpdateSwitcherButtonsVisuals(viewTypeStr);
                SaveSchedulerViewType(viewTypeStr);
            }
        }

        private void SaveSchedulerViewType(string viewType)
        {
            try
            {
                var localSettings = Windows.Storage.ApplicationData.Current.LocalSettings;
                localSettings.Values["CalendarSchedulerViewType"] = viewType;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarDetailPage] SaveSchedulerViewType error: {ex.Message}");
                try
                {
                    var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                    Directory.CreateDirectory(appDataPath);
                    var file = Path.Combine(appDataPath, "CalendarSchedulerViewType.txt");
                    File.WriteAllText(file, viewType);
                }
                catch { }
            }
        }

        private string LoadSchedulerViewType()
        {
            try
            {
                var localSettings = Windows.Storage.ApplicationData.Current.LocalSettings;
                if (localSettings.Values.TryGetValue("CalendarSchedulerViewType", out var val) && val is string viewType)
                {
                    return viewType;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarDetailPage] LoadSchedulerViewType error: {ex.Message}");
            }

            try
            {
                var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                var file = Path.Combine(appDataPath, "CalendarSchedulerViewType.txt");
                if (File.Exists(file))
                {
                    return File.ReadAllText(file).Trim();
                }
            }
            catch { }

            return "Month"; // Default
        }

        private void UpdateSwitcherButtonsVisuals(string selectedViewType)
        {
            if (DayViewBtn == null || WeekViewBtn == null || WorkWeekViewBtn == null || MonthViewBtn == null) return;

            // Clear active state of all buttons (make them transparent and muted text)
            DayViewBtn.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            WeekViewBtn.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            WorkWeekViewBtn.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            MonthViewBtn.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);

            var fgMutedBrush = Application.Current.Resources.TryGetValue("AppFgMutedColorBrush", out var fmb) ? fmb as Brush : null;
            var fgBrush = Application.Current.Resources.TryGetValue("AppFgColorBrush", out var fb) ? fb as Brush : null;
            var activeBgBrush = Application.Current.Resources.TryGetValue("AppGlassColorBrush", out var gb) ? gb as Brush : null;

            DayViewBtn.Foreground = fgMutedBrush;
            WeekViewBtn.Foreground = fgMutedBrush;
            WorkWeekViewBtn.Foreground = fgMutedBrush;
            MonthViewBtn.Foreground = fgMutedBrush;

            // Highlight the active button
            Button? activeBtn = selectedViewType switch
            {
                "Day" => DayViewBtn,
                "Week" => WeekViewBtn,
                "WorkWeek" => WorkWeekViewBtn,
                "Month" => MonthViewBtn,
                _ => MonthViewBtn
            };

            if (activeBtn != null)
            {
                activeBtn.Background = activeBgBrush;
                activeBtn.Foreground = fgBrush;
            }
        }



        private async void Scheduler_AppointmentTapped(object sender, AppointmentTappedArgs e)
        {
            if (e.Appointment != null && e.Appointment.Data is CalendarAppointment appt && appt.IsTodo)
            {
                var dialog = new ContentDialog
                {
                    Title = appt.Subject.Replace("✓ ", "").Replace("☐ ", ""),
                    Content = new TextBlock { Text = appt.Notes, TextWrapping = TextWrapping.Wrap },
                    PrimaryButtonText = appt.IsCompleted ? "Mark Incomplete" : "Complete Task",
                    CloseButtonText = "Close",
                    XamlRoot = this.XamlRoot
                };

                var res = await dialog.ShowAsync();
                if (res == ContentDialogResult.Primary)
                {
                    IsLoading = true;
                    await _calendarService.CompleteTodoAsync(appt.Id);
                    await LoadDataAsync();
                }
            }
            else if (e.Appointment != null && e.Appointment.Data is CalendarAppointment eventAppt)
            {
                var details = $"Time: {eventAppt.StartTime:g} - {eventAppt.EndTime:g}\n\nLocation: {(string.IsNullOrEmpty(eventAppt.Location) ? "None" : eventAppt.Location)}\n\nNotes: {eventAppt.Notes}";
                var dialog = new ContentDialog
                {
                    Title = eventAppt.Subject,
                    Content = new TextBlock { Text = details, TextWrapping = TextWrapping.Wrap },
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                await dialog.ShowAsync();
            }
        }

        private void Page_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            double width = e.NewSize.Width;

            // 1. Collapse connected accounts sidebar if expanded and resizing to small size (< 950px)
            if (width < 950 && ToggleSidebarBtn != null && ToggleSidebarBtn.IsChecked == true)
            {
                ToggleSidebarBtn.IsChecked = false;
            }

            // Calculate available width for the scheduler header
            double availableWidth = width;
            if (ToggleSidebarBtn != null && ToggleSidebarBtn.IsChecked == true)
            {
                availableWidth -= 360;
            }
            bool isSmall = availableWidth < 700;

            // 2. Update Today button content (icon vs text) and width
            if (TodayBtn != null && TodayText != null && TodayIcon != null)
            {
                if (isSmall)
                {
                    TodayText.Visibility = Visibility.Collapsed;
                    TodayIcon.Visibility = Visibility.Visible;
                    TodayBtn.Width = 32;
                    TodayBtn.Padding = new Thickness(0);
                }
                else
                {
                    TodayText.Visibility = Visibility.Visible;
                    TodayIcon.Visibility = Visibility.Collapsed;
                    TodayBtn.Width = double.NaN;
                    TodayBtn.Padding = new Thickness(16, 0, 16, 0);
                }
            }

            // 3. Adjust Spacing in left stack panel
            if (HeaderLeftStackPanel != null)
            {
                HeaderLeftStackPanel.Spacing = isSmall ? 8 : 16;
            }

            // 4. Update view switcher buttons (abbreviated text on small widths)
            if (DayViewBtn != null && WeekViewBtn != null && WorkWeekViewBtn != null && MonthViewBtn != null)
            {
                if (isSmall)
                {
                    DayViewBtn.Content = "D";
                    DayViewBtn.Padding = new Thickness(8, 0, 8, 0);
                    WeekViewBtn.Content = "W";
                    WeekViewBtn.Padding = new Thickness(8, 0, 8, 0);
                    WorkWeekViewBtn.Content = "Wk";
                    WorkWeekViewBtn.Padding = new Thickness(8, 0, 8, 0);
                    MonthViewBtn.Content = "M";
                    MonthViewBtn.Padding = new Thickness(8, 0, 8, 0);
                }
                else
                {
                    DayViewBtn.Content = "Day";
                    DayViewBtn.Padding = new Thickness(12, 0, 12, 0);
                    WeekViewBtn.Content = "Week";
                    WeekViewBtn.Padding = new Thickness(12, 0, 12, 0);
                    WorkWeekViewBtn.Content = "Work";
                    WorkWeekViewBtn.Padding = new Thickness(12, 0, 12, 0);
                    MonthViewBtn.Content = "Month";
                    MonthViewBtn.Padding = new Thickness(12, 0, 12, 0);
                }
            }

            // 5. Force re-formatting the date range text
            if (_currentStartDate != default && _currentEndDate != default)
            {
                UpdateDateText(_currentStartDate, _currentEndDate);
            }
        }
    }
}
