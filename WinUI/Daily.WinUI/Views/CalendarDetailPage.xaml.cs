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

        public string IconGlyph => AccountType.ToLowerInvariant() switch
        {
            "google" => "\xE8A9;", // People icon or custom
            "yahoo" => "\xE114;",  // Mail/alternate or custom
            _ => "\xE193;"         // Outlook/Microsoft logo glyph approximation
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
            "#FFB900"  // Yellow
        };

        public CalendarDetailPage()
        {
            this.InitializeComponent();
            _calendarService = App.Current.Services.GetRequiredService<ICalendarService>();
            _httpClient = App.Current.Services.GetRequiredService<HttpClient>();
        }

        protected override async void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            _calendarService.OnCalendarDataChanged += OnCalendarDataChanged;
            await LoadDataAsync();
            
            // Set current date on scheduler header
            UpdateSchedulerHeaderDate();
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
                Accounts.Clear();
                foreach (var ra in rawAccounts)
                {
                    Accounts.Add(new DisplayAccount
                    {
                        Id = ra.Id,
                        Email = ra.Email,
                        AccountType = ra.AccountType,
                        Color = string.IsNullOrEmpty(ra.Color) ? "#512BD4" : ra.Color,
                        IsActive = ra.IsActive
                    });
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

                var authUrl = $"https://accounts.google.com/o/oauth2/v2/auth?client_id={Secrets.WindowsClientId}&redirect_uri={Uri.EscapeDataString(redirectUri)}&response_type=code&scope={Uri.EscapeDataString("https://www.googleapis.com/auth/calendar.readonly")}&access_type=offline&prompt=consent&state={state}";

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
                var authUrl = $"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id={Secrets.MicrosoftClientId}&response_type=code&redirect_uri={Uri.EscapeDataString("com.intellidream.daily.desktop://login-callback")}&response_mode=query&scope={Uri.EscapeDataString("offline_access https://graph.microsoft.com/Calendars.Read https://graph.microsoft.com/Tasks.Read")}&prompt=consent";

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
                        new KeyValuePair<string, string>("grant_type", "authorization_code")
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
                        var accountType = "MicrosoftPersonal";

                        if (meResp.IsSuccessStatusCode)
                        {
                            var meJson = await meResp.Content.ReadAsStringAsync();
                            using var meDoc = JsonDocument.Parse(meJson);
                            var meRoot = meDoc.RootElement;
                            
                            email = meRoot.TryGetProperty("mail", out var m) ? m.GetString() ?? email : email;
                            if (email == "Outlook Calendar" && meRoot.TryGetProperty("userPrincipalName", out var upn))
                            {
                                email = upn.GetString() ?? email;
                            }

                            // Determine tenant/type
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

        private async void ConnectYahoo_Click(object sender, RoutedEventArgs e)
        {
            var emailInput = new TextBox { PlaceholderText = "Yahoo Email Address", Margin = new Thickness(0, 0, 0, 10) };
            var passwordInput = new PasswordBox { PlaceholderText = "Yahoo App Password" };

            var panel = new StackPanel();
            panel.Children.Add(new TextBlock { Text = "Please create and enter a Yahoo App Password (not your primary password) to link via CalDAV.", Margin = new Thickness(0, 0, 0, 12), FontSize = 12, Opacity = 0.8, TextWrapping = TextWrapping.Wrap });
            panel.Children.Add(emailInput);
            panel.Children.Add(passwordInput);

            var dialog = new ContentDialog
            {
                Title = "Connect Yahoo Calendar",
                Content = panel,
                PrimaryButtonText = "Connect",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                XamlRoot = this.XamlRoot
            };

            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary)
            {
                var email = emailInput.Text.Trim();
                var password = passwordInput.Password.Trim();

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
                            Color = "#512BD4",
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
                UpdateSchedulerHeaderDate();
            }
        }

        private void Prev_Click(object sender, RoutedEventArgs e)
        {
            Scheduler.Backward();
            UpdateSchedulerHeaderDate();
        }

        private void Next_Click(object sender, RoutedEventArgs e)
        {
            Scheduler.Forward();
            UpdateSchedulerHeaderDate();
        }

        private void Today_Click(object sender, RoutedEventArgs e)
        {
            Scheduler.DisplayDate = DateTime.Today;
            UpdateSchedulerHeaderDate();
        }

        private void Scheduler_ViewChanged(object sender, ViewChangedEventArgs e)
        {
            UpdateSchedulerHeaderDate();
        }

        private void UpdateSchedulerHeaderDate()
        {
            if (Scheduler == null || SchedulerDateHeader == null) return;
            
            var displayDate = Scheduler.DisplayDate;
            SchedulerDateHeader.Text = displayDate.ToString("MMMM yyyy");
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
    }
}
