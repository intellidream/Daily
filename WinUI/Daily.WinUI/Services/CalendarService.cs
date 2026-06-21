using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Daily.Configuration;
using Daily.Models;
using Daily.Services;
using Microsoft.UI.Xaml;

namespace Daily_WinUI.Services
{
    public class CalendarService : ICalendarService
    {
        private readonly IDatabaseService _databaseService;
        private readonly HttpClient _httpClient;
        
        public event Action? OnCalendarDataChanged;

        public CalendarService(IDatabaseService databaseService, HttpClient httpClient)
        {
            _databaseService = databaseService;
            _httpClient = httpClient;
        }

        public async Task<List<LocalCalendarAccount>> GetAccountsAsync()
        {
            await _databaseService.InitializeAsync();
            var allAccounts = await _databaseService.Connection.Table<LocalCalendarAccount>().OrderBy(x => x.DisplayOrder).ToListAsync();
            var accounts = allAccounts.Where(x => !x.IsDeleted).ToList();
            foreach (var account in accounts)
            {
                if (string.IsNullOrEmpty(account.IdentifiedName))
                {
                    account.IdentifiedName = DetermineIdentifiedName(account.Email, account.AccountType);
                    await _databaseService.Connection.UpdateAsync(account);
                }
            }
            return accounts;
        }

        public async Task AddAccountAsync(LocalCalendarAccount account)
        {
            await _databaseService.InitializeAsync();
            if (string.IsNullOrEmpty(account.IdentifiedName))
            {
                account.IdentifiedName = DetermineIdentifiedName(account.Email, account.AccountType);
            }
            var existing = await _databaseService.Connection.Table<LocalCalendarAccount>().ToListAsync();
            if (account.DisplayOrder == 0 && existing.Any())
            {
                account.DisplayOrder = existing.Max(x => x.DisplayOrder) + 1;
            }
            account.SyncedAt = null; // Mark dirty for Supabase sync
            await _databaseService.Connection.InsertOrReplaceAsync(account);
            OnCalendarDataChanged?.Invoke();
            _ = Task.Run(() => SyncAccountDataAsync(account));
        }

        public async Task DeleteAccountAsync(string id)
        {
            await _databaseService.InitializeAsync();
            
            // Delete account
            var account = await _databaseService.Connection.Table<LocalCalendarAccount>().Where(x => x.Id == id).FirstOrDefaultAsync();
            if (account != null)
            {
                account.IsDeleted = true;
                account.SyncedAt = null; // Mark dirty
                account.UpdatedAt = DateTime.UtcNow;
                await _databaseService.Connection.UpdateAsync(account);

                await _databaseService.Connection.Table<LocalCalendarEvent>().Where(x => x.AccountId == id).DeleteAsync();
                await _databaseService.Connection.Table<LocalCalendarTodo>().Where(x => x.AccountId == id).DeleteAsync();
                
                // Let SyncService handle pushing the IsDeleted flag to Supabase.
                
                OnCalendarDataChanged?.Invoke();
            }
        }

        public async Task ToggleAccountActiveAsync(string accountId, bool isActive)
        {
            await _databaseService.InitializeAsync();
            var account = await _databaseService.Connection.Table<LocalCalendarAccount>().Where(x => x.Id == accountId).FirstOrDefaultAsync();
            if (account != null)
            {
                if (account.IsActive == isActive) return; // Prevent loop/redundant updates if value hasn't changed
                
                account.IsActive = isActive;
                account.UpdatedAt = DateTime.UtcNow;
                account.SyncedAt = null;
                await _databaseService.Connection.UpdateAsync(account);
                OnCalendarDataChanged?.Invoke();
                if (isActive)
                {
                    _ = Task.Run(() => SyncAccountDataAsync(account));
                }
            }
        }

        public async Task UpdateAccountColorAsync(string accountId, string hexColor)
        {
            await _databaseService.InitializeAsync();
            var account = await _databaseService.Connection.Table<LocalCalendarAccount>().Where(x => x.Id == accountId).FirstOrDefaultAsync();
            if (account != null)
            {
                if (account.Color.Equals(hexColor, StringComparison.OrdinalIgnoreCase)) return; // Prevent redundant updates
                
                account.Color = hexColor;
                account.UpdatedAt = DateTime.UtcNow;
                account.SyncedAt = null;
                await _databaseService.Connection.UpdateAsync(account);
                
                // Update cached event/todo colors
                var events = await _databaseService.Connection.Table<LocalCalendarEvent>().Where(x => x.AccountId == accountId).ToListAsync();
                foreach (var ev in events)
                {
                    ev.Color = hexColor;
                    await _databaseService.Connection.UpdateAsync(ev);
                }
                var todos = await _databaseService.Connection.Table<LocalCalendarTodo>().Where(x => x.AccountId == accountId).ToListAsync();
                foreach (var td in todos)
                {
                    td.Color = hexColor;
                    await _databaseService.Connection.UpdateAsync(td);
                }

                OnCalendarDataChanged?.Invoke();
            }
        }

        public async Task<List<LocalCalendarEvent>> GetCachedEventsAsync(DateTime start, DateTime end)
        {
            await _databaseService.InitializeAsync();
            
            var activeAccounts = await _databaseService.Connection.Table<LocalCalendarAccount>()
                .Where(x => x.IsActive)
                .ToListAsync();
            var activeAccountIds = activeAccounts.Select(x => x.Id).ToList();

            if (activeAccountIds.Count == 0) return new List<LocalCalendarEvent>();

            // Query cached events within range for active accounts
            var events = await _databaseService.Connection.Table<LocalCalendarEvent>()
                .Where(x => x.Start <= end && x.End >= start)
                .ToListAsync();

            return events.FindAll(x => activeAccountIds.Contains(x.AccountId));
        }

        public async Task<List<LocalCalendarTodo>> GetCachedTodosAsync()
        {
            await _databaseService.InitializeAsync();
            
            var activeAccounts = await _databaseService.Connection.Table<LocalCalendarAccount>()
                .Where(x => x.IsActive)
                .ToListAsync();
            var activeAccountIds = activeAccounts.Select(x => x.Id).ToList();

            if (activeAccountIds.Count == 0) return new List<LocalCalendarTodo>();

            var todos = await _databaseService.Connection.Table<LocalCalendarTodo>().ToListAsync();
            return todos.FindAll(x => activeAccountIds.Contains(x.AccountId));
        }

        public async Task SyncAllCalendarsAsync()
        {
            var accounts = await GetAccountsAsync();
            var tasks = new List<Task>();
            foreach (var account in accounts)
            {
                if (account.IsActive)
                {
                    tasks.Add(SyncAccountDataAsync(account));
                }
            }
            await Task.WhenAll(tasks);
            OnCalendarDataChanged?.Invoke();
        }

        private async Task SyncAccountDataAsync(LocalCalendarAccount account)
        {
            try
            {
                // Ensure tokens are fresh
                await RefreshTokenIfNeededAsync(account);

                if (account.AccountType.Equals("Google", StringComparison.OrdinalIgnoreCase))
                {
                    await SyncGoogleCalendarAsync(account);
                }
                else if (account.AccountType.Equals("MicrosoftPersonal", StringComparison.OrdinalIgnoreCase) ||
                         account.AccountType.Equals("MicrosoftWork", StringComparison.OrdinalIgnoreCase))
                {
                    await SyncMicrosoftCalendarAndTodosAsync(account);
                }
                else if (account.AccountType.Equals("Yahoo", StringComparison.OrdinalIgnoreCase))
                {
                    await SyncYahooCalendarAsync(account);
                }
            }
            catch (Exception ex)
            {
                Log($"[CalendarService] Sync failed for account {account.Email}: {ex}");
            }
        }

        private async Task RefreshTokenIfNeededAsync(LocalCalendarAccount account)
        {
            // Yahoo uses App Passwords or OAuth. If App Password (no RefreshToken), skip refreshing.
            if (account.AccountType.Equals("Yahoo", StringComparison.OrdinalIgnoreCase) && string.IsNullOrEmpty(account.RefreshToken)) return;

            // Check expiry with a 5-minute buffer
            if (DateTime.UtcNow.AddMinutes(5) < account.TokenExpiresAt.ToUniversalTime()) return;

            Log($"[CalendarService] Refreshing token for {account.Email}...");

            if (account.AccountType.Equals("Google", StringComparison.OrdinalIgnoreCase))
            {
                var decryptedRefreshToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.RefreshToken, account.UserId);

                var content = new FormUrlEncodedContent(new[]
                {
                    new KeyValuePair<string, string>("client_id", Secrets.WindowsClientId),
                    new KeyValuePair<string, string>("client_secret", Secrets.WindowsClientSecret),
                    new KeyValuePair<string, string>("grant_type", "refresh_token"),
                    new KeyValuePair<string, string>("refresh_token", decryptedRefreshToken)
                });

                var response = await _httpClient.PostAsync("https://oauth2.googleapis.com/token", content);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    var root = doc.RootElement;
                    var accessToken = root.GetProperty("access_token").GetString() ?? string.Empty;
                    var expiresIn = root.GetProperty("expires_in").GetInt32();
                    
                    account.AccessToken = Daily.Services.Auth.EncryptionHelper.Encrypt(accessToken, account.UserId);
                    account.TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn);
                    
                    account.SyncedAt = null; // Mark dirty
                    await _databaseService.Connection.UpdateAsync(account);
                    Log($"[CalendarService] Google token refreshed successfully.");
                }
                else
                {
                    throw new Exception($"Google Token Refresh HTTP {response.StatusCode}");
                }
            }
            else if (account.AccountType.Equals("MicrosoftPersonal", StringComparison.OrdinalIgnoreCase) ||
                     account.AccountType.Equals("MicrosoftWork", StringComparison.OrdinalIgnoreCase))
            {
                var decryptedRefreshToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.RefreshToken, account.UserId);

                var content = new FormUrlEncodedContent(new[]
                {
                    new KeyValuePair<string, string>("client_id", Secrets.MicrosoftClientId),
                    new KeyValuePair<string, string>("grant_type", "refresh_token"),
                    new KeyValuePair<string, string>("refresh_token", decryptedRefreshToken),
                    new KeyValuePair<string, string>("redirect_uri", "com.intellidream.daily.desktop://login-callback")
                });

                var response = await _httpClient.PostAsync("https://login.microsoftonline.com/common/oauth2/v2.0/token", content);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    var root = doc.RootElement;
                    var accessToken = root.GetProperty("access_token").GetString() ?? string.Empty;
                    if (root.TryGetProperty("refresh_token", out var refToken))
                    {
                        var newRefreshToken = refToken.GetString() ?? string.Empty;
                        if (!string.IsNullOrEmpty(newRefreshToken))
                        {
                            account.RefreshToken = Daily.Services.Auth.EncryptionHelper.Encrypt(newRefreshToken, account.UserId);
                        }
                    }
                    account.AccessToken = Daily.Services.Auth.EncryptionHelper.Encrypt(accessToken, account.UserId);
                    var expiresIn = root.GetProperty("expires_in").GetInt32();
                    account.TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn);
                    
                    account.SyncedAt = null; // Mark dirty
                    await _databaseService.Connection.UpdateAsync(account);
                    Log($"[CalendarService] Microsoft token refreshed successfully.");
                }
                else
                {
                    throw new Exception($"Microsoft Token Refresh HTTP {response.StatusCode}");
                }
            }
            else if (account.AccountType.Equals("Yahoo", StringComparison.OrdinalIgnoreCase))
            {
                var decryptedRefreshToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.RefreshToken, account.UserId);
                var redirectUri = string.IsNullOrEmpty(Secrets.YahooRedirectUri) ? "https://localhost:50389/" : Secrets.YahooRedirectUri;

                var content = new FormUrlEncodedContent(new[]
                {
                    new KeyValuePair<string, string>("grant_type", "refresh_token"),
                    new KeyValuePair<string, string>("refresh_token", decryptedRefreshToken),
                    new KeyValuePair<string, string>("redirect_uri", redirectUri)
                });

                var request = new HttpRequestMessage(HttpMethod.Post, "https://api.login.yahoo.com/oauth2/get_token");
                request.Content = content;

                var authBytes = Encoding.UTF8.GetBytes($"{Secrets.YahooClientId}:{Secrets.YahooClientSecret}");
                request.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));

                var response = await _httpClient.SendAsync(request);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    var root = doc.RootElement;
                    var accessToken = root.GetProperty("access_token").GetString() ?? string.Empty;
                    if (root.TryGetProperty("refresh_token", out var refToken))
                    {
                        var newRefreshToken = refToken.GetString() ?? string.Empty;
                        if (!string.IsNullOrEmpty(newRefreshToken))
                        {
                            account.RefreshToken = Daily.Services.Auth.EncryptionHelper.Encrypt(newRefreshToken, account.UserId);
                        }
                    }
                    account.AccessToken = Daily.Services.Auth.EncryptionHelper.Encrypt(accessToken, account.UserId);
                    var expiresIn = root.GetProperty("expires_in").GetInt32();
                    account.TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn);
                    
                    account.SyncedAt = null; // Mark dirty
                    await _databaseService.Connection.UpdateAsync(account);
                    Log($"[CalendarService] Yahoo token refreshed successfully.");
                }
                else
                {
                    var errorDetails = await response.Content.ReadAsStringAsync();
                    throw new Exception($"Yahoo Token Refresh HTTP {response.StatusCode}: {errorDetails}");
                }
            }
        }

        private async Task SyncGoogleCalendarAsync(LocalCalendarAccount account)
        {
            var timeMin = DateTime.UtcNow.AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ");
            var timeMax = DateTime.UtcNow.AddDays(90).ToString("yyyy-MM-ddTHH:mm:ssZ");
            var url = $"https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin={Uri.EscapeDataString(timeMin)}&timeMax={Uri.EscapeDataString(timeMax)}&singleEvents=true";

            var decryptedAccessToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.AccessToken, account.UserId);

            var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);

            var response = await _httpClient.SendAsync(request);
            if (!response.IsSuccessStatusCode)
            {
                var errorBody = await response.Content.ReadAsStringAsync();
                throw new Exception($"Google Calendar Sync HTTP {response.StatusCode}: {errorBody}");
            }

            var json = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("items", out var items))
            {
                // Delete old local cached events for this account
                await _databaseService.Connection.Table<LocalCalendarEvent>()
                    .Where(x => x.AccountId == account.Id)
                    .DeleteAsync();

                foreach (var item in items.EnumerateArray())
                {
                    var evId = item.GetProperty("id").GetString() ?? Guid.NewGuid().ToString();
                    var title = item.TryGetProperty("summary", out var s) ? s.GetString() ?? "No Title" : "No Title";
                    var desc = item.TryGetProperty("description", out var d) ? d.GetString() ?? "" : "";
                    var location = item.TryGetProperty("location", out var l) ? l.GetString() ?? "" : "";

                    DateTime start = DateTime.UtcNow;
                    DateTime end = DateTime.UtcNow.AddHours(1);
                    bool isAllDay = false;

                    if (item.TryGetProperty("start", out var startEl))
                    {
                        if (startEl.TryGetProperty("dateTime", out var dt))
                        {
                            start = DateTime.Parse(dt.GetString()!).ToUniversalTime();
                        }
                        else if (startEl.TryGetProperty("date", out var dOnly))
                        {
                            start = DateTime.Parse(dOnly.GetString()!).ToUniversalTime();
                            isAllDay = true;
                        }
                    }

                    if (item.TryGetProperty("end", out var endEl))
                    {
                        if (endEl.TryGetProperty("dateTime", out var dt))
                        {
                            end = DateTime.Parse(dt.GetString()!).ToUniversalTime();
                        }
                        else if (endEl.TryGetProperty("date", out var dOnly))
                        {
                            end = DateTime.Parse(dOnly.GetString()!).ToUniversalTime();
                        }
                    }

                    var localEvent = new LocalCalendarEvent
                    {
                        Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                        AccountId = account.Id,
                        UserId = account.UserId,
                        ProviderEventId = evId,
                        Title = title,
                        Description = desc,
                        Start = start,
                        End = end,
                        IsAllDay = isAllDay,
                        Location = location,
                        Color = account.Color,
                        UpdatedAt = DateTime.UtcNow
                    };

                    await _databaseService.Connection.InsertAsync(localEvent);
                }
            }
        }

        private async Task SyncMicrosoftCalendarAndTodosAsync(LocalCalendarAccount account)
        {
            var decryptedAccessToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.AccessToken, account.UserId);

            // Self-healing: if email is generic, retrieve owner email from calendar metadata
            if (account.Email == "Outlook Calendar" || string.IsNullOrEmpty(account.Email))
            {
                try
                {
                    var calReq = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me/calendar");
                    calReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);
                    var calResp = await _httpClient.SendAsync(calReq);
                    if (calResp.IsSuccessStatusCode)
                    {
                        var calJson = await calResp.Content.ReadAsStringAsync();
                        using var calDoc = JsonDocument.Parse(calJson);
                        if (calDoc.RootElement.TryGetProperty("owner", out var owner) && 
                            owner.TryGetProperty("address", out var addr))
                        {
                            var realEmail = addr.GetString();
                            if (!string.IsNullOrEmpty(realEmail) && realEmail != "Outlook Calendar")
                            {
                                account.Email = realEmail;
                                account.IdentifiedName = DetermineIdentifiedName(realEmail, account.AccountType);
                                account.UpdatedAt = DateTime.UtcNow;
                                account.SyncedAt = null; // Mark dirty
                                await _databaseService.Connection.UpdateAsync(account);
                            }
                        }
                    }
                }
                catch { }
            }

            // 1. Sync Calendar View Events (expanded recurrence)
            var startStr = DateTime.UtcNow.AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ");
            var endStr = DateTime.UtcNow.AddDays(90).ToString("yyyy-MM-ddTHH:mm:ssZ");
            var url = $"https://graph.microsoft.com/v1.0/me/calendarView?startDateTime={Uri.EscapeDataString(startStr)}&endDateTime={Uri.EscapeDataString(endStr)}";

            var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);
            request.Headers.Add("Prefer", "outlook.timezone=\"UTC\"");

            var response = await _httpClient.SendAsync(request);
            if (response.IsSuccessStatusCode)
            {
                var json = await response.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(json);
                if (doc.RootElement.TryGetProperty("value", out var events))
                {
                    await _databaseService.Connection.Table<LocalCalendarEvent>()
                        .Where(x => x.AccountId == account.Id)
                        .DeleteAsync();

                    foreach (var ev in events.EnumerateArray())
                    {
                        var evId = ev.GetProperty("id").GetString() ?? Guid.NewGuid().ToString();
                        var title = ev.TryGetProperty("subject", out var s) ? s.GetString() ?? "No Title" : "No Title";
                        var desc = ev.TryGetProperty("bodyPreview", out var bp) ? bp.GetString() ?? "" : "";
                        
                        var locName = "";
                        if (ev.TryGetProperty("location", out var locObj))
                        {
                            locName = locObj.TryGetProperty("displayName", out var dn) ? dn.GetString() ?? "" : "";
                        }

                        DateTime start = DateTime.UtcNow;
                        DateTime end = DateTime.UtcNow.AddHours(1);
                        bool isAllDay = ev.TryGetProperty("isAllDay", out var ad) && ad.GetBoolean();

                        if (ev.TryGetProperty("start", out var startEl))
                        {
                            var dtStr = startEl.GetProperty("dateTime").GetString()!;
                            var zoneStr = startEl.GetProperty("timeZone").GetString()!;
                            
                            if (zoneStr.Equals("UTC", StringComparison.OrdinalIgnoreCase) || zoneStr.Equals("Coordinated Universal Time", StringComparison.OrdinalIgnoreCase))
                            {
                                start = DateTime.Parse(dtStr, null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal);
                            }
                            else
                            {
                                var tz = SafeFindTimeZone(zoneStr) ?? TimeZoneInfo.Local;
                                var dtNaive = DateTime.Parse(dtStr);
                                start = TimeZoneInfo.ConvertTimeToUtc(dtNaive, tz);
                            }
                        }

                        if (ev.TryGetProperty("end", out var endEl))
                        {
                            var dtStr = endEl.GetProperty("dateTime").GetString()!;
                            var zoneStr = endEl.GetProperty("timeZone").GetString()!;
                            
                            if (zoneStr.Equals("UTC", StringComparison.OrdinalIgnoreCase) || zoneStr.Equals("Coordinated Universal Time", StringComparison.OrdinalIgnoreCase))
                            {
                                end = DateTime.Parse(dtStr, null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal);
                            }
                            else
                            {
                                var tz = SafeFindTimeZone(zoneStr) ?? TimeZoneInfo.Local;
                                var dtNaive = DateTime.Parse(dtStr);
                                end = TimeZoneInfo.ConvertTimeToUtc(dtNaive, tz);
                            }
                        }

                        var localEvent = new LocalCalendarEvent
                        {
                            Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                            AccountId = account.Id,
                            UserId = account.UserId,
                            ProviderEventId = evId,
                            Title = title,
                            Description = desc,
                            Start = start,
                            End = end,
                            IsAllDay = isAllDay,
                            Location = locName,
                            Color = account.Color,
                            UpdatedAt = DateTime.UtcNow
                        };

                        await _databaseService.Connection.InsertAsync(localEvent);
                    }
                }
            }

            // 2. Sync ToDo Tasks
            var todoListUrl = "https://graph.microsoft.com/v1.0/me/todo/lists";
            var todoRequest = new HttpRequestMessage(HttpMethod.Get, todoListUrl);
            todoRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);

            var todoResponse = await _httpClient.SendAsync(todoRequest);
            if (todoResponse.IsSuccessStatusCode)
            {
                var json = await todoResponse.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(json);
                if (doc.RootElement.TryGetProperty("value", out var lists))
                {
                    // Clear old cached todos for this account
                    await _databaseService.Connection.Table<LocalCalendarTodo>()
                        .Where(x => x.AccountId == account.Id)
                        .DeleteAsync();

                    foreach (var list in lists.EnumerateArray())
                    {
                        var listId = list.GetProperty("id").GetString()!;
                        var tasksUrl = $"https://graph.microsoft.com/v1.0/me/todo/lists/{listId}/tasks";
                        
                        var taskReq = new HttpRequestMessage(HttpMethod.Get, tasksUrl);
                        taskReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);
                        var taskResp = await _httpClient.SendAsync(taskReq);

                        if (taskResp.IsSuccessStatusCode)
                        {
                            var taskJson = await taskResp.Content.ReadAsStringAsync();
                            using var taskDoc = JsonDocument.Parse(taskJson);
                            if (taskDoc.RootElement.TryGetProperty("value", out var tasks))
                            {
                                foreach (var task in tasks.EnumerateArray())
                                {
                                    var taskId = task.GetProperty("id").GetString()!;
                                    var title = task.GetProperty("title").GetString() ?? "Untitled Task";
                                    
                                    var bodyContent = "";
                                    if (task.TryGetProperty("body", out var bObj))
                                    {
                                        bodyContent = bObj.TryGetProperty("content", out var c) ? c.GetString() ?? "" : "";
                                    }

                                    DateTime? due = null;
                                    if (task.TryGetProperty("dueDateTime", out var dueObj))
                                    {
                                        var dtStr = dueObj.GetProperty("dateTime").GetString()!;
                                        due = DateTime.Parse(dtStr).ToUniversalTime();
                                    }

                                    var status = task.GetProperty("status").GetString() ?? "notStarted";
                                    bool isCompleted = status.Equals("completed", StringComparison.OrdinalIgnoreCase);

                                    DateTime? completedDate = null;
                                    if (task.TryGetProperty("completedDateTime", out var compObj))
                                    {
                                        var dtStr = compObj.GetProperty("dateTime").GetString()!;
                                        completedDate = DateTime.Parse(dtStr).ToUniversalTime();
                                    }

                                    var importance = task.TryGetProperty("importance", out var imp) ? imp.GetString() ?? "normal" : "normal";

                                    var localTodo = new LocalCalendarTodo
                                    {
                                        Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                                        AccountId = account.Id,
                                        UserId = account.UserId,
                                        ProviderTodoId = $"{listId}|{taskId}", // Store composite so we can mark completed in Microsoft ToDo
                                        Title = title,
                                        Notes = bodyContent,
                                        DueDate = due,
                                        CompletedDate = completedDate,
                                        IsCompleted = isCompleted,
                                        Importance = importance,
                                        Color = account.Color,
                                        UpdatedAt = DateTime.UtcNow
                                    };

                                    await _databaseService.Connection.InsertAsync(localTodo);
                                }
                            }
                        }
                    }
                }
            }
        }

        private async Task SyncYahooCalendarAsync(LocalCalendarAccount account)
        {
            // Simple CalDAV sync using username + App Password or OAuth Bearer token
            // Yahoo CalDAV URL: https://caldav.calendar.yahoo.com
            
            var user = account.Email;
            var decryptedToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.AccessToken, account.UserId);
            var isOAuth = !string.IsNullOrEmpty(account.RefreshToken);

            var baseAddress = "https://caldav.calendar.yahoo.com";
            
            void ApplyAuth(HttpRequestMessage request)
            {
                if (isOAuth)
                {
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedToken);
                }
                else
                {
                    var authBytes = Encoding.UTF8.GetBytes($"{user}:{decryptedToken}");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
                }
            }

            // Step 1: Query collection list to find calendar paths
            // We do a simple propfind request
            var propfindXml = @"<d:propfind xmlns:d=""DAV:"">
                <d:prop></d:prop>
            </d:propfind>";

            var propRequest = new HttpRequestMessage(new HttpMethod("PROPFIND"), $"{baseAddress}/dav/{user}/Calendar");
            propRequest.Headers.TryAddWithoutValidation("Depth", "1");
            ApplyAuth(propRequest);
            propRequest.Content = new StringContent(propfindXml, Encoding.UTF8, "text/xml");

            var propResponse = await _httpClient.SendAsync(propRequest);
            if (!propResponse.IsSuccessStatusCode)
            {
                throw new Exception($"Yahoo CalDAV collection query HTTP {propResponse.StatusCode}");
            }
            var propContent = await propResponse.Content.ReadAsStringAsync();
            Log($"[CalendarService] Yahoo PROPFIND response: {propContent}");

            // Extract all hrefs returned
            var calendarHrefs = new List<string>();
            try
            {
                var doc = System.Xml.Linq.XDocument.Parse(propContent);
                var hrefElements = doc.Descendants().Where(x => x.Name.LocalName.Equals("href", StringComparison.OrdinalIgnoreCase));
                foreach (var elem in hrefElements)
                {
                    var hrefVal = elem.Value.Trim();
                    if (!string.IsNullOrEmpty(hrefVal) && !calendarHrefs.Contains(hrefVal))
                    {
                        calendarHrefs.Add(hrefVal);
                    }
                }
            }
            catch (Exception ex)
            {
                Log($"[CalendarService] Failed to parse PROPFIND XML: {ex.Message}. Falling back to string parsing...");
                int index = 0;
                while (true)
                {
                    index = propContent.IndexOf("href", index, StringComparison.OrdinalIgnoreCase);
                    if (index == -1) break;
                    
                    int tagEnd = propContent.IndexOf(">", index);
                    if (tagEnd == -1) break;
                    
                    int dataStart = tagEnd + 1;
                    int dataEnd = propContent.IndexOf("</", dataStart);
                    if (dataEnd == -1) break;
                    
                    var hrefVal = propContent.Substring(dataStart, dataEnd - dataStart).Trim();
                    if (!string.IsNullOrEmpty(hrefVal) && !calendarHrefs.Contains(hrefVal))
                    {
                        calendarHrefs.Add(hrefVal);
                    }
                    index = dataEnd;
                }
            }

            // Fallback if no hrefs found
            if (calendarHrefs.Count == 0)
            {
                calendarHrefs.Add($"/dav/{user}/Calendar/calendar");
                calendarHrefs.Add($"/dav/{user}/Calendar");
            }

            var startStr = DateTime.UtcNow.AddDays(-30).ToString("yyyyMMddTHHmmssZ");
            var endStr = DateTime.UtcNow.AddDays(90).ToString("yyyyMMddTHHmmssZ");

            var reportXml = $@"<c:calendar-query xmlns:d=""DAV:"" xmlns:c=""urn:ietf:params:xml:ns:caldav"">
              <d:prop>
                <d:getetag />
                <c:calendar-data />
              </d:prop>
              <c:filter>
                <c:comp-filter name=""VCALENDAR"">
                  <c:comp-filter name=""VEVENT"">
                    <c:time-range start=""{startStr}"" end=""{endStr}"" />
                  </c:comp-filter>
                </c:comp-filter>
              </c:filter>
            </c:calendar-query>";

            // Clear old cached events
            await _databaseService.Connection.Table<LocalCalendarEvent>()
                .Where(x => x.AccountId == account.Id)
                .DeleteAsync();

            var seenUids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int parsedCount = 0;

            foreach (var href in calendarHrefs)
            {
                var reportUrl = baseAddress;
                if (href.StartsWith("/"))
                {
                    reportUrl += href;
                }
                else
                {
                    reportUrl += "/" + href;
                }

                Log($"[CalendarService] Sending CalDAV REPORT to Yahoo path: {reportUrl}");

                try
                {
                    var reportRequest = new HttpRequestMessage(new HttpMethod("REPORT"), reportUrl);
                    reportRequest.Headers.TryAddWithoutValidation("Depth", "1");
                    ApplyAuth(reportRequest);
                    reportRequest.Content = new StringContent(reportXml, Encoding.UTF8, "text/xml");

                    var reportResponse = await _httpClient.SendAsync(reportRequest);
                    if (!reportResponse.IsSuccessStatusCode)
                    {
                        Log($"[CalendarService] CalDAV REPORT failed for {reportUrl} with HTTP {reportResponse.StatusCode}");
                        continue;
                    }

                    var content = await reportResponse.Content.ReadAsStringAsync();
                    Log($"[CalendarService] Yahoo CalDAV response length for {href}: {content.Length}");
                    if (content.Length > 316)
                    {
                        Log($"[CalendarService] Yahoo CalDAV response content for {href}: {content}");
                    }

                    if (string.IsNullOrWhiteSpace(content) || !content.Contains("multistatus", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    try
                    {
                        var doc = System.Xml.Linq.XDocument.Parse(content);
                        System.Xml.Linq.XNamespace caldavNs = "urn:ietf:params:xml:ns:caldav";
                        
                        var calendarDataElements = doc.Descendants(caldavNs + "calendar-data");
                        foreach (var elem in calendarDataElements)
                        {
                            var icsContent = elem.Value.Trim();
                            ParseAndCacheIcsEvent(icsContent, account, seenUids);
                            parsedCount++;
                        }
                    }
                    catch (Exception ex)
                    {
                        Log($"[CalendarService] Yahoo XML Linq parsing failed for {href}: {ex.Message}. Falling back to string parsing...");
                        
                        int index = 0;
                        while (true)
                        {
                            index = content.IndexOf("calendar-data", index, StringComparison.OrdinalIgnoreCase);
                            if (index == -1) break;
                            
                            int tagEnd = content.IndexOf(">", index);
                            if (tagEnd == -1) break;
                            
                            int dataStart = tagEnd + 1;
                            int dataEnd = content.IndexOf("</", dataStart);
                            if (dataEnd == -1) break;
                            
                            var icsContent = content.Substring(dataStart, dataEnd - dataStart).Trim();
                            icsContent = System.Net.WebUtility.HtmlDecode(icsContent);
                            
                            ParseAndCacheIcsEvent(icsContent, account, seenUids);
                            parsedCount++;
                            
                            index = dataEnd;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Log($"[CalendarService] Exception during REPORT query for {reportUrl}: {ex.Message}");
                }
            }

            Log($"[CalendarService] Yahoo Sync finished. Parsed {parsedCount} total events ({seenUids.Count} unique).");
        }

        private void ParseAndCacheIcsEvent(string icsText, LocalCalendarAccount account, HashSet<string> seenUids)
        {
            try
            {
                // Unfold lines (RFC 5545: CRLF or LF followed by a space or tab is ignored/removed)
                icsText = icsText.Replace("\r\n ", "")
                                 .Replace("\n ", "")
                                 .Replace("\r\n\t", "")
                                 .Replace("\n\t", "");

                var lines = icsText.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
                string summary = "No Title";
                string desc = "";
                string location = "";
                string uid = "";
                
                DateTime start = DateTime.UtcNow;
                DateTime end = DateTime.UtcNow.AddHours(1);
                bool isAllDay = false;
                bool inVEvent = false;

                foreach (var line in lines)
                {
                    var trimmed = line.Trim();
                    if (trimmed.Equals("BEGIN:VEVENT", StringComparison.OrdinalIgnoreCase))
                    {
                        inVEvent = true;
                        summary = "No Title";
                        desc = "";
                        location = "";
                        uid = Guid.NewGuid().ToString();
                        start = DateTime.UtcNow;
                        end = DateTime.UtcNow.AddHours(1);
                        isAllDay = false;
                        continue;
                    }
                    
                    if (trimmed.Equals("END:VEVENT", StringComparison.OrdinalIgnoreCase))
                    {
                        inVEvent = false;
                        
                        if (!string.IsNullOrEmpty(uid))
                        {
                            if (!seenUids.Contains(uid))
                            {
                                seenUids.Add(uid);
                                
                                var localEvent = new LocalCalendarEvent
                                {
                                    Id = Guid.NewGuid().ToString().ToLowerInvariant(),
                                    AccountId = account.Id,
                                    UserId = account.UserId,
                                    ProviderEventId = uid,
                                    Title = summary,
                                    Description = desc,
                                    Start = start,
                                    End = end,
                                    IsAllDay = isAllDay,
                                    Location = location,
                                    Color = account.Color,
                                    UpdatedAt = DateTime.UtcNow
                                };

                                _databaseService.Connection.InsertAsync(localEvent).Wait();
                            }
                        }
                        continue;
                    }

                    if (!inVEvent) continue;

                    if (line.StartsWith("SUMMARY:", StringComparison.OrdinalIgnoreCase))
                    {
                        summary = line.Substring(8).Trim();
                    }
                    else if (line.StartsWith("DESCRIPTION:", StringComparison.OrdinalIgnoreCase))
                    {
                        desc = line.Substring(12).Trim();
                    }
                    else if (line.StartsWith("LOCATION:", StringComparison.OrdinalIgnoreCase))
                    {
                        location = line.Substring(9).Trim();
                    }
                    else if (line.StartsWith("UID:", StringComparison.OrdinalIgnoreCase))
                    {
                        uid = line.Substring(4).Trim();
                    }
                    else if (line.StartsWith("DTSTART;", StringComparison.OrdinalIgnoreCase) || line.StartsWith("DTSTART:", StringComparison.OrdinalIgnoreCase))
                    {
                        var colonIdx = line.IndexOf(':');
                        if (colonIdx != -1)
                        {
                            var header = line.Substring(0, colonIdx);
                            var val = line.Substring(colonIdx + 1).Trim();
                            var tzid = ExtractTzid(header);
                            start = ParseIcsDateTime(val, tzid, out isAllDay);
                        }
                    }
                    else if (line.StartsWith("DTEND;", StringComparison.OrdinalIgnoreCase) || line.StartsWith("DTEND:", StringComparison.OrdinalIgnoreCase))
                    {
                        var colonIdx = line.IndexOf(':');
                        if (colonIdx != -1)
                        {
                            var header = line.Substring(0, colonIdx);
                            var val = line.Substring(colonIdx + 1).Trim();
                            var tzid = ExtractTzid(header);
                            end = ParseIcsDateTime(val, tzid, out var _);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[CalendarService] ICS parsing failed: {ex.Message}");
            }
        }

        private static readonly Dictionary<string, string> IanaToWindowsTz = new(StringComparer.OrdinalIgnoreCase)
        {
            { "Europe/Bucharest", "GTB Standard Time" },
            { "Europe/London", "GMT Standard Time" },
            { "Europe/Paris", "Romance Standard Time" },
            { "Europe/Berlin", "W. Europe Standard Time" },
            { "America/New_York", "Eastern Standard Time" },
            { "America/Chicago", "Central Standard Time" },
            { "America/Denver", "Mountain Standard Time" },
            { "America/Los_Angeles", "Pacific Standard Time" },
            { "Asia/Tokyo", "Tokyo Standard Time" }
        };

        private string ExtractTzid(string header)
        {
            int tzidIdx = header.IndexOf("TZID=", StringComparison.OrdinalIgnoreCase);
            if (tzidIdx != -1)
            {
                var remaining = header.Substring(tzidIdx + 5);
                int semicolonIdx = remaining.IndexOf(';');
                string tzidVal = semicolonIdx != -1 ? remaining.Substring(0, semicolonIdx) : remaining;
                return tzidVal.Trim(' ', '"', '\'');
            }
            return null;
        }

        private TimeZoneInfo SafeFindTimeZone(string tzid)
        {
            if (string.IsNullOrEmpty(tzid)) return null;

            var cleanTzid = tzid.Trim(' ', '"', '\'', '/', '\\');
            
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(cleanTzid);
            }
            catch {}

            if (IanaToWindowsTz.TryGetValue(cleanTzid, out var windowsTz))
            {
                try
                {
                    return TimeZoneInfo.FindSystemTimeZoneById(windowsTz);
                }
                catch {}
            }

            if (cleanTzid.Contains('/'))
            {
                var parts = cleanTzid.Split('/');
                if (parts.Length >= 2)
                {
                    var lastTwo = parts[parts.Length - 2] + "/" + parts[parts.Length - 1];
                    try
                    {
                        return TimeZoneInfo.FindSystemTimeZoneById(lastTwo);
                    }
                    catch {}
                    
                    if (IanaToWindowsTz.TryGetValue(lastTwo, out var winTz2))
                    {
                        try
                        {
                            return TimeZoneInfo.FindSystemTimeZoneById(winTz2);
                        }
                        catch {}
                    }
                }
                
                var lastPart = parts[parts.Length - 1];
                try
                {
                    return TimeZoneInfo.FindSystemTimeZoneById(lastPart);
                }
                catch {}
                
                if (IanaToWindowsTz.TryGetValue(lastPart, out var winTz3))
                {
                    try
                    {
                        return TimeZoneInfo.FindSystemTimeZoneById(winTz3);
                    }
                    catch {}
                }
            }

            return null;
        }

        private DateTime ParseIcsDateTime(string val, string tzid, out bool isAllDay)
        {
            isAllDay = false;
            // Format can be:
            // 20260610T120000Z (UTC)
            // 20260610T120000 (Local/Floating)
            // 20260610 (Date only)
            
            bool isUtc = val.EndsWith("Z", StringComparison.OrdinalIgnoreCase);
            val = val.Replace("Z", "").Replace("z", "");
            
            if (val.Contains("T"))
            {
                var parts = val.Split('T');
                var dateStr = parts[0];
                var timeStr = parts[1];

                int yr = int.Parse(dateStr.Substring(0, 4));
                int mn = int.Parse(dateStr.Substring(4, 2));
                int dy = int.Parse(dateStr.Substring(6, 2));

                int hr = int.Parse(timeStr.Substring(0, 2));
                int min = int.Parse(timeStr.Substring(2, 2));
                int sec = int.Parse(timeStr.Substring(4, 2));

                var dt = new DateTime(yr, mn, dy, hr, min, sec, DateTimeKind.Unspecified);
                if (isUtc)
                {
                    return DateTime.SpecifyKind(dt, DateTimeKind.Utc);
                }
                else
                {
                    TimeZoneInfo tz = SafeFindTimeZone(tzid) ?? TimeZoneInfo.Local;
                    return TimeZoneInfo.ConvertTimeToUtc(dt, tz);
                }
            }
            else
            {
                // Date only
                int yr = int.Parse(val.Substring(0, 4));
                int mn = int.Parse(val.Substring(4, 2));
                int dy = int.Parse(val.Substring(6, 2));
                isAllDay = true;
                return new DateTime(yr, mn, dy, 0, 0, 0, DateTimeKind.Utc);
            }
        }

        public async Task CompleteTodoAsync(string todoId)
        {
            await _databaseService.InitializeAsync();
            var todo = await _databaseService.Connection.Table<LocalCalendarTodo>().Where(x => x.Id == todoId).FirstOrDefaultAsync();
            if (todo != null)
            {
                // Toggle completion local state
                todo.IsCompleted = !todo.IsCompleted;
                todo.CompletedDate = todo.IsCompleted ? DateTime.UtcNow : null;
                await _databaseService.Connection.UpdateAsync(todo);
                OnCalendarDataChanged?.Invoke();

                // Propagate to Microsoft Graph (in background)
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var account = await _databaseService.Connection.Table<LocalCalendarAccount>()
                            .Where(x => x.Id == todo.AccountId)
                            .FirstOrDefaultAsync();

                        if (account != null && (account.AccountType.Equals("MicrosoftPersonal") || account.AccountType.Equals("MicrosoftWork")))
                        {
                            await RefreshTokenIfNeededAsync(account);

                            // Parse listId and taskId
                            var parts = todo.ProviderTodoId.Split('|');
                            if (parts.Length == 2)
                            {
                                var listId = parts[0];
                                var taskId = parts[1];

                                var url = $"https://graph.microsoft.com/v1.0/me/todo/lists/{listId}/tasks/{taskId}";
                                var patchData = new
                                {
                                    status = todo.IsCompleted ? "completed" : "notStarted"
                                };

                                var patchJson = JsonSerializer.Serialize(patchData);
                                var request = new HttpRequestMessage(new HttpMethod("PATCH"), url);
                                var decryptedAccessToken = Daily.Services.Auth.EncryptionHelper.Decrypt(account.AccessToken, account.UserId);
                                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);
                                request.Content = new StringContent(patchJson, Encoding.UTF8, "application/json");

                                var response = await _httpClient.SendAsync(request);
                                if (!response.IsSuccessStatusCode)
                                {
                                    Log($"[CalendarService] Failed to complete task in Microsoft Graph: {response.StatusCode}");
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Log($"[CalendarService] Microsoft Graph complete task exception: {ex}");
                    }
                });
            }
        }

        public async Task UpdateAccountCustomNameAsync(string accountId, string customName)
        {
            await _databaseService.InitializeAsync();
            var account = await _databaseService.Connection.Table<LocalCalendarAccount>().Where(x => x.Id == accountId).FirstOrDefaultAsync();
            if (account != null)
            {
                account.CustomName = customName ?? string.Empty;
                account.UpdatedAt = DateTime.UtcNow;
                account.SyncedAt = null;
                await _databaseService.Connection.UpdateAsync(account);
                OnCalendarDataChanged?.Invoke();
            }
        }

        public async Task UpdateAccountsOrderAsync(List<string> accountIds)
        {
            if (accountIds == null) return;
            await _databaseService.InitializeAsync();
            for (int i = 0; i < accountIds.Count; i++)
            {
                var id = accountIds[i];
                var account = await _databaseService.Connection.Table<LocalCalendarAccount>().Where(x => x.Id == id).FirstOrDefaultAsync();
                if (account != null)
                {
                    if (account.DisplayOrder != i)
                    {
                        account.DisplayOrder = i;
                        account.UpdatedAt = DateTime.UtcNow;
                        account.SyncedAt = null;
                        await _databaseService.Connection.UpdateAsync(account);
                    }
                }
            }
            OnCalendarDataChanged?.Invoke();
        }

        public static string DetermineIdentifiedName(string email, string accountType)
        {
            if (string.IsNullOrWhiteSpace(email)) return string.Empty;

            // 1. Google -> always "Google"
            if (accountType.Equals("Google", StringComparison.OrdinalIgnoreCase))
            {
                return "Google";
            }

            // 2. Yahoo -> always "Yahoo"
            if (accountType.Equals("Yahoo", StringComparison.OrdinalIgnoreCase))
            {
                return "Yahoo";
            }

            // Extract domain
            int atIndex = email.LastIndexOf('@');
            if (atIndex < 0 || atIndex >= email.Length - 1)
            {
                return "Outlook"; // fallback
            }

            string domain = email.Substring(atIndex + 1).ToLowerInvariant();

            // 3. Microsoft Personal domains
            if (domain.StartsWith("outlook.") || domain == "outlook")
            {
                return "Outlook";
            }
            if (domain.StartsWith("hotmail.") || domain == "hotmail")
            {
                return "Hotmail";
            }
            if (domain.StartsWith("live.") || domain == "live")
            {
                return "Live";
            }
            if (domain == "msn.com" || domain == "msn")
            {
                return "MSN";
            }

            // 4. Microsoft Work/School or any other domain -> try to extract the company/school name
            // Split domain by '.'
            string[] parts = domain.Split('.');
            if (parts.Length > 0)
            {
                // Common TLDs and SLDs to filter out from right-to-left
                var commonSuffixes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                {
                    "com", "org", "edu", "net", "gov", "mil", "co", "ac", "or", "go", "ltd", "me", "io", "cc", "tv", 
                    "biz", "info", "mobi", "name", "us", "uk", "ca", "de", "fr", "jp", "au", "ro", "nl", "it", "es", "ch", "se", "no"
                };

                // Traverse right-to-left and pick the first part that is not in the common suffixes
                for (int i = parts.Length - 1; i >= 0; i--)
                {
                    string part = parts[i];
                    if (!commonSuffixes.Contains(part))
                    {
                        // Capitalize the first letter
                        if (part.Length > 0)
                        {
                            return char.ToUpper(part[0]) + part.Substring(1);
                        }
                    }
                }

                // Fallback: capitalize the first part of domain if everything is classified as suffix
                string firstPart = parts[0];
                if (firstPart.Length > 0)
                {
                    return char.ToUpper(firstPart[0]) + firstPart.Substring(1);
                }
            }

            return "Outlook"; // default fallback for microsoft/office365
        }

        private void Log(string message)
        {
            Console.WriteLine(message);
            System.Diagnostics.Debug.WriteLine(message);
            try
            {
                var logPath = System.IO.Path.Combine(System.AppDomain.CurrentDomain.BaseDirectory, "calendar_sync_debug.log");
                System.IO.File.AppendAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\r\n");
            }
            catch { }
        }
    }
}
