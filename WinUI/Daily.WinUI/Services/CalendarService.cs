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
            return await _databaseService.Connection.Table<LocalCalendarAccount>().ToListAsync();
        }

        public async Task AddAccountAsync(LocalCalendarAccount account)
        {
            await _databaseService.InitializeAsync();
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
                // In SQLite we can just delete, but we should mark deleted or just delete and let sync handle it.
                // For simplicity, we delete local account, events, and todos.
                await _databaseService.Connection.DeleteAsync(account);
                await _databaseService.Connection.Table<LocalCalendarEvent>().Where(x => x.AccountId == id).DeleteAsync();
                await _databaseService.Connection.Table<LocalCalendarTodo>().Where(x => x.AccountId == id).DeleteAsync();
                
                // Trigger Supabase sync to delete/propagate
                // We'll mark the synced accounts state
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
                System.Diagnostics.Debug.WriteLine($"[CalendarService] Sync failed for account {account.Email}: {ex.Message}");
            }
        }

        private async Task RefreshTokenIfNeededAsync(LocalCalendarAccount account)
        {
            // Yahoo uses App Passwords so token refreshing is not needed
            if (account.AccountType.Equals("Yahoo", StringComparison.OrdinalIgnoreCase)) return;

            // Check expiry with a 5-minute buffer
            if (DateTime.UtcNow.AddMinutes(5) < account.TokenExpiresAt.ToUniversalTime()) return;

            System.Diagnostics.Debug.WriteLine($"[CalendarService] Refreshing token for {account.Email}...");

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
                    System.Diagnostics.Debug.WriteLine($"[CalendarService] Google token refreshed successfully.");
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
                    System.Diagnostics.Debug.WriteLine($"[CalendarService] Microsoft token refreshed successfully.");
                }
                else
                {
                    throw new Exception($"Microsoft Token Refresh HTTP {response.StatusCode}");
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
                throw new Exception($"Google Calendar Sync HTTP {response.StatusCode}");
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

            // 1. Sync Calendar View Events (expanded recurrence)
            var startStr = DateTime.UtcNow.AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ");
            var endStr = DateTime.UtcNow.AddDays(90).ToString("yyyy-MM-ddTHH:mm:ssZ");
            var url = $"https://graph.microsoft.com/v1.0/me/calendarView?startDateTime={Uri.EscapeDataString(startStr)}&endDateTime={Uri.EscapeDataString(endStr)}";

            var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", decryptedAccessToken);

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
                            start = DateTime.Parse(dtStr).ToUniversalTime();
                        }

                        if (ev.TryGetProperty("end", out var endEl))
                        {
                            var dtStr = endEl.GetProperty("dateTime").GetString()!;
                            var zoneStr = endEl.GetProperty("timeZone").GetString()!;
                            end = DateTime.Parse(dtStr).ToUniversalTime();
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
            // Simple CalDAV sync using username + App Password (stored in AccessToken)
            // Yahoo CalDAV URL: https://caldav.calendar.yahoo.com
            // CalDAV uses HTTP basic auth
            
            var user = account.Email;
            var appPassword = Daily.Services.Auth.EncryptionHelper.Decrypt(account.AccessToken, account.UserId);

            var baseAddress = "https://caldav.calendar.yahoo.com";
            
            // Step 1: Query collection list to find calendar paths
            // We do a simple propfind request
            var propfindXml = @"<d:propfind xmlns:d=""DAV:"">
                <d:prop></d:prop>
            </d:propfind>";

            var propRequest = new HttpRequestMessage(new HttpMethod("PROPFIND"), $"{baseAddress}/dav/{user}/Calendar");
            propRequest.Headers.TryAddWithoutValidation("Depth", "1");
            var authBytes = Encoding.UTF8.GetBytes($"{user}:{appPassword}");
            propRequest.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
            propRequest.Content = new StringContent(propfindXml, Encoding.UTF8, "text/xml");

            var propResponse = await _httpClient.SendAsync(propRequest);
            if (!propResponse.IsSuccessStatusCode)
            {
                throw new Exception($"Yahoo CalDAV collection query HTTP {propResponse.StatusCode}");
            }

            // Parse response to find calendar URLs. If parsing is complex, we target the default user calendar path:
            // https://caldav.calendar.yahoo.com/dav/{email}/Calendar/calendar/
            // Many Yahoo calendars default to `/dav/{email}/Calendar/calendar` or `/dav/{email}/Calendar/calendar/`
            // Let's do a calendar-query report on the user's primary path.
            
            var reportXml = @"<c:calendar-query xmlns:d=""DAV:"" xmlns:c=""urn:ietf:params:xml:ns:caldav"">
              <d:prop>
                <d:getetag />
                <c:calendar-data />
              </d:prop>
              <c:filter>
                <c:comp-filter name=""VCALENDAR"">
                  <c:comp-filter name=""VEVENT"" />
                </c:comp-filter>
              </c:filter>
            </c:calendar-query>";

            // Try the standard main path
            var reportUrl = $"{baseAddress}/dav/{user}/Calendar/calendar";
            var reportRequest = new HttpRequestMessage(new HttpMethod("REPORT"), reportUrl);
            reportRequest.Headers.TryAddWithoutValidation("Depth", "1");
            reportRequest.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
            reportRequest.Content = new StringContent(reportXml, Encoding.UTF8, "text/xml");

            var reportResponse = await _httpClient.SendAsync(reportRequest);
            if (!reportResponse.IsSuccessStatusCode)
            {
                // Try fallback directory
                reportUrl = $"{baseAddress}/dav/{user}/Calendar";
                reportRequest = new HttpRequestMessage(new HttpMethod("REPORT"), reportUrl);
                reportRequest.Headers.TryAddWithoutValidation("Depth", "1");
                reportRequest.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
                reportRequest.Content = new StringContent(reportXml, Encoding.UTF8, "text/xml");
                reportResponse = await _httpClient.SendAsync(reportRequest);
            }

            if (reportResponse.IsSuccessStatusCode)
            {
                var content = await reportResponse.Content.ReadAsStringAsync();
                
                // Clear old cached events
                await _databaseService.Connection.Table<LocalCalendarEvent>()
                    .Where(x => x.AccountId == account.Id)
                    .DeleteAsync();

                // Simple custom iCalendar (ics) text parser inside XML nodes
                // CalDAV returns XML containing <c:calendar-data> tags, which hold raw .ics content.
                int index = 0;
                while (true)
                {
                    index = content.IndexOf("<c:calendar-data>", index);
                    if (index == -1) index = content.IndexOf("<calendar-data xmlns=\"urn:ietf:params:xml:ns:caldav\">", index);
                    if (index == -1) break;

                    int dataStart = content.IndexOf(">", index) + 1;
                    int dataEnd = content.IndexOf("</", dataStart);
                    if (dataEnd == -1) break;

                    var icsContent = content.Substring(dataStart, dataEnd - dataStart).Trim();
                    icsContent = System.Net.WebUtility.HtmlDecode(icsContent);

                    ParseAndCacheIcsEvent(icsContent, account);

                    index = dataEnd;
                }
            }
            else
            {
                throw new Exception($"Yahoo CalDAV query HTTP {reportResponse.StatusCode}");
            }
        }

        private void ParseAndCacheIcsEvent(string icsText, LocalCalendarAccount account)
        {
            try
            {
                var lines = icsText.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
                string summary = "No Title";
                string desc = "";
                string location = "";
                string uid = Guid.NewGuid().ToString();
                
                DateTime start = DateTime.UtcNow;
                DateTime end = DateTime.UtcNow.AddHours(1);
                bool isAllDay = false;

                foreach (var line in lines)
                {
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
                        var val = line.Substring(line.IndexOf(":") + 1).Trim();
                        start = ParseIcsDateTime(val, out isAllDay);
                    }
                    else if (line.StartsWith("DTEND;", StringComparison.OrdinalIgnoreCase) || line.StartsWith("DTEND:", StringComparison.OrdinalIgnoreCase))
                    {
                        var val = line.Substring(line.IndexOf(":") + 1).Trim();
                        end = ParseIcsDateTime(val, out var _);
                    }
                }

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
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CalendarService] ICS parsing failed: {ex.Message}");
            }
        }

        private DateTime ParseIcsDateTime(string val, out bool isAllDay)
        {
            isAllDay = false;
            // Format can be:
            // 20260610T120000Z (UTC)
            // 20260610T120000 (Local)
            // 20260610 (Date only)
            
            val = val.Replace("Z", "");
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

                return new DateTime(yr, mn, dy, hr, min, sec, DateTimeKind.Utc);
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
                                    System.Diagnostics.Debug.WriteLine($"[CalendarService] Failed to complete task in Microsoft Graph: {response.StatusCode}");
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[CalendarService] Microsoft Graph complete task exception: {ex.Message}");
                    }
                });
            }
        }
    }
}
