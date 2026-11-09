using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Daily.Configuration;
using Daily.Models;
using Daily.Services;
using Daily.Services.Auth;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;
using Supabase.Postgrest;
using Supabase.Realtime;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Daily_WinUI.Services;

public sealed class PrismService : IPrismService
{
    private const string BucketName = "prism-clips";
    private const string PrimaryGeminiModel = "gemini-2.5-flash";

    private readonly IDatabaseService _databaseService;
    private readonly Supabase.Client _supabaseClient;
    private readonly ISupabaseSessionGuardian _sessionGuardian;
    private readonly ITagdosService _tagdosService;
    private readonly IRssArticleService _rssArticleService;
    private readonly IRssFeedService _rssFeedService;
    private readonly ISmartIntelligenceService _smartIntelligence;
    private readonly IHttpClientFactory _httpClientFactory;

    private readonly SemaphoreSlim _loadLock = new(1, 1);
    private readonly SemaphoreSlim _syncLock = new(1, 1);
    private readonly object _stateLock = new();

    private readonly string _appFolder;
    private readonly string _clipsImageFolder;
    private readonly string _tabsStatePath;
    private readonly string _watermarksPath;

    private List<PrismClip> _clips = new();
    private List<PrismPinnedSite> _pinnedSites = new();
    private List<PrismTabState> _tabs = new();
    private string? _activeTabId;
    private string? _pendingUrlRequest;
    private string? _clipboardCandidateUrl;
    private string? _lastDismissedClipboardUrl;

    private bool _isLoaded;
    private RealtimeChannel? _clipsChannel;
    private RealtimeChannel? _pinsChannel;
    private string? _realtimeUserId;
    private long _lastLocalPushMs;
    private readonly IGotrueClient<User, Session>.AuthEventHandler _authListener;

    public event EventHandler? DataChanged;

    public PrismService(
        IDatabaseService databaseService,
        Supabase.Client supabaseClient,
        ISupabaseSessionGuardian sessionGuardian,
        ITagdosService tagdosService,
        IRssArticleService rssArticleService,
        IRssFeedService rssFeedService,
        ISmartIntelligenceService smartIntelligence,
        IHttpClientFactory httpClientFactory)
    {
        _databaseService = databaseService;
        _supabaseClient = supabaseClient;
        _sessionGuardian = sessionGuardian;
        _tagdosService = tagdosService;
        _rssArticleService = rssArticleService;
        _rssFeedService = rssFeedService;
        _smartIntelligence = smartIntelligence;
        _httpClientFactory = httpClientFactory;

        _appFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Daily.WinUI");
        _clipsImageFolder = Path.Combine(_appFolder, "PrismClips");
        _tabsStatePath = Path.Combine(_appFolder, "prism_tabs.json");
        _watermarksPath = Path.Combine(_appFolder, "prism_sync_watermarks.json");
        Directory.CreateDirectory(_clipsImageFolder);

        LoadTabsFromDisk();

        _authListener = OnAuthStateChanged;
        _supabaseClient.Auth.AddStateChangedListener(_authListener);
    }

    public IReadOnlyList<PrismClip> Clips
    {
        get { lock (_stateLock) return _clips.ToList(); }
    }

    public IReadOnlyList<PrismPinnedSite> PinnedSites
    {
        get { lock (_stateLock) return _pinnedSites.ToList(); }
    }

    public IReadOnlyList<PrismTabState> Tabs
    {
        get { lock (_stateLock) return _tabs.ToList(); }
    }

    public string? ActiveTabId => _activeTabId;
    public string? PendingUrlRequest => _pendingUrlRequest;
    public string? ClipboardCandidateUrl => _clipboardCandidateUrl;

    public async Task EnsureLoadedAsync()
    {
        if (_isLoaded)
        {
            return;
        }

        await _loadLock.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_isLoaded)
            {
                return;
            }

            await _databaseService.InitializeAsync().ConfigureAwait(false);
            await ReloadLocalStateCoreAsync().ConfigureAwait(false);
            _isLoaded = true;
        }
        finally
        {
            _loadLock.Release();
        }

        if (_supabaseClient.Auth.CurrentUser != null && _realtimeUserId == null)
        {
            _ = Task.Run(() => SetupRealtimeAsync(forceRecreate: false));
        }
    }

    private async Task ReloadLocalStateCoreAsync()
    {
        var conn = _databaseService.Connection;

        var localClips = await conn.Table<LocalPrismClip>()
            .Where(c => !c.IsDeleted)
            .OrderByDescending(c => c.CreatedAtTicks)
            .ToListAsync()
            .ConfigureAwait(false);

        var allPins = await conn.Table<LocalPrismPinnedSite>().ToListAsync().ConfigureAwait(false);
        if (allPins.Count == 0)
        {
            string scope = _supabaseClient.Auth.CurrentUser?.Id ?? "local";
            var seeds = PrismPinnedSite.CreateDefaultStarterSites(scope);
            foreach (var seed in seeds)
            {
                await conn.InsertOrReplaceAsync(ToLocalPin(seed, syncedTicks: DateTime.UtcNow.Ticks)).ConfigureAwait(false);
            }

            allPins = await conn.Table<LocalPrismPinnedSite>().ToListAsync().ConfigureAwait(false);
        }

        var activePins = allPins
            .Where(p => !p.IsDeleted)
            .OrderBy(p => p.DisplayOrder)
            .ThenBy(p => p.CreatedAtTicks)
            .Select(FromLocalPin)
            .ToList();

        var mappedClips = localClips.Select(FromLocalClip).ToList();

        lock (_stateLock)
        {
            _clips = mappedClips;
            _pinnedSites = activePins;
        }
    }

    private void NotifyDataChanged()
    {
        DataChanged?.Invoke(this, EventArgs.Empty);
    }

    // ── Single-Active-Engine Tab Hibernation (Max 8 Tabs) ─────────────────────

    private sealed class PersistedTabBundle
    {
        public string? ActiveTabId { get; set; }
        public List<PrismTabState> Tabs { get; set; } = new();
    }

    private void LoadTabsFromDisk()
    {
        List<PrismTabState> restored = new();
        string? savedActive = null;

        try
        {
            if (File.Exists(_tabsStatePath))
            {
                string raw = File.ReadAllText(_tabsStatePath);
                var bundle = JsonConvert.DeserializeObject<PersistedTabBundle>(raw);
                if (bundle?.Tabs != null)
                {
                    restored = bundle.Tabs.Where(t => !t.IsPrivate).ToList();
                    savedActive = bundle.ActiveTabId;
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] LoadTabsFromDisk warning: {ex.Message}");
        }

        if (restored.Count == 0)
        {
            restored.Add(new PrismTabState { Title = "Start Page" });
        }

        string activeId = restored.FirstOrDefault(t => t.Id == savedActive)?.Id ?? restored[0].Id;
        foreach (var tab in restored)
        {
            tab.IsHibernated = tab.Id != activeId;
        }

        lock (_stateLock)
        {
            _tabs = restored;
            _activeTabId = activeId;
        }
    }

    private void SaveTabsToDisk()
    {
        try
        {
            PersistedTabBundle bundle;
            lock (_stateLock)
            {
                bundle = new PersistedTabBundle
                {
                    ActiveTabId = _activeTabId,
                    Tabs = _tabs.Where(t => !t.IsPrivate).ToList()
                };
            }

            Directory.CreateDirectory(_appFolder);
            File.WriteAllText(_tabsStatePath, JsonConvert.SerializeObject(bundle, Formatting.None));
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] SaveTabsToDisk warning: {ex.Message}");
        }
    }

    public PrismTabState? GetActiveTab()
    {
        lock (_stateLock)
        {
            return _tabs.FirstOrDefault(t => t.Id == _activeTabId) ?? _tabs.FirstOrDefault();
        }
    }

    public void SelectTab(string tabId)
    {
        lock (_stateLock)
        {
            if (_tabs.All(t => t.Id != tabId))
            {
                return;
            }

            _activeTabId = tabId;
            long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            foreach (var tab in _tabs)
            {
                tab.IsHibernated = tab.Id != tabId;
                if (tab.Id == tabId)
                {
                    tab.LastAccessedEpochMs = now;
                }
            }
        }

        SaveTabsToDisk();
        NotifyDataChanged();
    }

    public PrismTabState OpenNewTab(string url = "", string? title = null, bool isPrivate = false)
    {
        PrismTabState created;
        lock (_stateLock)
        {
            if (_tabs.Count >= PrismTabState.MaxOpenTabs)
            {
                var victim = _tabs.Where(t => t.Id != _activeTabId).OrderBy(t => t.LastAccessedEpochMs).FirstOrDefault();
                if (victim != null)
                {
                    _tabs.Remove(victim);
                }
            }

            string domain = string.IsNullOrWhiteSpace(url) ? string.Empty : PrismSearchEngineHelper.ExtractCleanDomain(url);
            string resolvedTitle = !string.IsNullOrWhiteSpace(title)
                ? title
                : (string.IsNullOrWhiteSpace(url) ? (isPrivate ? "Private Tab" : "Start Page") : domain);

            created = new PrismTabState
            {
                Url = url,
                Title = resolvedTitle,
                Domain = domain,
                IsPrivate = isPrivate,
                IsHibernated = false
            };

            _tabs.Add(created);
            _activeTabId = created.Id;
            foreach (var tab in _tabs)
            {
                tab.IsHibernated = tab.Id != created.Id;
            }
        }

        SaveTabsToDisk();
        NotifyDataChanged();
        return created;
    }

    public void CloseTab(string tabId)
    {
        lock (_stateLock)
        {
            int idx = _tabs.FindIndex(t => t.Id == tabId);
            if (idx < 0)
            {
                return;
            }

            bool wasActive = _activeTabId == tabId;
            _tabs.RemoveAt(idx);

            if (_tabs.Count == 0)
            {
                var fresh = new PrismTabState { Title = "Start Page" };
                _tabs.Add(fresh);
                _activeTabId = fresh.Id;
            }
            else if (wasActive)
            {
                int nextIdx = Math.Min(idx, _tabs.Count - 1);
                _activeTabId = _tabs[nextIdx].Id;
                foreach (var tab in _tabs)
                {
                    tab.IsHibernated = tab.Id != _activeTabId;
                }
            }
        }

        SaveTabsToDisk();
        NotifyDataChanged();
    }

    public void UpdateActiveTabMetadata(
        string? url = null,
        string? title = null,
        int? scrollY = null,
        bool? isReaderMode = null,
        string? detectedRssUrl = "__keep__",
        string? detectedRssTitle = "__keep__")
    {
        lock (_stateLock)
        {
            var tab = _tabs.FirstOrDefault(t => t.Id == _activeTabId);
            if (tab == null)
            {
                return;
            }

            if (!string.IsNullOrWhiteSpace(url))
            {
                tab.Url = url;
                tab.Domain = PrismSearchEngineHelper.ExtractCleanDomain(url);
            }

            if (!string.IsNullOrWhiteSpace(title))
            {
                tab.Title = title;
            }

            if (scrollY.HasValue)
            {
                tab.ScrollY = scrollY.Value;
            }

            if (isReaderMode.HasValue)
            {
                tab.IsReaderMode = isReaderMode.Value;
            }

            if (detectedRssUrl != "__keep__")
            {
                tab.DetectedRssUrl = detectedRssUrl;
            }

            if (detectedRssTitle != "__keep__")
            {
                tab.DetectedRssTitle = detectedRssTitle;
            }
        }

        SaveTabsToDisk();
        NotifyDataChanged();
    }

    public void RequestOpenUrlInPrism(string rawUrl, string? title = null, bool openInNewTab = false)
    {
        string? safe = PrismSearchEngineHelper.ResolveOmniboxInput(rawUrl);
        if (string.IsNullOrWhiteSpace(safe))
        {
            return;
        }

        if (openInNewTab || GetActiveTab()?.IsPrivate == true)
        {
            OpenNewTab(safe, title, isPrivate: false);
        }
        else
        {
            UpdateActiveTabMetadata(url: safe, title: title, isReaderMode: false, detectedRssUrl: null, detectedRssTitle: null);
        }

        _pendingUrlRequest = safe;
        NotifyDataChanged();
    }

    public string? ConsumePendingUrlRequest()
    {
        string? req = _pendingUrlRequest;
        _pendingUrlRequest = null;
        return req;
    }

    public void CheckClipboardCandidate(string? rawClipboardText, bool enabled)
    {
        if (!enabled || string.IsNullOrWhiteSpace(rawClipboardText))
        {
            _clipboardCandidateUrl = null;
            return;
        }

        string trimmed = rawClipboardText.Trim();
        if ((!trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase) &&
             !trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase)) ||
            trimmed.Contains(' '))
        {
            return;
        }

        bool alreadyOpen = Tabs.Any(t => string.Equals(t.Url, trimmed, StringComparison.OrdinalIgnoreCase));
        bool alreadySaved = Clips.Any(c => string.Equals(c.SourceUrl, trimmed, StringComparison.OrdinalIgnoreCase));
        if (!alreadyOpen && !alreadySaved && !string.Equals(trimmed, _lastDismissedClipboardUrl, StringComparison.OrdinalIgnoreCase))
        {
            _clipboardCandidateUrl = trimmed;
            NotifyDataChanged();
        }
    }

    public void DismissClipboardCandidate()
    {
        _lastDismissedClipboardUrl = _clipboardCandidateUrl;
        _clipboardCandidateUrl = null;
        NotifyDataChanged();
    }

    // ── Prism Vault Capture Operations ────────────────────────────────────────

    public async Task<PrismClip> SaveLinkClipAsync(
        string url,
        string title,
        string? previewImageUrl = null,
        string userNote = "",
        IReadOnlyList<string>? tags = null)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        string domain = PrismSearchEngineHelper.ExtractCleanDomain(url);
        var now = DateTime.UtcNow;
        var clip = new PrismClip
        {
            UserId = _supabaseClient.Auth.CurrentUser?.Id,
            ClipType = PrismClipType.Link,
            Title = string.IsNullOrWhiteSpace(title) ? domain : title.Trim(),
            SourceUrl = url.Trim(),
            Domain = domain,
            UserNote = userNote.Trim(),
            Tags = tags?.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim().TrimStart('#').ToLowerInvariant()).Distinct().ToList() ?? new List<string>(),
            PreviewImageUrl = previewImageUrl,
            CreatedAtUtc = now,
            UpdatedAtUtc = now
        };

        await PersistAndPushClipAsync(clip).ConfigureAwait(false);
        return clip;
    }

    public async Task<PrismClip> SaveQuoteClipAsync(
        string quoteText,
        string sourceUrl,
        string pageTitle,
        string userNote = "",
        IReadOnlyList<string>? tags = null)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        string domain = PrismSearchEngineHelper.ExtractCleanDomain(sourceUrl);
        var now = DateTime.UtcNow;
        var clip = new PrismClip
        {
            UserId = _supabaseClient.Auth.CurrentUser?.Id,
            ClipType = PrismClipType.Quote,
            Title = string.IsNullOrWhiteSpace(pageTitle) ? domain : pageTitle.Trim(),
            SourceUrl = sourceUrl.Trim(),
            Domain = domain,
            ContentText = quoteText.Trim(),
            UserNote = userNote.Trim(),
            Tags = tags?.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim().TrimStart('#').ToLowerInvariant()).Distinct().ToList() ?? new List<string>(),
            CreatedAtUtc = now,
            UpdatedAtUtc = now
        };

        await PersistAndPushClipAsync(clip).ConfigureAwait(false);
        return clip;
    }

    public async Task<PrismClip> SaveAiSummaryClipAsync(PrismCoPilotTurn turn)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        var sb = new StringBuilder();
        sb.Append(turn.ResponseMarkdown);
        if (turn.KeyBullets.Count > 0)
        {
            sb.AppendLine().AppendLine();
            foreach (string bullet in turn.KeyBullets)
            {
                sb.Append("• ").AppendLine(bullet);
            }
        }

        var now = DateTime.UtcNow;
        string domain = PrismSearchEngineHelper.ExtractCleanDomain(turn.SourceUrl);
        var clip = new PrismClip
        {
            UserId = _supabaseClient.Auth.CurrentUser?.Id,
            ClipType = PrismClipType.AiSummary,
            Title = string.IsNullOrWhiteSpace(turn.PageTitle) ? turn.Prompt : $"{turn.PageTitle} — {turn.Prompt}",
            SourceUrl = turn.SourceUrl,
            Domain = domain,
            ContentText = sb.ToString().Trim(),
            Tags = new List<string> { "ai" },
            CreatedAtUtc = now,
            UpdatedAtUtc = now
        };

        await PersistAndPushClipAsync(clip).ConfigureAwait(false);
        return clip;
    }

    public async Task<PrismClip> SaveImageClipAsync(
        byte[]? rawImageBytes,
        string? remoteImageUrl,
        string sourceUrl,
        string title,
        int? width = null,
        int? height = null,
        IReadOnlyList<string>? tags = null)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        string clipId = Guid.NewGuid().ToString("D");

        if ((rawImageBytes == null || rawImageBytes.Length == 0) && !string.IsNullOrWhiteSpace(remoteImageUrl))
        {
            try
            {
                var client = _httpClientFactory.CreateClient();
                rawImageBytes = await client.GetByteArrayAsync(remoteImageUrl).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PrismService] Remote image fetch warning: {ex.Message}");
            }
        }

        byte[]? compressedJpeg = null;
        int? outWidth = width;
        int? outHeight = height;

        if (rawImageBytes != null && rawImageBytes.Length > 0)
        {
            var compressed = await CompressToJpegMax1600Async(rawImageBytes).ConfigureAwait(false);
            compressedJpeg = compressed.JpegBytes;
            outWidth = compressed.Width ?? outWidth;
            outHeight = compressed.Height ?? outHeight;

            string localFile = Path.Combine(_clipsImageFolder, $"{clipId}.jpg");
            await File.WriteAllBytesAsync(localFile, compressedJpeg).ConfigureAwait(false);
        }

        string? storagePath = null;
        string? userId = _supabaseClient.Auth.CurrentUser?.Id;
        if (!string.IsNullOrEmpty(userId) && compressedJpeg != null && compressedJpeg.Length > 0)
        {
            storagePath = await UploadImageToSupabaseStorageAsync(userId, clipId, compressedJpeg).ConfigureAwait(false);
        }

        string domain = PrismSearchEngineHelper.ExtractCleanDomain(sourceUrl);
        var now = DateTime.UtcNow;
        var clip = new PrismClip
        {
            Id = clipId,
            UserId = userId,
            ClipType = PrismClipType.Image,
            Title = string.IsNullOrWhiteSpace(title) ? (string.IsNullOrEmpty(domain) ? "Captured Image" : domain) : title.Trim(),
            SourceUrl = sourceUrl.Trim(),
            Domain = domain,
            Tags = tags?.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim().TrimStart('#').ToLowerInvariant()).Distinct().ToList() ?? new List<string>(),
            PreviewImageUrl = remoteImageUrl,
            StoragePath = storagePath,
            ImageWidth = outWidth,
            ImageHeight = outHeight,
            CreatedAtUtc = now,
            UpdatedAtUtc = now
        };

        await PersistAndPushClipAsync(clip).ConfigureAwait(false);
        return clip;
    }

    public async Task ToggleFavoriteClipAsync(string clipId)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        var conn = _databaseService.Connection;
        var existing = await conn.FindAsync<LocalPrismClip>(clipId).ConfigureAwait(false);
        if (existing == null)
        {
            return;
        }

        existing.IsFavorite = !existing.IsFavorite;
        existing.UpdatedAtTicks = DateTime.UtcNow.Ticks;
        existing.SyncedAtTicks = null;
        await conn.InsertOrReplaceAsync(existing).ConfigureAwait(false);
        await ReloadLocalStateCoreAsync().ConfigureAwait(false);
        NotifyDataChanged();

        _ = Task.Run(() => PushSingleClipIfAuthenticatedAsync(FromLocalClip(existing)));
    }

    public async Task DeleteClipAsync(string clipId)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        var conn = _databaseService.Connection;
        var existing = await conn.FindAsync<LocalPrismClip>(clipId).ConfigureAwait(false);
        if (existing == null)
        {
            return;
        }

        existing.IsDeleted = true;
        existing.UpdatedAtTicks = DateTime.UtcNow.Ticks;
        existing.SyncedAtTicks = null;
        await conn.InsertOrReplaceAsync(existing).ConfigureAwait(false);

        string localFile = Path.Combine(_clipsImageFolder, $"{clipId}.jpg");
        if (File.Exists(localFile))
        {
            try { File.Delete(localFile); } catch { }
        }

        await ReloadLocalStateCoreAsync().ConfigureAwait(false);
        NotifyDataChanged();

        _ = Task.Run(async () =>
        {
            if (!string.IsNullOrWhiteSpace(existing.StoragePath))
            {
                await DeleteStorageObjectAsync(existing.StoragePath).ConfigureAwait(false);
            }

            await PushSingleClipIfAuthenticatedAsync(FromLocalClip(existing)).ConfigureAwait(false);
        });
    }

    public async Task<string?> ResolveClipImageLocalPathAsync(PrismClip clip, CancellationToken ct = default)
    {
        string localFile = Path.Combine(_clipsImageFolder, $"{clip.Id}.jpg");
        if (File.Exists(localFile))
        {
            return localFile;
        }

        byte[]? downloaded = null;
        if (!string.IsNullOrWhiteSpace(clip.StoragePath))
        {
            downloaded = await DownloadStorageObjectAsync(clip.StoragePath, ct).ConfigureAwait(false);
        }

        if ((downloaded == null || downloaded.Length == 0) && !string.IsNullOrWhiteSpace(clip.PreviewImageUrl))
        {
            try
            {
                var client = _httpClientFactory.CreateClient();
                downloaded = await client.GetByteArrayAsync(clip.PreviewImageUrl, ct).ConfigureAwait(false);
            }
            catch { }
        }

        if (downloaded != null && downloaded.Length > 0)
        {
            await File.WriteAllBytesAsync(localFile, downloaded, ct).ConfigureAwait(false);
            return localFile;
        }

        return null;
    }

    // ── Speed Dial Pinned Sites ───────────────────────────────────────────────

    public async Task TogglePinSiteAsync(string title, string url)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        string? normalizedUrl = PrismSearchEngineHelper.ResolveOmniboxInput(url);
        if (string.IsNullOrWhiteSpace(normalizedUrl))
        {
            return;
        }

        var conn = _databaseService.Connection;
        var allPins = await conn.Table<LocalPrismPinnedSite>().ToListAsync().ConfigureAwait(false);
        var match = allPins.FirstOrDefault(p => string.Equals(p.Url.TrimEnd('/'), normalizedUrl.TrimEnd('/'), StringComparison.OrdinalIgnoreCase));

        if (match != null && !match.IsDeleted)
        {
            match.IsDeleted = true;
            match.UpdatedAtTicks = DateTime.UtcNow.Ticks;
            match.SyncedAtTicks = null;
            await conn.InsertOrReplaceAsync(match).ConfigureAwait(false);
            await ReloadLocalStateCoreAsync().ConfigureAwait(false);
            NotifyDataChanged();
            _ = Task.Run(() => PushSinglePinIfAuthenticatedAsync(FromLocalPin(match)));
        }
        else
        {
            string scope = _supabaseClient.Auth.CurrentUser?.Id ?? "local";
            string domain = PrismSearchEngineHelper.ExtractCleanDomain(normalizedUrl);
            var pin = new PrismPinnedSite
            {
                Id = match?.Id ?? PrismPinnedSite.DeterministicId(scope, normalizedUrl),
                UserId = _supabaseClient.Auth.CurrentUser?.Id,
                Title = string.IsNullOrWhiteSpace(title) ? domain : title.Trim(),
                Url = normalizedUrl,
                Domain = domain,
                IconUrl = $"https://www.google.com/s2/favicons?domain={domain}&sz=64",
                DisplayOrder = PinnedSites.Count,
                IsDeleted = false,
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow
            };

            await conn.InsertOrReplaceAsync(ToLocalPin(pin, syncedTicks: null)).ConfigureAwait(false);
            await ReloadLocalStateCoreAsync().ConfigureAwait(false);
            NotifyDataChanged();
            _ = Task.Run(() => PushSinglePinIfAuthenticatedAsync(pin));
        }
    }

    public async Task DeletePinnedSiteAsync(string pinId)
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        var conn = _databaseService.Connection;
        var existing = await conn.FindAsync<LocalPrismPinnedSite>(pinId).ConfigureAwait(false);
        if (existing == null)
        {
            return;
        }

        existing.IsDeleted = true;
        existing.UpdatedAtTicks = DateTime.UtcNow.Ticks;
        existing.SyncedAtTicks = null;
        await conn.InsertOrReplaceAsync(existing).ConfigureAwait(false);
        await ReloadLocalStateCoreAsync().ConfigureAwait(false);
        NotifyDataChanged();

        _ = Task.Run(() => PushSinglePinIfAuthenticatedAsync(FromLocalPin(existing)));
    }

    // ── Ecosystem Bridges (`TagDoS` & `News`) ─────────────────────────────────

    public async Task SendClipToTagdosAsync(PrismClip clip)
    {
        var tagList = new List<string> { "prism" };
        tagList.AddRange(clip.Tags);
        string tagFooter = string.Join(" ", tagList.Distinct(StringComparer.OrdinalIgnoreCase).Select(t => $"#{t}"));
        string body = !string.IsNullOrWhiteSpace(clip.ContentText)
            ? $"> {clip.ContentText}\n\n🔗 {clip.SourceUrl}\n{tagFooter}"
            : $"🔗 {clip.SourceUrl}\n{tagFooter}";

        var createdNote = await _tagdosService.CreateQuickNoteAsync($"💎 {clip.Title}", body, isPinned: false).ConfigureAwait(false);

        var conn = _databaseService.Connection;
        var local = await conn.FindAsync<LocalPrismClip>(clip.Id).ConfigureAwait(false);
        if (local != null)
        {
            local.TagdosNoteId = createdNote.Id;
            local.UpdatedAtTicks = DateTime.UtcNow.Ticks;
            local.SyncedAtTicks = null;
            await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);
            await ReloadLocalStateCoreAsync().ConfigureAwait(false);
            NotifyDataChanged();
            _ = Task.Run(() => PushSingleClipIfAuthenticatedAsync(FromLocalClip(local)));
        }
    }

    public async Task SendTasksToTagdosAsync(IReadOnlyList<string> tasks, string pageTitle, string sourceUrl)
    {
        if (tasks.Count == 0)
        {
            return;
        }

        string checklist = string.Join("\n", tasks.Select(t => $"- [ ] {t}"));
        string content = $"{checklist}\n\n🔗 {sourceUrl}\n#prism #tasks";
        string title = string.IsNullOrWhiteSpace(pageTitle) ? "🎯 Prism Action Items" : $"🎯 Tasks: {pageTitle}";
        await _tagdosService.CreateQuickNoteAsync(title, content, isPinned: false).ConfigureAwait(false);
    }

    public async Task SaveClipToReadLaterAsync(PrismClip clip)
    {
        if (string.IsNullOrWhiteSpace(clip.SourceUrl))
        {
            return;
        }

        var rssItem = new RssItem
        {
            Title = clip.Title,
            Link = clip.SourceUrl,
            Description = clip.ContentText,
            PublishDate = clip.CreatedAtUtc,
            PublicationName = string.IsNullOrWhiteSpace(clip.Domain) ? "Prism Web" : clip.Domain
        };

        await _rssArticleService.SaveArticleAsync(
            rssItem,
            rssItem.PublicationName ?? "Prism Web",
            clip.PreviewImageUrl,
            SavedArticleType.ReadLater).ConfigureAwait(false);
    }

    public async Task SubscribeRssFeedAsync(string feedUrl, string feedTitle)
    {
        if (string.IsNullOrWhiteSpace(feedUrl))
        {
            return;
        }

        string userId = _supabaseClient.Auth.CurrentUser?.Id ?? "local_user";
        string domain = PrismSearchEngineHelper.ExtractCleanDomain(feedUrl);
        string name = string.IsNullOrWhiteSpace(feedTitle) ? domain : feedTitle.Trim();
        await _rssFeedService.AddFeedAsync(feedUrl.Trim(), name, "Tech", userId).ConfigureAwait(false);
    }

    // ── Prism Co-Pilot (Gemini 2.5 Flash + Windows Hardware NPU + Extractive) ─

    public Task<PrismCoPilotTurn> RunCoPilotActionAsync(
        PrismCoPilotAction action,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string? selectedText,
        CancellationToken ct = default)
    {
        string promptLabel = action switch
        {
            PrismCoPilotAction.TldrSummary => "TL;DR Summary",
            PrismCoPilotAction.ExtractTasks => "Extract Actionable Tasks",
            PrismCoPilotAction.KeyFactsAndNumbers => "Key Facts & Numbers",
            PrismCoPilotAction.ExplainSelection => "Explain Selection",
            _ => "Analyze Page"
        };

        string instruction = action switch
        {
            PrismCoPilotAction.TldrSummary => "Provide a crisp 2-3 sentence executive summary and 3-5 high-signal bullet points.",
            PrismCoPilotAction.ExtractTasks => "Extract concrete, actionable follow-up tasks or next steps from this page.",
            PrismCoPilotAction.KeyFactsAndNumbers => "Extract the most important quantitative metrics, dates, benchmarks, and verifiable facts.",
            PrismCoPilotAction.ExplainSelection => "Explain the selected passage clearly in context and highlight why it matters.",
            _ => "Summarize this page clearly."
        };

        return ExecuteCoPilotCoreAsync(promptLabel, instruction, pageTitle, sourceUrl, bodyText, selectedText, ct);
    }

    public Task<PrismCoPilotTurn> AskCoPilotQuestionAsync(
        string question,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string? selectedText,
        CancellationToken ct = default)
    {
        return ExecuteCoPilotCoreAsync(
            question.Trim(),
            $"Answer the user's question accurately based on the page context: {question.Trim()}",
            pageTitle,
            sourceUrl,
            bodyText,
            selectedText,
            ct);
    }

    private async Task<PrismCoPilotTurn> ExecuteCoPilotCoreAsync(
        string promptLabel,
        string instruction,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string? selectedText,
        CancellationToken ct)
    {
        string truncatedBody = bodyText.Length > 12000 ? bodyText.Substring(0, 12000) : bodyText;
        string truncatedSelection = !string.IsNullOrWhiteSpace(selectedText)
            ? (selectedText.Length > 2500 ? selectedText.Substring(0, 2500) : selectedText)
            : string.Empty;

        var settings = SettingsService.Load();
        string? geminiKey = !string.IsNullOrWhiteSpace(settings.PrismGeminiApiKey)
            ? settings.PrismGeminiApiKey
            : Environment.GetEnvironmentVariable("GEMINI_API_KEY");

        // Tier 1: Gemini 2.5 Flash structured synthesis when API key is configured
        if (!string.IsNullOrWhiteSpace(geminiKey))
        {
            var geminiTurn = await TryInvokeGeminiAsync(promptLabel, instruction, pageTitle, sourceUrl, truncatedBody, truncatedSelection, geminiKey!, ct).ConfigureAwait(false);
            if (geminiTurn != null)
            {
                return geminiTurn;
            }
        }

        // Tier 2: Windows 11 On-Device Hardware NPU (Phi Silica 45 TOPS) or Local GGUF AI
        try
        {
            if (await _smartIntelligence.IsModelReadyAsync().ConfigureAwait(false))
            {
                await _smartIntelligence.InitializeAsync().ConfigureAwait(false);
                string sysPrompt = "You are Prism Co-Pilot inside DayOne. Respond concisely with clear markdown paragraphs and bullet points.";
                string localBody = truncatedBody.Length > 3800 ? truncatedBody.Substring(0, 3800) : truncatedBody;
                string userPrompt = $"Page: {pageTitle} ({sourceUrl})\n" +
                                    (!string.IsNullOrEmpty(truncatedSelection) ? $"Selected Text:\n{truncatedSelection}\n\n" : string.Empty) +
                                    $"Content:\n{localBody}\n\nTask: {instruction}";

                string rawResponse = await _smartIntelligence.GenerateResponseAsync(sysPrompt, userPrompt, ct).ConfigureAwait(false);
                if (!string.IsNullOrWhiteSpace(rawResponse))
                {
                    var bullets = ExtractMarkdownBullets(rawResponse);
                    return new PrismCoPilotTurn
                    {
                        Prompt = promptLabel,
                        ResponseMarkdown = rawResponse.Trim(),
                        KeyBullets = bullets.Take(5).ToList(),
                        SuggestedTasks = promptLabel.Contains("Task", StringComparison.OrdinalIgnoreCase) ? bullets.Take(5).ToList() : new List<string>(),
                        EngineBadge = _smartIntelligence.IsPhiSilicaActive ? "Phi Silica NPU" : _smartIntelligence.ActiveEngineName,
                        SourceUrl = sourceUrl,
                        PageTitle = pageTitle
                    };
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] Local NPU/AI fallback notice: {ex.Message}");
        }

        // Tier 3: Deterministic zero-latency extractive synthesis
        return BuildDeterministicFallbackTurn(promptLabel, pageTitle, sourceUrl, truncatedBody, truncatedSelection);
    }

    private async Task<PrismCoPilotTurn?> TryInvokeGeminiAsync(
        string promptLabel,
        string instruction,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string selectedText,
        string apiKey,
        CancellationToken ct)
    {
        try
        {
            string endpoint = $"https://generativelanguage.googleapis.com/v1beta/models/{PrimaryGeminiModel}:generateContent?key={Uri.EscapeDataString(apiKey.Trim())}";
            string prompt =
                "You are Prism Co-Pilot inside DayOne. Return ONLY valid JSON with keys: " +
                "\"summary\" (string), \"bullets\" (array of up to 5 strings), \"tasks\" (array of up to 5 actionable strings).\n\n" +
                $"Title: {pageTitle}\nURL: {sourceUrl}\n" +
                (!string.IsNullOrEmpty(selectedText) ? $"Selected Text:\n{selectedText}\n\n" : string.Empty) +
                $"Page Content:\n{bodyText}\n\nInstruction: {instruction}";

            var payload = new JObject
            {
                ["contents"] = new JArray
                {
                    new JObject
                    {
                        ["parts"] = new JArray { new JObject { ["text"] = prompt } }
                    }
                },
                ["generationConfig"] = new JObject
                {
                    ["temperature"] = 0.25,
                    ["responseMimeType"] = "application/json"
                }
            };

            var client = _httpClientFactory.CreateClient();
            using var content = new StringContent(payload.ToString(Formatting.None), Encoding.UTF8, "application/json");
            using var resp = await client.PostAsync(endpoint, content, ct).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode)
            {
                return null;
            }

            string respBody = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            var root = JObject.Parse(respBody);
            string? textJson = root["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]?.ToString();
            if (string.IsNullOrWhiteSpace(textJson))
            {
                return null;
            }

            var parsed = JObject.Parse(textJson);
            string summary = parsed["summary"]?.ToString() ?? string.Empty;
            var bullets = parsed["bullets"]?.Values<string?>().Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s!.Trim()).ToList() ?? new List<string>();
            var tasks = parsed["tasks"]?.Values<string?>().Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s!.Trim()).ToList() ?? new List<string>();

            if (string.IsNullOrWhiteSpace(summary) && bullets.Count == 0)
            {
                return null;
            }

            return new PrismCoPilotTurn
            {
                Prompt = promptLabel,
                ResponseMarkdown = summary,
                KeyBullets = bullets,
                SuggestedTasks = tasks,
                EngineBadge = "Gemini 2.5 Flash",
                SourceUrl = sourceUrl,
                PageTitle = pageTitle
            };
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] Gemini request warning: {ex.Message}");
            return null;
        }
    }

    private static List<string> ExtractMarkdownBullets(string markdown)
    {
        return markdown
            .Split('\n')
            .Select(line => line.Trim())
            .Where(line => line.StartsWith("- ", StringComparison.Ordinal) || line.StartsWith("* ", StringComparison.Ordinal) || line.StartsWith("• ", StringComparison.Ordinal))
            .Select(line => line.Substring(2).Trim())
            .Where(line => line.Length > 4)
            .ToList();
    }

    private static PrismCoPilotTurn BuildDeterministicFallbackTurn(
        string promptLabel,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string selectedText)
    {
        string source = !string.IsNullOrWhiteSpace(selectedText) ? selectedText : bodyText;
        var sentences = Regex.Split(source, @"(?<=[\.\!\?])\s+")
            .Select(s => Regex.Replace(s, @"\s+", " ").Trim())
            .Where(s => s.Length >= 40 && s.Length <= 260)
            .Distinct()
            .ToList();

        string lead = sentences.FirstOrDefault() ?? (string.IsNullOrWhiteSpace(pageTitle) ? "Page context extracted offline." : $"Extracted key context from {pageTitle}.");
        var bullets = sentences.Skip(1).Take(4).ToList();
        var tasks = new List<string>();
        if (promptLabel.Contains("Task", StringComparison.OrdinalIgnoreCase))
        {
            tasks.Add($"Review: {(string.IsNullOrWhiteSpace(pageTitle) ? sourceUrl : pageTitle)}");
            foreach (string s in bullets.Take(2))
            {
                tasks.Add(s.Length > 90 ? s.Substring(0, 87) + "..." : s);
            }
        }

        return new PrismCoPilotTurn
        {
            Prompt = promptLabel,
            ResponseMarkdown = lead,
            KeyBullets = bullets,
            SuggestedTasks = tasks,
            EngineBadge = "Offline Extractive",
            SourceUrl = sourceUrl,
            PageTitle = pageTitle
        };
    }

    // ── Lean Supabase Sync + Realtime + Storage ───────────────────────────────

    private sealed class SyncWatermarks
    {
        public Dictionary<string, DateTime> ClipsWatermarkByUser { get; set; } = new();
        public Dictionary<string, DateTime> PinsWatermarkByUser { get; set; } = new();
    }

    private SyncWatermarks LoadWatermarks()
    {
        try
        {
            if (File.Exists(_watermarksPath))
            {
                return JsonConvert.DeserializeObject<SyncWatermarks>(File.ReadAllText(_watermarksPath)) ?? new SyncWatermarks();
            }
        }
        catch { }

        return new SyncWatermarks();
    }

    private void SaveWatermarks(SyncWatermarks wm)
    {
        try
        {
            Directory.CreateDirectory(_appFolder);
            File.WriteAllText(_watermarksPath, JsonConvert.SerializeObject(wm, Formatting.None));
        }
        catch { }
    }

    public async Task SyncWithRemoteAsync()
    {
        await EnsureLoadedAsync().ConfigureAwait(false);
        string? userId = _supabaseClient.Auth.CurrentUser?.Id;
        if (string.IsNullOrEmpty(userId))
        {
            return;
        }

        if (!await _syncLock.WaitAsync(0).ConfigureAwait(false))
        {
            return;
        }

        try
        {
            var conn = _databaseService.Connection;
            var watermarks = LoadWatermarks();
            bool anyChanged = false;

            // 1. Push dirty local clips (`ReturnType.Minimal`)
            var allLocalClips = await conn.Table<LocalPrismClip>().ToListAsync().ConfigureAwait(false);
            foreach (var dirty in allLocalClips.Where(c => c.SyncedAtTicks == null))
            {
                if (dirty.ClipType == "image" && string.IsNullOrEmpty(dirty.StoragePath) && !dirty.IsDeleted)
                {
                    string localImg = Path.Combine(_clipsImageFolder, $"{dirty.Id}.jpg");
                    if (File.Exists(localImg))
                    {
                        byte[] bytes = await File.ReadAllBytesAsync(localImg).ConfigureAwait(false);
                        dirty.StoragePath = await UploadImageToSupabaseStorageAsync(userId, dirty.Id, bytes).ConfigureAwait(false);
                    }
                }

                var remote = ToRemoteClip(dirty, userId);
                Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                await _supabaseClient.From<RemotePrismClip>()
                    .Upsert(remote, new QueryOptions { Returning = QueryOptions.ReturnType.Minimal })
                    .ConfigureAwait(false);

                dirty.UserId = userId;
                dirty.SyncedAtTicks = DateTime.UtcNow.Ticks;
                await conn.InsertOrReplaceAsync(dirty).ConfigureAwait(false);
            }

            // 2. Pull incremental clip deltas since `updated_at` watermark
            var clipQuery = _supabaseClient.From<RemotePrismClip>()
                .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userId);

            if (watermarks.ClipsWatermarkByUser.TryGetValue(userId, out var clipWm))
            {
                string iso = clipWm.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", CultureInfo.InvariantCulture);
                clipQuery = clipQuery.Filter("updated_at", Supabase.Postgrest.Constants.Operator.GreaterThan, iso);
            }

            var remoteClipsResp = await clipQuery
                .Order("updated_at", Supabase.Postgrest.Constants.Ordering.Descending)
                .Limit(200)
                .Get()
                .ConfigureAwait(false);

            DateTime maxClipUtc = watermarks.ClipsWatermarkByUser.TryGetValue(userId, out var existingClipWm)
                ? existingClipWm
                : DateTime.MinValue;

            foreach (var rc in remoteClipsResp.Models)
            {
                DateTime rUpdated = rc.UpdatedAt.ToUniversalTime();
                if (rUpdated > maxClipUtc)
                {
                    maxClipUtc = rUpdated;
                }

                var localExisting = await conn.FindAsync<LocalPrismClip>(rc.Id).ConfigureAwait(false);
                if (localExisting == null || rUpdated.Ticks >= localExisting.UpdatedAtTicks)
                {
                    await conn.InsertOrReplaceAsync(FromRemoteClipToLocal(rc)).ConfigureAwait(false);
                    anyChanged = true;
                }
            }

            if (maxClipUtc > DateTime.MinValue)
            {
                watermarks.ClipsWatermarkByUser[userId] = maxClipUtc;
            }

            // 3. Push dirty local pinned sites
            var allLocalPins = await conn.Table<LocalPrismPinnedSite>().ToListAsync().ConfigureAwait(false);
            foreach (var dirtyPin in allLocalPins.Where(p => p.SyncedAtTicks == null))
            {
                string canonicalId = PrismPinnedSite.DeterministicId(userId, dirtyPin.Url);
                var remotePin = ToRemotePin(dirtyPin, userId, canonicalId);
                Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                await _supabaseClient.From<RemotePrismPinnedSite>()
                    .Upsert(remotePin, new QueryOptions { Returning = QueryOptions.ReturnType.Minimal })
                    .ConfigureAwait(false);

                if (dirtyPin.Id != canonicalId)
                {
                    await conn.DeleteAsync(dirtyPin).ConfigureAwait(false);
                    dirtyPin.Id = canonicalId;
                }

                dirtyPin.UserId = userId;
                dirtyPin.SyncedAtTicks = DateTime.UtcNow.Ticks;
                await conn.InsertOrReplaceAsync(dirtyPin).ConfigureAwait(false);
                anyChanged = true;
            }

            // 4. Pull incremental pinned sites deltas
            var pinQuery = _supabaseClient.From<RemotePrismPinnedSite>()
                .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userId);

            if (watermarks.PinsWatermarkByUser.TryGetValue(userId, out var pinWm))
            {
                string iso = pinWm.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", CultureInfo.InvariantCulture);
                pinQuery = pinQuery.Filter("updated_at", Supabase.Postgrest.Constants.Operator.GreaterThan, iso);
            }

            var remotePinsResp = await pinQuery
                .Order("display_order", Supabase.Postgrest.Constants.Ordering.Ascending)
                .Get()
                .ConfigureAwait(false);

            DateTime maxPinUtc = watermarks.PinsWatermarkByUser.TryGetValue(userId, out var existingPinWm)
                ? existingPinWm
                : DateTime.MinValue;

            foreach (var rp in remotePinsResp.Models)
            {
                DateTime rUpdated = rp.UpdatedAt.ToUniversalTime();
                if (rUpdated > maxPinUtc)
                {
                    maxPinUtc = rUpdated;
                }

                var localExisting = await conn.FindAsync<LocalPrismPinnedSite>(rp.Id).ConfigureAwait(false);
                if (localExisting == null || rUpdated.Ticks >= localExisting.UpdatedAtTicks)
                {
                    await conn.InsertOrReplaceAsync(FromRemotePinToLocal(rp)).ConfigureAwait(false);
                    anyChanged = true;
                }
            }

            if (maxPinUtc > DateTime.MinValue)
            {
                watermarks.PinsWatermarkByUser[userId] = maxPinUtc;
            }

            SaveWatermarks(watermarks);

            if (anyChanged)
            {
                await ReloadLocalStateCoreAsync().ConfigureAwait(false);
                NotifyDataChanged();
            }

            if (_realtimeUserId != userId)
            {
                _ = Task.Run(() => SetupRealtimeAsync(forceRecreate: false));
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] SyncWithRemoteAsync warning: {ex.Message}");
        }
        finally
        {
            _syncLock.Release();
        }
    }

    private void OnAuthStateChanged(IGotrueClient<User, Session> sender, Supabase.Gotrue.Constants.AuthState state)
    {
        if (state == Supabase.Gotrue.Constants.AuthState.SignedIn || state == Supabase.Gotrue.Constants.AuthState.TokenRefreshed)
        {
            _ = Task.Run(async () =>
            {
                await SetupRealtimeAsync(forceRecreate: false).ConfigureAwait(false);
                if (state == Supabase.Gotrue.Constants.AuthState.SignedIn)
                {
                    await SyncWithRemoteAsync().ConfigureAwait(false);
                }
            });
        }
        else if (state == Supabase.Gotrue.Constants.AuthState.SignedOut)
        {
            _realtimeUserId = null;
        }
    }

    private async Task SetupRealtimeAsync(bool forceRecreate)
    {
        string? userId = _supabaseClient.Auth.CurrentUser?.Id;
        if (string.IsNullOrEmpty(userId))
        {
            return;
        }

        if (!forceRecreate && _realtimeUserId == userId && _clipsChannel != null)
        {
            return;
        }

        try
        {
            if (!await _sessionGuardian.EnsureRealtimeConnectedAsync().ConfigureAwait(false))
            {
                return;
            }

            try { _clipsChannel?.Unsubscribe(); } catch { }
            try { _pinsChannel?.Unsubscribe(); } catch { }

            _clipsChannel = await _supabaseClient.From<RemotePrismClip>()
                .On(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, (_, _) =>
                {
                    long elapsed = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - Interlocked.Read(ref _lastLocalPushMs);
                    if (elapsed > 1500)
                    {
                        _ = Task.Run(SyncWithRemoteAsync);
                    }
                })
                .ConfigureAwait(false);

            _pinsChannel = await _supabaseClient.From<RemotePrismPinnedSite>()
                .On(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, (_, _) =>
                {
                    long elapsed = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - Interlocked.Read(ref _lastLocalPushMs);
                    if (elapsed > 1500)
                    {
                        _ = Task.Run(SyncWithRemoteAsync);
                    }
                })
                .ConfigureAwait(false);

            _realtimeUserId = userId;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] SetupRealtimeAsync warning: {ex.Message}");
        }
    }

    private async Task PersistAndPushClipAsync(PrismClip clip)
    {
        var conn = _databaseService.Connection;
        var local = ToLocalClip(clip, syncedTicks: null);
        await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);
        await ReloadLocalStateCoreAsync().ConfigureAwait(false);
        NotifyDataChanged();

        _ = Task.Run(() => PushSingleClipIfAuthenticatedAsync(clip));
    }

    private async Task PushSingleClipIfAuthenticatedAsync(PrismClip clip)
    {
        string? userId = _supabaseClient.Auth.CurrentUser?.Id;
        if (string.IsNullOrEmpty(userId))
        {
            return;
        }

        try
        {
            var local = ToLocalClip(clip, syncedTicks: null);
            var remote = ToRemoteClip(local, userId);
            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            await _supabaseClient.From<RemotePrismClip>()
                .Upsert(remote, new QueryOptions { Returning = QueryOptions.ReturnType.Minimal })
                .ConfigureAwait(false);

            local.UserId = userId;
            local.SyncedAtTicks = DateTime.UtcNow.Ticks;
            await _databaseService.Connection.InsertOrReplaceAsync(local).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] PushSingleClip warning: {ex.Message}");
        }
    }

    private async Task PushSinglePinIfAuthenticatedAsync(PrismPinnedSite pin)
    {
        string? userId = _supabaseClient.Auth.CurrentUser?.Id;
        if (string.IsNullOrEmpty(userId))
        {
            return;
        }

        try
        {
            string canonicalId = PrismPinnedSite.DeterministicId(userId, pin.Url);
            var local = ToLocalPin(pin, syncedTicks: null);
            var remote = ToRemotePin(local, userId, canonicalId);
            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            await _supabaseClient.From<RemotePrismPinnedSite>()
                .Upsert(remote, new QueryOptions { Returning = QueryOptions.ReturnType.Minimal })
                .ConfigureAwait(false);

            local.Id = canonicalId;
            local.UserId = userId;
            local.SyncedAtTicks = DateTime.UtcNow.Ticks;
            await _databaseService.Connection.InsertOrReplaceAsync(local).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] PushSinglePin warning: {ex.Message}");
        }
    }

    // ── Private `prism-clips` Storage & Max-1600px JPEG Compression ───────────

    private static async Task<(byte[] JpegBytes, int? Width, int? Height)> CompressToJpegMax1600Async(byte[] inputBytes)
    {
        try
        {
            using var inStream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(inStream.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(inputBytes);
                await writer.StoreAsync();
            }

            var decoder = await BitmapDecoder.CreateAsync(inStream);
            uint srcW = decoder.PixelWidth;
            uint srcH = decoder.PixelHeight;
            uint maxEdge = Math.Max(srcW, srcH);

            uint targetW = srcW;
            uint targetH = srcH;
            if (maxEdge > 1600)
            {
                double ratio = 1600.0 / maxEdge;
                targetW = Math.Max(1u, (uint)Math.Round(srcW * ratio));
                targetH = Math.Max(1u, (uint)Math.Round(srcH * ratio));
            }

            var softwareBitmap = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                new BitmapTransform { ScaledWidth = targetW, ScaledHeight = targetH, InterpolationMode = BitmapInterpolationMode.Fant },
                ExifOrientationMode.RespectExifOrientation,
                ColorManagementMode.DoNotColorManage);

            using var outStream = new InMemoryRandomAccessStream();
            var propertySet = new BitmapPropertySet
            {
                { "ImageQuality", new BitmapTypedValue(0.82, Windows.Foundation.PropertyType.Single) }
            };
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, outStream, propertySet);
            encoder.SetSoftwareBitmap(softwareBitmap);
            await encoder.FlushAsync();

            byte[] outBytes = new byte[outStream.Size];
            using (var reader = new DataReader(outStream.GetInputStreamAt(0)))
            {
                await reader.LoadAsync((uint)outStream.Size);
                reader.ReadBytes(outBytes);
            }

            softwareBitmap.Dispose();
            return (outBytes, (int)targetW, (int)targetH);
        }
        catch
        {
            return (inputBytes, null, null);
        }
    }

    private async Task<string?> UploadImageToSupabaseStorageAsync(string userId, string clipId, byte[] jpegBytes)
    {
        try
        {
            string? token = _supabaseClient.Auth.CurrentSession?.AccessToken;
            if (string.IsNullOrEmpty(token))
            {
                return null;
            }

            string remotePath = $"{userId.ToLowerInvariant()}/{clipId.ToLowerInvariant()}.jpg";
            string url = $"{Secrets.SupabaseUrl.TrimEnd('/')}/storage/v1/object/{BucketName}/{remotePath}";

            var client = _httpClientFactory.CreateClient();
            using var req = new HttpRequestMessage(HttpMethod.Post, url);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            req.Headers.Add("apikey", Secrets.SupabaseKey);
            req.Headers.Add("x-upsert", "true");
            req.Content = new ByteArrayContent(jpegBytes);
            req.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");

            using var resp = await client.SendAsync(req).ConfigureAwait(false);
            return resp.IsSuccessStatusCode ? remotePath : null;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismService] Storage upload warning: {ex.Message}");
            return null;
        }
    }

    private async Task<byte[]?> DownloadStorageObjectAsync(string storagePath, CancellationToken ct)
    {
        try
        {
            string? token = _supabaseClient.Auth.CurrentSession?.AccessToken;
            if (string.IsNullOrEmpty(token))
            {
                return null;
            }

            string url = $"{Secrets.SupabaseUrl.TrimEnd('/')}/storage/v1/object/authenticated/{BucketName}/{storagePath.TrimStart('/')}";
            var client = _httpClientFactory.CreateClient();
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            req.Headers.Add("apikey", Secrets.SupabaseKey);

            using var resp = await client.SendAsync(req, ct).ConfigureAwait(false);
            return resp.IsSuccessStatusCode ? await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false) : null;
        }
        catch
        {
            return null;
        }
    }

    private async Task DeleteStorageObjectAsync(string storagePath)
    {
        try
        {
            string? token = _supabaseClient.Auth.CurrentSession?.AccessToken;
            if (string.IsNullOrEmpty(token))
            {
                return;
            }

            string url = $"{Secrets.SupabaseUrl.TrimEnd('/')}/storage/v1/object/{BucketName}/{storagePath.TrimStart('/')}";
            var client = _httpClientFactory.CreateClient();
            using var req = new HttpRequestMessage(HttpMethod.Delete, url);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            req.Headers.Add("apikey", Secrets.SupabaseKey);
            using var _ = await client.SendAsync(req).ConfigureAwait(false);
        }
        catch { }
    }

    // ── Entity Mappers ────────────────────────────────────────────────────────

    private static LocalPrismClip ToLocalClip(PrismClip c, long? syncedTicks) => new()
    {
        Id = c.Id,
        UserId = c.UserId,
        ClipType = c.ClipType.ToRawValue(),
        Title = c.Title,
        SourceUrl = c.SourceUrl,
        Domain = c.Domain,
        ContentText = c.ContentText,
        UserNote = c.UserNote,
        TagsJson = JsonConvert.SerializeObject(c.Tags),
        PreviewImageUrl = c.PreviewImageUrl,
        StoragePath = c.StoragePath,
        ImageWidth = c.ImageWidth,
        ImageHeight = c.ImageHeight,
        IsFavorite = c.IsFavorite,
        IsDeleted = c.IsDeleted,
        TagdosNoteId = c.TagdosNoteId,
        CreatedAtTicks = c.CreatedAtUtc.Ticks,
        UpdatedAtTicks = c.UpdatedAtUtc.Ticks,
        SyncedAtTicks = syncedTicks
    };

    private static PrismClip FromLocalClip(LocalPrismClip row)
    {
        List<string> tags = new();
        try
        {
            if (!string.IsNullOrWhiteSpace(row.TagsJson))
            {
                tags = JsonConvert.DeserializeObject<List<string>>(row.TagsJson) ?? new List<string>();
            }
        }
        catch { }

        return new PrismClip
        {
            Id = row.Id,
            UserId = row.UserId,
            ClipType = PrismClipTypeExtensions.FromRawValue(row.ClipType),
            Title = row.Title,
            SourceUrl = row.SourceUrl,
            Domain = row.Domain,
            ContentText = row.ContentText,
            UserNote = row.UserNote,
            Tags = tags,
            PreviewImageUrl = row.PreviewImageUrl,
            StoragePath = row.StoragePath,
            ImageWidth = row.ImageWidth,
            ImageHeight = row.ImageHeight,
            IsFavorite = row.IsFavorite,
            IsDeleted = row.IsDeleted,
            TagdosNoteId = row.TagdosNoteId,
            CreatedAtUtc = new DateTime(row.CreatedAtTicks, DateTimeKind.Utc),
            UpdatedAtUtc = new DateTime(row.UpdatedAtTicks, DateTimeKind.Utc)
        };
    }

    private static RemotePrismClip ToRemoteClip(LocalPrismClip row, string userId)
    {
        List<string> tags = new();
        try
        {
            if (!string.IsNullOrWhiteSpace(row.TagsJson))
            {
                tags = JsonConvert.DeserializeObject<List<string>>(row.TagsJson) ?? new List<string>();
            }
        }
        catch { }

        return new RemotePrismClip
        {
            Id = Guid.TryParse(row.Id, out _) ? row.Id : Guid.NewGuid().ToString("D"),
            UserId = userId,
            ClipType = row.ClipType,
            Title = row.Title,
            SourceUrl = row.SourceUrl,
            Domain = row.Domain,
            ContentText = row.ContentText,
            UserNote = row.UserNote,
            Tags = tags,
            PreviewImageUrl = row.PreviewImageUrl,
            StoragePath = row.StoragePath,
            ImageWidth = row.ImageWidth,
            ImageHeight = row.ImageHeight,
            IsFavorite = row.IsFavorite,
            IsDeleted = row.IsDeleted,
            TagdosNoteId = Guid.TryParse(row.TagdosNoteId, out _) ? row.TagdosNoteId : null,
            CreatedAt = new DateTime(row.CreatedAtTicks, DateTimeKind.Utc),
            UpdatedAt = new DateTime(row.UpdatedAtTicks, DateTimeKind.Utc)
        };
    }

    private static LocalPrismClip FromRemoteClipToLocal(RemotePrismClip rc) => new()
    {
        Id = rc.Id,
        UserId = rc.UserId,
        ClipType = rc.ClipType,
        Title = rc.Title,
        SourceUrl = rc.SourceUrl,
        Domain = rc.Domain,
        ContentText = rc.ContentText,
        UserNote = rc.UserNote,
        TagsJson = JsonConvert.SerializeObject(rc.Tags ?? new List<string>()),
        PreviewImageUrl = rc.PreviewImageUrl,
        StoragePath = rc.StoragePath,
        ImageWidth = rc.ImageWidth,
        ImageHeight = rc.ImageHeight,
        IsFavorite = rc.IsFavorite,
        IsDeleted = rc.IsDeleted,
        TagdosNoteId = rc.TagdosNoteId,
        CreatedAtTicks = rc.CreatedAt.ToUniversalTime().Ticks,
        UpdatedAtTicks = rc.UpdatedAt.ToUniversalTime().Ticks,
        SyncedAtTicks = DateTime.UtcNow.Ticks
    };

    private static LocalPrismPinnedSite ToLocalPin(PrismPinnedSite p, long? syncedTicks) => new()
    {
        Id = p.Id,
        UserId = p.UserId,
        Title = p.Title,
        Url = p.Url,
        Domain = p.Domain,
        IconUrl = p.IconUrl,
        DisplayOrder = p.DisplayOrder,
        IsDeleted = p.IsDeleted,
        CreatedAtTicks = p.CreatedAtUtc.Ticks,
        UpdatedAtTicks = p.UpdatedAtUtc.Ticks,
        SyncedAtTicks = syncedTicks
    };

    private static PrismPinnedSite FromLocalPin(LocalPrismPinnedSite row) => new()
    {
        Id = row.Id,
        UserId = row.UserId,
        Title = row.Title,
        Url = row.Url,
        Domain = row.Domain,
        IconUrl = row.IconUrl,
        DisplayOrder = row.DisplayOrder,
        IsDeleted = row.IsDeleted,
        CreatedAtUtc = new DateTime(row.CreatedAtTicks, DateTimeKind.Utc),
        UpdatedAtUtc = new DateTime(row.UpdatedAtTicks, DateTimeKind.Utc)
    };

    private static RemotePrismPinnedSite ToRemotePin(LocalPrismPinnedSite row, string userId, string canonicalId) => new()
    {
        Id = canonicalId,
        UserId = userId,
        Title = row.Title,
        Url = row.Url,
        Domain = row.Domain,
        IconUrl = row.IconUrl,
        DisplayOrder = row.DisplayOrder,
        IsDeleted = row.IsDeleted,
        CreatedAt = new DateTime(row.CreatedAtTicks, DateTimeKind.Utc),
        UpdatedAt = new DateTime(row.UpdatedAtTicks, DateTimeKind.Utc)
    };

    private static LocalPrismPinnedSite FromRemotePinToLocal(RemotePrismPinnedSite rp) => new()
    {
        Id = rp.Id,
        UserId = rp.UserId,
        Title = rp.Title,
        Url = rp.Url,
        Domain = rp.Domain,
        IconUrl = rp.IconUrl,
        DisplayOrder = rp.DisplayOrder,
        IsDeleted = rp.IsDeleted,
        CreatedAtTicks = rp.CreatedAt.ToUniversalTime().Ticks,
        UpdatedAtTicks = rp.UpdatedAt.ToUniversalTime().Ticks,
        SyncedAtTicks = DateTime.UtcNow.Ticks
    };
}
