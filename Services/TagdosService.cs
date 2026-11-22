using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Services.Auth;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;
using Supabase.Realtime;

namespace Daily.Services
{
    public class TagdosService : ITagdosService
    {
        private static readonly (int index, string title, string raw, int hour, int min)[] DefaultStreamSeeds =
        {
            (0, "Morning Prime", "MG/GM/TG & FSH/LDL & C$T/INV & 22/HAB & MED/CHK & REV/DEP & WRK/PRJ", 8, 30),
            (1, "Work Execution", "WRK/PRJ/REV & MET/ZOOM & CALL/CLI & BUG/FIX", 10, 0),
            (2, "Fitness & Health", "FIT/GYM & RUN/5K & PROT/SHK & CREAT/5G & SLP/REC", 17, 30),
            (3, "Finances & Ledger", "FIN/CARD & CASH/EUR & INV/STK & CRYP/BTC", 19, 0),
            (4, "Home & Routine", "HOM/ORD & CLN/KIT & BUY/MKT & GROC/VEG", 21, 0)
        };

        private const string SeedNote1Title = "Executive Briefing Focus";
        private const string SeedNote1Content = "1. Focus on top 3 deep work streams\n2. Review quarterly financial roadmap\n3. Sync multi-device biometrics";
        private const string SeedNote2Title = "Desktop Reading Queue";
        private const string SeedNote2Content = "• Windows App SDK & WinUI 3 Composition APIs\n• Cross-platform shared architecture with DailyCore";

        private readonly IDatabaseService _databaseService;
        private readonly Supabase.Client? _supabaseClient;
        private readonly ILogger<TagdosService>? _logger;
        private readonly ISupabaseSessionGuardian? _sessionGuardian;

        private readonly List<TagDoStream> _cachedStreams = new();
        private readonly List<TagDoQuickNote> _cachedNotes = new();
        private bool _isLoaded = false;
        private readonly SemaphoreSlim _lock = new(1, 1);
        private readonly SemaphoreSlim _syncLock = new(1, 1);

        private RealtimeChannel? _streamsRealtimeChannel;
        private RealtimeChannel? _notesRealtimeChannel;
        private string? _realtimeUserId;
        private long _lastLocalPushMs = 0;
        private readonly Dictionary<int, string> _remoteSlotIdByNumber = new();
        private readonly object _remoteSlotLock = new();
        private CancellationTokenSource? _realtimeDebounceCts;
        private readonly IGotrueClient<User, Session>.AuthEventHandler? _authListener;
        private TagdosNavigationTarget? _pendingNavigation;

        public event EventHandler? DataChanged;
        public event EventHandler? PendingNavigationChanged;

        public TagdosNavigationTarget? PendingNavigation => _pendingNavigation;

        public void RequestNavigation(string? streamId = null, int? clusterIndex = null, string? pillId = null, bool openPillEditor = false)
        {
            if (string.IsNullOrWhiteSpace(streamId) && !clusterIndex.HasValue && string.IsNullOrWhiteSpace(pillId))
                return;

            _pendingNavigation = new TagdosNavigationTarget
            {
                StreamId = string.IsNullOrWhiteSpace(streamId) ? null : streamId,
                ClusterIndex = clusterIndex,
                PillId = string.IsNullOrWhiteSpace(pillId) ? null : pillId,
                OpenPillEditor = openPillEditor
            };
            PendingNavigationChanged?.Invoke(this, EventArgs.Empty);
        }

        public void HandleDeepLink(Uri uri)
        {
            if (uri == null) return;
            var query = !string.IsNullOrEmpty(uri.Query)
                ? uri.Query.TrimStart('?')
                : (!string.IsNullOrEmpty(uri.Fragment) ? uri.Fragment.TrimStart('#') : string.Empty);
            if (string.IsNullOrWhiteSpace(query)) return;

            string? streamId = null;
            int? clusterIndex = null;
            string? pillId = null;
            bool openEdit = false;

            foreach (var part in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var kv = part.Split('=', 2);
                if (kv.Length != 2) continue;
                var key = System.Net.WebUtility.UrlDecode(kv[0]);
                var val = System.Net.WebUtility.UrlDecode(kv[1]);
                if (key.Equals("streamId", StringComparison.OrdinalIgnoreCase))
                    streamId = val;
                else if (key.Equals("clusterIndex", StringComparison.OrdinalIgnoreCase) && int.TryParse(val, out int cIdx))
                    clusterIndex = cIdx;
                else if (key.Equals("pillId", StringComparison.OrdinalIgnoreCase))
                    pillId = val;
                else if (key.Equals("edit", StringComparison.OrdinalIgnoreCase) && val == "1")
                    openEdit = true;
            }

            if (!string.IsNullOrWhiteSpace(pillId))
                openEdit = true;

            RequestNavigation(streamId, clusterIndex, pillId, openEdit);
        }

        public TagdosNavigationTarget? ConsumePendingNavigation()
        {
            return Interlocked.Exchange(ref _pendingNavigation, null);
        }

        public async Task ReloadFromLocalAsync()
        {
            await _databaseService.InitializeAsync().ConfigureAwait(false);
            var conn = _databaseService.Connection;
            var localStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);
            if (localStreams.Count > 0)
            {
                RebuildStreamCacheFromLocal(localStreams);
                _isLoaded = true;
                DataChanged?.Invoke(this, EventArgs.Empty);

                var dirty = localStreams.Where(s => s.SyncedAtTicks == null && !IsUntouchedSeedStream(s)).ToList();
                if (dirty.Count > 0)
                {
                    _ = Task.Run(async () =>
                    {
                        foreach (var ls in dirty)
                        {
                            await PushSingleStreamAsync(ls).ConfigureAwait(false);
                        }
                    });
                }
            }
        }

        public TagdosService(
            IDatabaseService databaseService,
            Supabase.Client? supabaseClient = null,
            ILogger<TagdosService>? logger = null,
            ISupabaseSessionGuardian? sessionGuardian = null)
        {
            _databaseService = databaseService;
            _supabaseClient = supabaseClient;
            _logger = logger;
            _sessionGuardian = sessionGuardian;

            if (_supabaseClient != null)
            {
                _authListener = OnAuthStateChanged;
                _supabaseClient.Auth.AddStateChangedListener(_authListener);
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

        private async Task EnsureLoadedAsync()
        {
            if (_isLoaded) return;

            await _lock.WaitAsync().ConfigureAwait(false);
            try
            {
                if (_isLoaded) return;

                await _databaseService.InitializeAsync().ConfigureAwait(false);
                var conn = _databaseService.Connection;

                var localStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);
                if (localStreams.Count == 0)
                {
                    await SeedDefaultStreamsAsync().ConfigureAwait(false);
                    localStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);
                }

                RebuildStreamCacheFromLocal(localStreams);

                var localNotes = await conn.Table<LocalTagdoQuickNote>()
                    .OrderByDescending(n => n.IsPinned)
                    .ThenByDescending(n => n.UpdatedAtTicks)
                    .ToListAsync()
                    .ConfigureAwait(false);

                if (localNotes.Count == 0)
                {
                    await SeedDefaultNotesAsync().ConfigureAwait(false);
                    localNotes = await conn.Table<LocalTagdoQuickNote>()
                        .OrderByDescending(n => n.IsPinned)
                        .ThenByDescending(n => n.UpdatedAtTicks)
                        .ToListAsync()
                        .ConfigureAwait(false);
                }

                RebuildNoteCacheFromLocal(localNotes);

                _isLoaded = true;
            }
            finally
            {
                _lock.Release();
            }

            // Ensure Realtime subscription is active when already authenticated
            if (_supabaseClient?.Auth.CurrentUser != null && _realtimeUserId == null)
            {
                _ = Task.Run(() => SetupRealtimeAsync(forceRecreate: false));
            }
        }

        private void RebuildStreamCacheFromLocal(List<LocalTagdoStream> localStreams)
        {
            lock (_cachedStreams)
            {
                _cachedStreams.Clear();
                foreach (var ls in localStreams.OrderBy(s => s.OrderIndex))
                {
                    DateTime? reminder = ls.StreamReminderTicks.HasValue
                        ? new DateTime(ls.StreamReminderTicks.Value, DateTimeKind.Utc)
                        : null;
                    var parsed = TagdosParser.ParseStream(
                        ls.RawText,
                        ls.OrderIndex,
                        ls.Title,
                        reminder,
                        ls.ActiveMemos,
                        ls.AttachmentsJson,
                        ls.CustomTitle);
                    TagdosParser.ApplyClusterRemindersSpec(parsed, ls.ClusterRemindersSpec);
                    parsed.Id = ls.Id;
                    _cachedStreams.Add(parsed);
                }
            }
        }

        private void RebuildNoteCacheFromLocal(List<LocalTagdoQuickNote> localNotes)
        {
            lock (_cachedNotes)
            {
                _cachedNotes.Clear();
                foreach (var ln in localNotes.OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAtTicks))
                {
                    List<string> tags = new();
                    try
                    {
                        if (!string.IsNullOrWhiteSpace(ln.TagsJson))
                        {
                            tags = JsonSerializer.Deserialize<List<string>>(ln.TagsJson) ?? new();
                        }
                    }
                    catch { }

                    var createdTicks = ln.CreatedAtTicks > 0 ? ln.CreatedAtTicks : DateTime.UnixEpoch.Ticks;
                    var updatedTicks = ln.UpdatedAtTicks > 0 ? ln.UpdatedAtTicks : DateTime.UnixEpoch.Ticks;

                    _cachedNotes.Add(new TagDoQuickNote
                    {
                        Id = ln.Id,
                        UserId = ln.UserId,
                        Title = ln.Title,
                        Content = ln.Content,
                        IsPinned = ln.IsPinned,
                        Tags = tags,
                        CreatedAt = new DateTime(createdTicks, DateTimeKind.Utc),
                        UpdatedAt = new DateTime(updatedTicks, DateTimeKind.Utc)
                    });
                }
            }
        }

        private async Task SeedDefaultStreamsAsync()
        {
            var conn = _databaseService.Connection;
            var now = DateTime.UtcNow;

            foreach (var d in DefaultStreamSeeds)
            {
                var remDate = new DateTime(now.Year, now.Month, now.Day, d.hour, d.min, 0, DateTimeKind.Utc);
                var row = new LocalTagdoStream
                {
                    Id = Guid.NewGuid().ToString(),
                    OrderIndex = d.index,
                    Title = d.title,
                    RawText = d.raw,
                    StreamReminderTicks = remDate.Ticks,
                    ActiveMemos = string.Empty,
                    AttachmentsJson = "[]",
                    // Seed with UnixEpoch so real Supabase cloud data ALWAYS wins over untouched starter seeds!
                    UpdatedAtTicks = DateTime.UnixEpoch.Ticks,
                    SyncedAtTicks = null
                };
                await conn.InsertOrReplaceAsync(row).ConfigureAwait(false);
            }
        }

        private async Task SeedDefaultNotesAsync()
        {
            var conn = _databaseService.Connection;

            var n1 = new LocalTagdoQuickNote
            {
                Id = Guid.NewGuid().ToString(),
                Title = SeedNote1Title,
                Content = SeedNote1Content,
                IsPinned = true,
                TagsJson = "[\"#focus\",\"#executive\"]",
                CreatedAtTicks = DateTime.UnixEpoch.Ticks,
                UpdatedAtTicks = DateTime.UnixEpoch.Ticks,
                SyncedAtTicks = null
            };

            var n2 = new LocalTagdoQuickNote
            {
                Id = Guid.NewGuid().ToString(),
                Title = SeedNote2Title,
                Content = SeedNote2Content,
                IsPinned = false,
                TagsJson = "[\"#reading\",\"#dev\"]",
                CreatedAtTicks = DateTime.UnixEpoch.Ticks,
                UpdatedAtTicks = DateTime.UnixEpoch.Ticks,
                SyncedAtTicks = null
            };

            await conn.InsertOrReplaceAsync(n1).ConfigureAwait(false);
            await conn.InsertOrReplaceAsync(n2).ConfigureAwait(false);
        }

        private static bool IsUntouchedSeedStream(LocalTagdoStream ls)
        {
            if (ls.UpdatedAtTicks <= DateTime.UnixEpoch.Ticks)
                return true;

            if (ls.SyncedAtTicks == null &&
                string.IsNullOrEmpty(ls.CustomTitle) &&
                string.IsNullOrEmpty(ls.ActiveMemos))
            {
                foreach (var seed in DefaultStreamSeeds)
                {
                    if (ls.OrderIndex == seed.index &&
                        string.Equals(ls.Title, seed.title, StringComparison.Ordinal) &&
                        string.Equals(ls.RawText, seed.raw, StringComparison.Ordinal))
                    {
                        return true;
                    }
                }
            }

            return false;
        }

        private static bool IsUntouchedSeedNote(LocalTagdoQuickNote ln)
        {
            if (ln.UpdatedAtTicks <= DateTime.UnixEpoch.Ticks)
                return true;

            if (ln.SyncedAtTicks == null)
            {
                if (ln.Title == SeedNote1Title && ln.Content == SeedNote1Content)
                    return true;
                if (ln.Title == SeedNote2Title && ln.Content == SeedNote2Content)
                    return true;
            }

            return false;
        }

        public async Task<List<TagDoStream>> GetStreamsAsync()
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            lock (_cachedStreams)
            {
                return _cachedStreams.OrderBy(s => s.OrderIndex).ToList();
            }
        }

        public async Task<TagDoStream?> GetStreamByIndexAsync(int orderIndex)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            lock (_cachedStreams)
            {
                return _cachedStreams.FirstOrDefault(s => s.OrderIndex == orderIndex);
            }
        }

        public async Task SaveStreamAsync(TagDoStream stream)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            await SaveStreamInternalAsync(stream, notify: true, pushRemote: true).ConfigureAwait(false);
        }

        private async Task SaveStreamInternalAsync(TagDoStream stream, bool notify, bool pushRemote)
        {
            if (!string.IsNullOrWhiteSpace(stream.CustomTitle))
            {
                stream.CustomTitle = stream.CustomTitle.Trim();
                stream.Title = stream.CustomTitle;
            }
            else
            {
                stream.CustomTitle = null;
                if (string.IsNullOrWhiteSpace(stream.Title))
                {
                    stream.Title = TagdosParser.AutoDetectStreamTitle(stream.RawText, stream.OrderIndex);
                }
            }

            var conn = _databaseService.Connection;
            var local = new LocalTagdoStream
            {
                Id = stream.Id,
                OrderIndex = stream.OrderIndex,
                Title = stream.Title,
                CustomTitle = stream.CustomTitle,
                RawText = stream.RawText,
                StreamReminderTicks = stream.StreamReminder?.Ticks,
                ClusterRemindersSpec = TagdosParser.EncodeClusterSpecOnly(stream),
                ActiveMemos = stream.ActiveMemos ?? string.Empty,
                AttachmentsJson = string.IsNullOrWhiteSpace(stream.AttachmentsJson) ? "[]" : stream.AttachmentsJson,
                UpdatedAtTicks = DateTime.UtcNow.Ticks,
                SyncedAtTicks = null
            };

            await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);

            lock (_cachedStreams)
            {
                var idx = _cachedStreams.FindIndex(s => s.Id == stream.Id);
                if (idx >= 0)
                {
                    _cachedStreams[idx] = stream;
                }
                else
                {
                    _cachedStreams.Add(stream);
                }
                _cachedStreams.Sort((a, b) => a.OrderIndex.CompareTo(b.OrderIndex));
            }

            if (notify)
            {
                DataChanged?.Invoke(this, EventArgs.Empty);
            }
            if (pushRemote)
            {
                _ = Task.Run(() => PushSingleStreamAsync(local));
            }
        }

        public async Task UpdateStreamRawTextAsync(string streamId, string newRawText)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoStream? stream = null;
            lock (_cachedStreams)
            {
                stream = _cachedStreams.FirstOrDefault(s => s.Id == streamId);
            }

            if (stream != null)
            {
                var parsed = TagdosParser.ParseStream(newRawText, stream.OrderIndex, stream.Title, stream.StreamReminder, stream.ActiveMemos, stream.AttachmentsJson, stream.CustomTitle, stream);
                parsed.Id = stream.Id;
                if (string.IsNullOrWhiteSpace(parsed.CustomTitle))
                {
                    parsed.Title = TagdosParser.AutoDetectStreamTitle(parsed.RawText, parsed.OrderIndex);
                }
                await SaveStreamAsync(parsed).ConfigureAwait(false);
            }
        }

        public async Task UpdateStreamTitleAsync(string streamId, string? newTitle)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoStream? stream = null;
            lock (_cachedStreams)
            {
                stream = _cachedStreams.FirstOrDefault(s => s.Id == streamId);
            }

            if (stream != null)
            {
                var clean = newTitle?.Trim();
                if (!string.IsNullOrWhiteSpace(clean))
                {
                    stream.CustomTitle = clean;
                    stream.Title = clean;
                }
                else
                {
                    stream.CustomTitle = null;
                    stream.Title = TagdosParser.AutoDetectStreamTitle(stream.RawText, stream.OrderIndex);
                }
                await SaveStreamAsync(stream).ConfigureAwait(false);
            }
        }

        public async Task SetStreamReminderAsync(string streamId, DateTime? reminder)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoStream? stream = null;
            lock (_cachedStreams)
            {
                stream = _cachedStreams.FirstOrDefault(s => s.Id == streamId);
            }

            if (stream != null)
            {
                stream.StreamReminder = reminder;
                await SaveStreamAsync(stream).ConfigureAwait(false);
            }
        }

        public async Task SetClusterReminderAsync(string streamId, int clusterIndex, DateTime? reminder)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoStream? stream = null;
            lock (_cachedStreams)
            {
                stream = _cachedStreams.FirstOrDefault(s => s.Id == streamId);
            }

            if (stream != null && clusterIndex >= 0 && clusterIndex < stream.Clusters.Count)
            {
                stream.Clusters[clusterIndex].ClusterReminder = reminder;
                await SaveStreamAsync(stream).ConfigureAwait(false);
            }
        }

        public async Task UpdateStreamMemosAsync(string streamId, string memos, string attachmentsJson)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoStream? stream = null;
            lock (_cachedStreams)
            {
                stream = _cachedStreams.FirstOrDefault(s => s.Id == streamId);
            }

            if (stream != null)
            {
                stream.ActiveMemos = memos;
                stream.AttachmentsJson = attachmentsJson;
                await SaveStreamAsync(stream).ConfigureAwait(false);
            }
        }

        public async Task<TagDoStream> CreateStreamAsync(string? title = null, string rawText = "", string activeMemos = "")
        {
            await EnsureLoadedAsync().ConfigureAwait(false);

            int nextOrderIndex;
            lock (_cachedStreams)
            {
                nextOrderIndex = _cachedStreams.Count > 0 ? _cachedStreams.Max(s => s.OrderIndex) + 1 : 0;
            }

            var stream = BuildNewStream(title, rawText, activeMemos, nextOrderIndex);
            await SaveStreamAsync(stream).ConfigureAwait(false);
            return stream;
        }

        private static TagDoStream BuildNewStream(string? title, string rawText, string activeMemos, int orderIndex)
        {
            var cleanTitle = string.IsNullOrWhiteSpace(title) ? null : title.Trim();
            var resolvedTitle = cleanTitle ?? TagdosParser.AutoDetectStreamTitle(rawText, orderIndex);
            var stream = TagdosParser.ParseStream(
                rawText,
                orderIndex,
                resolvedTitle,
                null,
                activeMemos,
                "[]",
                cleanTitle);
            return stream;
        }

        public async Task MoveStreamAsync(int fromIndex, int toIndex)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            List<TagDoStream> reordered;
            lock (_cachedStreams)
            {
                var ordered = _cachedStreams.OrderBy(s => s.OrderIndex).ToList();
                if (fromIndex < 0 || fromIndex >= ordered.Count || toIndex < 0 || toIndex >= ordered.Count || fromIndex == toIndex)
                    return;
                var item = ordered[fromIndex];
                ordered.RemoveAt(fromIndex);
                ordered.Insert(toIndex, item);
                reordered = ordered;
            }
            await ApplyReorderedStreamsAsync(reordered).ConfigureAwait(false);
        }

        public async Task ReorderStreamsAsync(List<string> orderedIds)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            List<TagDoStream> reordered;
            lock (_cachedStreams)
            {
                var current = _cachedStreams.OrderBy(s => s.OrderIndex).ToList();
                var byId = current.ToDictionary(s => s.Id, s => s);
                reordered = new List<TagDoStream>();
                foreach (var id in orderedIds)
                {
                    if (byId.Remove(id, out var found))
                        reordered.Add(found);
                }
                foreach (var s in current)
                {
                    if (byId.ContainsKey(s.Id))
                        reordered.Add(s);
                }
                if (reordered.Select(s => s.Id).SequenceEqual(current.Select(s => s.Id)))
                    return;
            }
            await ApplyReorderedStreamsAsync(reordered).ConfigureAwait(false);
        }

        private async Task ApplyReorderedStreamsAsync(List<TagDoStream> reordered)
        {
            var conn = _databaseService.Connection;
            var localsToPush = new List<LocalTagdoStream>();
            var nowTicks = DateTime.UtcNow.Ticks;

            for (int i = 0; i < reordered.Count; i++)
            {
                var s = reordered[i];
                s.OrderIndex = i;
                if (!string.IsNullOrWhiteSpace(s.CustomTitle))
                {
                    s.Title = s.CustomTitle.Trim();
                }
                else
                {
                    s.CustomTitle = null;
                    s.Title = TagdosParser.AutoDetectStreamTitle(s.RawText, i);
                }

                var local = new LocalTagdoStream
                {
                    Id = s.Id,
                    OrderIndex = i,
                    Title = s.Title,
                    CustomTitle = s.CustomTitle,
                    RawText = s.RawText,
                    StreamReminderTicks = s.StreamReminder?.Ticks,
                    ClusterRemindersSpec = TagdosParser.EncodeClusterSpecOnly(s),
                    ActiveMemos = s.ActiveMemos ?? string.Empty,
                    AttachmentsJson = string.IsNullOrWhiteSpace(s.AttachmentsJson) ? "[]" : s.AttachmentsJson,
                    UpdatedAtTicks = nowTicks,
                    SyncedAtTicks = null
                };
                await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);
                localsToPush.Add(local);
            }

            lock (_cachedStreams)
            {
                _cachedStreams.Clear();
                _cachedStreams.AddRange(reordered);
            }

            DataChanged?.Invoke(this, EventArgs.Empty);

            _ = Task.Run(async () =>
            {
                foreach (var ls in localsToPush)
                {
                    await PushSingleStreamAsync(ls).ConfigureAwait(false);
                }
            });
        }

        public async Task DeleteStreamAsync(string streamId)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);

            List<TagDoStream> remaining;
            lock (_cachedStreams)
            {
                if (_cachedStreams.Count <= 1) return;
                remaining = _cachedStreams.Where(s => s.Id != streamId).OrderBy(s => s.OrderIndex).ToList();
                if (remaining.Count == _cachedStreams.Count) return;
            }

            var conn = _databaseService.Connection;
            await conn.DeleteAsync<LocalTagdoStream>(streamId).ConfigureAwait(false);

            var reindexedLocals = new List<LocalTagdoStream>();
            var nowTicks = DateTime.UtcNow.Ticks;

            for (int i = 0; i < remaining.Count; i++)
            {
                var s = remaining[i];
                s.OrderIndex = i;
                if (string.IsNullOrWhiteSpace(s.CustomTitle))
                {
                    s.Title = TagdosParser.AutoDetectStreamTitle(s.RawText, i);
                }
                var local = new LocalTagdoStream
                {
                    Id = s.Id,
                    OrderIndex = i,
                    Title = s.Title,
                    CustomTitle = s.CustomTitle,
                    RawText = s.RawText,
                    StreamReminderTicks = s.StreamReminder?.Ticks,
                    ClusterRemindersSpec = TagdosParser.EncodeClusterSpecOnly(s),
                    ActiveMemos = s.ActiveMemos ?? string.Empty,
                    AttachmentsJson = string.IsNullOrWhiteSpace(s.AttachmentsJson) ? "[]" : s.AttachmentsJson,
                    UpdatedAtTicks = nowTicks,
                    SyncedAtTicks = null
                };
                await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);
                reindexedLocals.Add(local);
            }

            lock (_cachedStreams)
            {
                _cachedStreams.Clear();
                _cachedStreams.AddRange(remaining);
            }

            int newCount = remaining.Count;
            lock (_remoteSlotLock)
            {
                foreach (var overflowKey in _remoteSlotIdByNumber.Keys.Where(k => k > newCount).ToList())
                {
                    _remoteSlotIdByNumber.Remove(overflowKey);
                }
            }

            DataChanged?.Invoke(this, EventArgs.Empty);

            _ = Task.Run(async () =>
            {
                if (_supabaseClient != null)
                {
                    try
                    {
                        if (_sessionGuardian != null)
                            await _sessionGuardian.EnsureValidSessionAsync().ConfigureAwait(false);

                        var userId = _supabaseClient.Auth.CurrentUser?.Id;
                        if (!string.IsNullOrEmpty(userId))
                        {
                            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                            await ExecuteWithAuthAsync(async () =>
                            {
                                await _supabaseClient.From<RemoteTagdoStream>()
                                    .Where(x => x.UserId == userId)
                                    .Filter("stream_number", Supabase.Postgrest.Constants.Operator.GreaterThan, newCount)
                                    .Delete(new Supabase.Postgrest.QueryOptions { Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal })
                                    .ConfigureAwait(false);
                                return true;
                            }, "Tagdos.DeleteStreamOverflow").ConfigureAwait(false);
                        }
                    }
                    catch (Exception ex)
                    {
                        SupabaseSessionGuardian.LogGuardian($"[TagdosService] Delete overflow streams failed: {ex.Message}");
                    }
                }

                foreach (var ls in reindexedLocals)
                {
                    await PushSingleStreamAsync(ls).ConfigureAwait(false);
                }
            });
        }

        public async Task<string?> ImportExternalTaskBatchAsync(List<TagdosTaskImportItem> items)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            if (items == null || items.Count == 0) return null;

            string? firstAffectedId = null;
            var touchedStreams = new List<TagDoStream>();

            // 1. Replace targets
            var replaceOrder = new List<string>();
            var replaceGroups = new Dictionary<string, List<TagdosTaskImportItem>>();
            foreach (var item in items)
            {
                if (item.Mode == TagdosTaskImportMode.Replace && !string.IsNullOrEmpty(item.TargetStreamId))
                {
                    if (!replaceGroups.ContainsKey(item.TargetStreamId)) replaceOrder.Add(item.TargetStreamId);
                    if (!replaceGroups.TryGetValue(item.TargetStreamId, out var list))
                    {
                        list = new List<TagdosTaskImportItem>();
                        replaceGroups[item.TargetStreamId] = list;
                    }
                    list.Add(item);
                }
            }

            foreach (var streamId in replaceOrder)
            {
                TagDoStream? existing;
                lock (_cachedStreams) { existing = _cachedStreams.FirstOrDefault(s => s.Id == streamId); }
                if (existing == null) continue;

                var group = replaceGroups[streamId];
                var combinedDsl = CombineImportedDslChunks(group.Select(g => g.DslOrTag).ToList());
                var combinedMemos = string.Join("\n", group.Select(g => g.MemoLine?.Trim() ?? "").Where(m => !string.IsNullOrEmpty(m)));

                var updated = TagdosParser.ParseStream(
                    combinedDsl,
                    existing.OrderIndex,
                    existing.Title,
                    existing.StreamReminder,
                    combinedMemos,
                    existing.AttachmentsJson,
                    existing.CustomTitle);
                updated.Id = existing.Id;
                if (string.IsNullOrWhiteSpace(updated.CustomTitle))
                {
                    updated.Title = TagdosParser.AutoDetectStreamTitle(updated.RawText, updated.OrderIndex);
                }
                else
                {
                    updated.CustomTitle = updated.CustomTitle.Trim();
                    updated.Title = updated.CustomTitle;
                }

                await SaveStreamInternalAsync(updated, notify: false, pushRemote: false).ConfigureAwait(false);
                touchedStreams.Add(updated);
                firstAffectedId ??= updated.Id;
            }

            // 2. Append targets
            var appendOrder = new List<string>();
            var appendGroups = new Dictionary<string, List<TagdosTaskImportItem>>();
            foreach (var item in items)
            {
                if (item.Mode == TagdosTaskImportMode.Append && !string.IsNullOrEmpty(item.TargetStreamId))
                {
                    if (!appendGroups.ContainsKey(item.TargetStreamId)) appendOrder.Add(item.TargetStreamId);
                    if (!appendGroups.TryGetValue(item.TargetStreamId, out var list))
                    {
                        list = new List<TagdosTaskImportItem>();
                        appendGroups[item.TargetStreamId] = list;
                    }
                    list.Add(item);
                }
            }

            foreach (var streamId in appendOrder)
            {
                TagDoStream? existing;
                lock (_cachedStreams) { existing = _cachedStreams.FirstOrDefault(s => s.Id == streamId); }
                if (existing == null) continue;

                var group = appendGroups[streamId];
                var combinedDsl = CombineImportedDslChunks(group.Select(g => g.DslOrTag).ToList());
                var combinedMemos = string.Join("\n", group.Select(g => g.MemoLine?.Trim() ?? "").Where(m => !string.IsNullOrEmpty(m)));

                var existingRaw = (existing.RawText ?? string.Empty).Trim();
                var newRaw = string.IsNullOrEmpty(existingRaw)
                    ? combinedDsl
                    : (string.IsNullOrEmpty(combinedDsl) ? existingRaw : $"{existingRaw} & {combinedDsl}");
                var existingMemos = (existing.ActiveMemos ?? string.Empty).Trim();
                var mergedMemos = string.IsNullOrEmpty(existingMemos)
                    ? combinedMemos
                    : (string.IsNullOrEmpty(combinedMemos) ? existingMemos : $"{existingMemos}\n{combinedMemos}");

                var updated = TagdosParser.ParseStream(
                    newRaw,
                    existing.OrderIndex,
                    existing.Title,
                    existing.StreamReminder,
                    mergedMemos,
                    existing.AttachmentsJson,
                    existing.CustomTitle,
                    existing);
                updated.Id = existing.Id;
                if (string.IsNullOrWhiteSpace(updated.CustomTitle))
                {
                    updated.Title = TagdosParser.AutoDetectStreamTitle(updated.RawText, updated.OrderIndex);
                }
                else
                {
                    updated.CustomTitle = updated.CustomTitle.Trim();
                    updated.Title = updated.CustomTitle;
                }

                await SaveStreamInternalAsync(updated, notify: false, pushRemote: false).ConfigureAwait(false);
                if (!touchedStreams.Any(t => t.Id == updated.Id)) touchedStreams.Add(updated);
                else touchedStreams[touchedStreams.FindIndex(t => t.Id == updated.Id)] = updated;
                firstAffectedId ??= updated.Id;
            }

            // 3. New Stream targets
            var namedOrder = new List<string>();
            var namedGroups = new Dictionary<string, List<TagdosTaskImportItem>>();
            var unnamedItems = new List<TagdosTaskImportItem>();
            foreach (var item in items)
            {
                if (item.Mode == TagdosTaskImportMode.NewStream)
                {
                    var cleanTitle = item.NewStreamTitle?.Trim() ?? string.Empty;
                    if (string.IsNullOrEmpty(cleanTitle))
                    {
                        unnamedItems.Add(item);
                    }
                    else
                    {
                        if (!namedGroups.ContainsKey(cleanTitle)) namedOrder.Add(cleanTitle);
                        if (!namedGroups.TryGetValue(cleanTitle, out var list))
                        {
                            list = new List<TagdosTaskImportItem>();
                            namedGroups[cleanTitle] = list;
                        }
                        list.Add(item);
                    }
                }
            }

            foreach (var titleKey in namedOrder)
            {
                var group = namedGroups[titleKey];
                var combinedDsl = CombineImportedDslChunks(group.Select(g => g.DslOrTag).ToList());
                var combinedMemos = string.Join("\n", group.Select(g => g.MemoLine?.Trim() ?? "").Where(m => !string.IsNullOrEmpty(m)));
                int nextIdx;
                lock (_cachedStreams) { nextIdx = _cachedStreams.Count > 0 ? _cachedStreams.Max(s => s.OrderIndex) + 1 : 0; }
                var created = BuildNewStream(titleKey, combinedDsl, combinedMemos, nextIdx);
                await SaveStreamInternalAsync(created, notify: false, pushRemote: false).ConfigureAwait(false);
                touchedStreams.Add(created);
                firstAffectedId ??= created.Id;
            }

            foreach (var item in unnamedItems)
            {
                var combinedDsl = CombineImportedDslChunks(new List<string> { item.DslOrTag });
                var memo = item.MemoLine?.Trim() ?? string.Empty;
                int nextIdx;
                lock (_cachedStreams) { nextIdx = _cachedStreams.Count > 0 ? _cachedStreams.Max(s => s.OrderIndex) + 1 : 0; }
                var created = BuildNewStream(null, combinedDsl, memo, nextIdx);
                await SaveStreamInternalAsync(created, notify: false, pushRemote: false).ConfigureAwait(false);
                touchedStreams.Add(created);
                firstAffectedId ??= created.Id;
            }

            if (touchedStreams.Count > 0)
            {
                DataChanged?.Invoke(this, EventArgs.Empty);
                var conn = _databaseService.Connection;
                var allIds = touchedStreams.Select(t => t.Id).ToHashSet();
                _ = Task.Run(async () =>
                {
                    var allLocals = await conn.Table<LocalTagdoStream>().ToListAsync().ConfigureAwait(false);
                    foreach (var ls in allLocals.Where(l => allIds.Contains(l.Id)))
                    {
                        await PushSingleStreamAsync(ls).ConfigureAwait(false);
                    }
                });
            }

            return firstAffectedId;
        }

        public async Task<TagDoStream> ImportExternalTasksAsync(
            string mode,
            string? targetStreamId,
            string? newStreamTitle,
            List<string> rawDslChunks,
            List<string> memoLines)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);

            string combinedDsl = CombineImportedDslChunks(rawDslChunks);
            string combinedMemos = string.Join("\n", memoLines.Select(m => m.Trim()).Where(m => !string.IsNullOrEmpty(m)));

            TagDoStream? target = null;
            lock (_cachedStreams)
            {
                target = _cachedStreams.FirstOrDefault(s => s.Id == targetStreamId);
            }

            TagdosTaskImportMode mappedMode = string.Equals(mode, "new", StringComparison.OrdinalIgnoreCase) || target == null
                ? TagdosTaskImportMode.NewStream
                : (string.Equals(mode, "replace", StringComparison.OrdinalIgnoreCase) ? TagdosTaskImportMode.Replace : TagdosTaskImportMode.Append);

            var id = await ImportExternalTaskBatchAsync(new List<TagdosTaskImportItem>
            {
                new TagdosTaskImportItem
                {
                    DslOrTag = combinedDsl,
                    MemoLine = string.IsNullOrEmpty(combinedMemos) ? null : combinedMemos,
                    Mode = mappedMode,
                    TargetStreamId = target?.Id,
                    NewStreamTitle = newStreamTitle
                }
            }).ConfigureAwait(false);

            lock (_cachedStreams)
            {
                return _cachedStreams.FirstOrDefault(s => s.Id == id)
                    ?? _cachedStreams.OrderByDescending(s => s.OrderIndex).First();
            }
        }

        private static string CombineImportedDslChunks(List<string> chunks)
        {
            var cleaned = chunks.Select(c => (c ?? string.Empty).Trim()).Where(c => !string.IsNullOrEmpty(c)).ToList();
            if (cleaned.Count == 0) return string.Empty;

            var singleTags = new List<string>();
            var complexClusters = new List<string>();
            foreach (var chunk in cleaned)
            {
                if (chunk.Contains('&') || chunk.Contains('/'))
                    complexClusters.Add(chunk);
                else
                    singleTags.Add(chunk);
            }

            var parts = new List<string>();
            if (singleTags.Count > 0)
                parts.Add(string.Join("/", singleTags));
            parts.AddRange(complexClusters);
            return string.Join(" & ", parts);
        }

        public async Task<List<TagDoQuickNote>> GetQuickNotesAsync()
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            lock (_cachedNotes)
            {
                return _cachedNotes.OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAt).ToList();
            }
        }

        public async Task<TagDoQuickNote> CreateQuickNoteAsync(string title, string content, bool isPinned = false)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);

            var userId = _supabaseClient?.Auth.CurrentUser?.Id;
            var note = new TagDoQuickNote
            {
                Id = Guid.NewGuid().ToString(),
                UserId = userId,
                Title = title,
                Content = content,
                IsPinned = isPinned,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            var local = new LocalTagdoQuickNote
            {
                Id = note.Id,
                UserId = userId,
                Title = note.Title,
                Content = note.Content,
                IsPinned = note.IsPinned,
                TagsJson = "[]",
                CreatedAtTicks = note.CreatedAt.Ticks,
                UpdatedAtTicks = note.UpdatedAt.Ticks,
                SyncedAtTicks = null
            };

            var conn = _databaseService.Connection;
            await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);

            lock (_cachedNotes)
            {
                _cachedNotes.Insert(0, note);
            }

            DataChanged?.Invoke(this, EventArgs.Empty);
            _ = Task.Run(() => PushSingleQuickNoteAsync(local));
            return note;
        }

        public async Task UpdateQuickNoteAsync(TagDoQuickNote note)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);

            note.UpdatedAt = DateTime.UtcNow;
            var local = new LocalTagdoQuickNote
            {
                Id = note.Id,
                UserId = note.UserId ?? _supabaseClient?.Auth.CurrentUser?.Id,
                Title = note.Title,
                Content = note.Content,
                IsPinned = note.IsPinned,
                TagsJson = JsonSerializer.Serialize(note.Tags ?? new List<string>()),
                CreatedAtTicks = note.CreatedAt.Ticks,
                UpdatedAtTicks = note.UpdatedAt.Ticks,
                SyncedAtTicks = null
            };

            var conn = _databaseService.Connection;
            await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);

            lock (_cachedNotes)
            {
                var idx = _cachedNotes.FindIndex(n => n.Id == note.Id);
                if (idx >= 0)
                {
                    _cachedNotes[idx] = note;
                }
            }

            DataChanged?.Invoke(this, EventArgs.Empty);
            _ = Task.Run(() => PushSingleQuickNoteAsync(local));
        }

        public async Task TogglePinQuickNoteAsync(string noteId)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoQuickNote? note = null;
            lock (_cachedNotes)
            {
                note = _cachedNotes.FirstOrDefault(n => n.Id == noteId);
            }

            if (note != null)
            {
                note.IsPinned = !note.IsPinned;
                await UpdateQuickNoteAsync(note).ConfigureAwait(false);
            }
        }

        public async Task DeleteQuickNoteAsync(string noteId)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);

            var conn = _databaseService.Connection;
            await conn.Table<LocalTagdoQuickNote>().DeleteAsync(n => n.Id == noteId).ConfigureAwait(false);

            lock (_cachedNotes)
            {
                _cachedNotes.RemoveAll(n => n.Id == noteId);
            }

            DataChanged?.Invoke(this, EventArgs.Empty);

            if (_supabaseClient != null)
            {
                _ = Task.Run(async () =>
                {
                    try
                    {
                        if (_sessionGuardian != null)
                            await _sessionGuardian.EnsureValidSessionAsync().ConfigureAwait(false);

                        var userId = _supabaseClient.Auth.CurrentUser?.Id;
                        if (!string.IsNullOrEmpty(userId))
                        {
                            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                            await ExecuteWithAuthAsync(async () =>
                            {
                                await _supabaseClient.From<RemoteTagdoQuickNote>()
                                    .Where(x => x.Id == noteId && x.UserId == userId)
                                    .Delete(new Supabase.Postgrest.QueryOptions { Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal })
                                    .ConfigureAwait(false);
                                return true;
                            }, "Tagdos.DeleteQuickNote").ConfigureAwait(false);
                            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                        }
                    }
                    catch (Exception ex)
                    {
                        SupabaseSessionGuardian.LogGuardian($"[TagdosService] Remote delete quick note failed ({noteId}): {ex.Message}");
                    }
                });
            }
        }

        public async Task SyncWithRemoteAsync()
        {
            if (_supabaseClient == null)
                return;

            await EnsureLoadedAsync().ConfigureAwait(false);

            if (_sessionGuardian != null)
            {
                await _sessionGuardian.EnsureValidSessionAsync().ConfigureAwait(false);
            }

            var userId = _supabaseClient.Auth.CurrentUser?.Id;
            if (string.IsNullOrEmpty(userId))
                return;

            await _syncLock.WaitAsync().ConfigureAwait(false);
            bool anyLocalUpdatedFromRemote = false;

            try
            {
                var conn = _databaseService.Connection;

                // ── 1. Pull & Merge Streams (tagdos_streams) ─────────────────────────
                var remoteStreamResp = await ExecuteWithAuthAsync(
                    () => _supabaseClient.From<RemoteTagdoStream>().Where(x => x.UserId == userId).Get(),
                    "Tagdos.PullStreams").ConfigureAwait(false);

                var remoteStreams = remoteStreamResp.Models ?? new List<RemoteTagdoStream>();
                var localStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);

                if (remoteStreams.Count > 0)
                {
                    lock (_remoteSlotLock)
                    {
                        _remoteSlotIdByNumber.Clear();
                        foreach (var r in remoteStreams)
                        {
                            if (!string.IsNullOrWhiteSpace(r.Id))
                                _remoteSlotIdByNumber[r.StreamNumber] = r.Id;
                        }
                    }

                    var remoteStreamNumbers = remoteStreams.Select(r => r.StreamNumber).ToHashSet();
                    int maxRemoteNum = remoteStreams.Max(r => r.StreamNumber);

                    foreach (var orphanLocal in localStreams.ToList())
                    {
                        int localNum = orphanLocal.OrderIndex + 1;
                        // Only prune clean, previously synced overflow rows deleted remotely; never drop dirty local rows
                        if (orphanLocal.SyncedAtTicks != null && localNum > maxRemoteNum && !IsUntouchedSeedStream(orphanLocal))
                        {
                            await conn.DeleteAsync(orphanLocal).ConfigureAwait(false);
                            localStreams.Remove(orphanLocal);
                            anyLocalUpdatedFromRemote = true;
                        }
                    }

                    foreach (var remote in remoteStreams)
                    {
                        int orderIdx = Math.Max(0, remote.StreamNumber - 1);
                        var existing = localStreams.FirstOrDefault(s => s.OrderIndex == orderIdx);
                        var remoteUpdatedUtc = remote.UpdatedAt.Kind == DateTimeKind.Utc
                            ? remote.UpdatedAt
                            : remote.UpdatedAt.ToUniversalTime();

                        bool localIsSeed = existing == null || IsUntouchedSeedStream(existing);
                        bool localIsDirty = existing != null && existing.SyncedAtTicks == null && !localIsSeed;
                        var localUpdatedUtc = existing != null
                            ? new DateTime(existing.UpdatedAtTicks, DateTimeKind.Utc)
                            : DateTime.MinValue;

                        // Remote wins if local is untouched seed, or local is already synced and remote is newer/different,
                        // or both are modified and remote is strictly newer.
                        bool adoptRemote = existing == null
                            || localIsSeed
                            || (!localIsDirty && (remoteUpdatedUtc > localUpdatedUtc || existing.RawText != remote.RawSyntax || existing.DisplayNameCheck(remote.Title)))
                            || (localIsDirty && remoteUpdatedUtc > localUpdatedUtc);

                        if (adoptRemote)
                        {
                            if (existing != null && !string.Equals(existing.Id, remote.Id, StringComparison.OrdinalIgnoreCase))
                            {
                                await conn.DeleteAsync(existing).ConfigureAwait(false);
                            }

                            var (reminderTicks, clusterSpec) = TagdosParser.DecodeReminderSpec(remote.ReminderTime);
                            var attachmentsJson = remote.Attachments != null
                                ? remote.Attachments.ToString(Newtonsoft.Json.Formatting.None)
                                : "[]";

                            var autoTitle = TagdosParser.AutoDetectStreamTitle(remote.RawSyntax ?? string.Empty, orderIdx);
                            var trimmedRemoteTitle = (remote.Title ?? string.Empty).Trim();
                            var customTitle = !string.IsNullOrWhiteSpace(trimmedRemoteTitle) && !string.Equals(trimmedRemoteTitle, autoTitle, StringComparison.Ordinal)
                                ? trimmedRemoteTitle
                                : null;

                            var updatedLocal = new LocalTagdoStream
                            {
                                Id = remote.Id,
                                OrderIndex = orderIdx,
                                Title = !string.IsNullOrWhiteSpace(trimmedRemoteTitle) ? trimmedRemoteTitle : autoTitle,
                                CustomTitle = customTitle,
                                RawText = remote.RawSyntax ?? string.Empty,
                                StreamReminderTicks = reminderTicks,
                                ClusterRemindersSpec = clusterSpec,
                                ActiveMemos = remote.ActiveMemos ?? string.Empty,
                                AttachmentsJson = string.IsNullOrWhiteSpace(attachmentsJson) ? "[]" : attachmentsJson,
                                UpdatedAtTicks = remoteUpdatedUtc.Ticks,
                                SyncedAtTicks = DateTime.UtcNow.Ticks
                            };

                            await conn.InsertOrReplaceAsync(updatedLocal).ConfigureAwait(false);
                            anyLocalUpdatedFromRemote = true;
                        }
                    }
                }

                // Refresh localStreams snapshot and push dirty / missing-remote (or initial when remote is completely empty)
                localStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);
                var existingRemoteNums = remoteStreams.Select(r => r.StreamNumber).ToHashSet();
                var streamsToPush = remoteStreams.Count == 0
                    ? localStreams
                    : localStreams.Where(s => (s.SyncedAtTicks == null && !IsUntouchedSeedStream(s)) || !existingRemoteNums.Contains(s.OrderIndex + 1)).ToList();

                foreach (var ls in streamsToPush)
                {
                    await UpsertLocalStreamToRemoteAsync(ls, userId).ConfigureAwait(false);
                }

                // ── 2. Pull & Merge Quick Notes (tagdos_quick_notes) ─────────────────
                var remoteNotesResp = await ExecuteWithAuthAsync(
                    () => _supabaseClient.From<RemoteTagdoQuickNote>()
                        .Where(x => x.UserId == userId)
                        .Order("updated_at", Supabase.Postgrest.Constants.Ordering.Descending)
                        .Get(),
                    "Tagdos.PullQuickNotes").ConfigureAwait(false);

                var remoteNotes = remoteNotesResp.Models ?? new List<RemoteTagdoQuickNote>();
                var localNotes = await conn.Table<LocalTagdoQuickNote>().ToListAsync().ConfigureAwait(false);

                if (remoteNotes.Count > 0)
                {
                    // Remove untouched starter seed notes once real cloud notes exist
                    foreach (var seedNote in localNotes.Where(IsUntouchedSeedNote).ToList())
                    {
                        await conn.DeleteAsync(seedNote).ConfigureAwait(false);
                        localNotes.Remove(seedNote);
                        anyLocalUpdatedFromRemote = true;
                    }

                    var remoteIds = remoteNotes.Select(r => r.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);

                    // Clean up previously synced notes that were deleted on another device
                    foreach (var orphan in localNotes.Where(ln => ln.SyncedAtTicks != null && !remoteIds.Contains(ln.Id)).ToList())
                    {
                        await conn.DeleteAsync(orphan).ConfigureAwait(false);
                        localNotes.Remove(orphan);
                        anyLocalUpdatedFromRemote = true;
                    }

                    foreach (var rNote in remoteNotes)
                    {
                        var existing = localNotes.FirstOrDefault(n => string.Equals(n.Id, rNote.Id, StringComparison.OrdinalIgnoreCase));
                        var rUpdatedUtc = rNote.UpdatedAt.Kind == DateTimeKind.Utc ? rNote.UpdatedAt : rNote.UpdatedAt.ToUniversalTime();
                        var rCreatedUtc = rNote.CreatedAt.Kind == DateTimeKind.Utc ? rNote.CreatedAt : rNote.CreatedAt.ToUniversalTime();

                        bool localDirty = existing != null && existing.SyncedAtTicks == null && !IsUntouchedSeedNote(existing);
                        var localUpdatedUtc = existing != null
                            ? new DateTime(existing.UpdatedAtTicks, DateTimeKind.Utc)
                            : DateTime.MinValue;

                        bool adoptRemote = existing == null
                            || (!localDirty && (rUpdatedUtc > localUpdatedUtc || existing.Title != rNote.Title || existing.Content != rNote.Content || existing.IsPinned != rNote.IsPinned))
                            || (localDirty && rUpdatedUtc > localUpdatedUtc);

                        if (adoptRemote)
                        {
                            var localRow = new LocalTagdoQuickNote
                            {
                                Id = rNote.Id,
                                UserId = rNote.UserId ?? userId,
                                Title = rNote.Title ?? string.Empty,
                                Content = rNote.Content ?? string.Empty,
                                IsPinned = rNote.IsPinned,
                                TagsJson = JsonSerializer.Serialize(rNote.Tags ?? new List<string>()),
                                CreatedAtTicks = rCreatedUtc.Ticks,
                                UpdatedAtTicks = rUpdatedUtc.Ticks,
                                SyncedAtTicks = DateTime.UtcNow.Ticks
                            };
                            await conn.InsertOrReplaceAsync(localRow).ConfigureAwait(false);
                            anyLocalUpdatedFromRemote = true;
                        }
                    }
                }

                // Push user-authored dirty notes (never push untouched seed notes!)
                localNotes = await conn.Table<LocalTagdoQuickNote>().ToListAsync().ConfigureAwait(false);
                var dirtyNotes = localNotes.Where(n => n.SyncedAtTicks == null && !IsUntouchedSeedNote(n)).ToList();

                foreach (var dn in dirtyNotes)
                {
                    List<string> tags = new();
                    try
                    {
                        if (!string.IsNullOrWhiteSpace(dn.TagsJson))
                            tags = JsonSerializer.Deserialize<List<string>>(dn.TagsJson) ?? new();
                    }
                    catch { }

                    var createdUtc = dn.CreatedAtTicks > DateTime.UnixEpoch.Ticks
                        ? new DateTime(dn.CreatedAtTicks, DateTimeKind.Utc)
                        : DateTime.UtcNow;
                    var updatedUtc = dn.UpdatedAtTicks > DateTime.UnixEpoch.Ticks
                        ? new DateTime(dn.UpdatedAtTicks, DateTimeKind.Utc)
                        : DateTime.UtcNow;

                    var remoteNote = new RemoteTagdoQuickNote
                    {
                        Id = Guid.TryParse(dn.Id, out _) ? dn.Id : Guid.NewGuid().ToString(),
                        UserId = userId,
                        Title = dn.Title ?? string.Empty,
                        Content = dn.Content ?? string.Empty,
                        IsPinned = dn.IsPinned,
                        Tags = tags,
                        CreatedAt = createdUtc,
                        UpdatedAt = updatedUtc
                    };

                    Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                    await ExecuteWithAuthAsync(
                        () => _supabaseClient.From<RemoteTagdoQuickNote>().Upsert(
                            remoteNote,
                            new Supabase.Postgrest.QueryOptions { Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal }),
                        $"Tagdos.PushQuickNote({dn.Id})").ConfigureAwait(false);
                    Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

                    dn.Id = remoteNote.Id;
                    dn.UserId = userId;
                    dn.SyncedAtTicks = DateTime.UtcNow.Ticks;
                    await conn.InsertOrReplaceAsync(dn).ConfigureAwait(false);
                }

                if (anyLocalUpdatedFromRemote)
                {
                    var finalStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);
                    var finalNotes = await conn.Table<LocalTagdoQuickNote>()
                        .OrderByDescending(n => n.IsPinned)
                        .ThenByDescending(n => n.UpdatedAtTicks)
                        .ToListAsync()
                        .ConfigureAwait(false);

                    RebuildStreamCacheFromLocal(finalStreams);
                    RebuildNoteCacheFromLocal(finalNotes);

                    DataChanged?.Invoke(this, EventArgs.Empty);
                }

                if (_realtimeUserId != userId)
                {
                    _ = Task.Run(() => SetupRealtimeAsync(forceRecreate: false));
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning("Tagdos remote sync failed: {Message}", ex.Message);
                SupabaseSessionGuardian.LogGuardian($"[TagdosService] SyncWithRemoteAsync error: {ex.GetType().Name}: {ex.Message}");
            }
            finally
            {
                _syncLock.Release();
            }
        }

        private async Task SetupRealtimeAsync(bool forceRecreate)
        {
            if (_supabaseClient == null) return;
            var userId = _supabaseClient.Auth.CurrentUser?.Id;
            if (string.IsNullOrEmpty(userId)) return;

            if (!forceRecreate && _realtimeUserId == userId && _streamsRealtimeChannel != null)
                return;

            try
            {
                if (_sessionGuardian != null)
                {
                    var connected = await _sessionGuardian.EnsureRealtimeConnectedAsync().ConfigureAwait(false);
                    if (!connected)
                        return;
                }

                if (_streamsRealtimeChannel != null)
                {
                    try { _streamsRealtimeChannel.Unsubscribe(); } catch { }
                    _streamsRealtimeChannel = null;
                }
                if (_notesRealtimeChannel != null)
                {
                    try { _notesRealtimeChannel.Unsubscribe(); } catch { }
                    _notesRealtimeChannel = null;
                }

                var subStreamsTask = _supabaseClient.From<RemoteTagdoStream>()
                    .On(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, (_, _) =>
                    {
                        ScheduleDebouncedRemoteSync();
                    });
                if (await Task.WhenAny(subStreamsTask, Task.Delay(5000)).ConfigureAwait(false) == subStreamsTask)
                {
                    _streamsRealtimeChannel = await subStreamsTask.ConfigureAwait(false);
                }

                var subNotesTask = _supabaseClient.From<RemoteTagdoQuickNote>()
                    .On(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, (_, _) =>
                    {
                        ScheduleDebouncedRemoteSync();
                    });
                if (await Task.WhenAny(subNotesTask, Task.Delay(5000)).ConfigureAwait(false) == subNotesTask)
                {
                    _notesRealtimeChannel = await subNotesTask.ConfigureAwait(false);
                }

                if (_streamsRealtimeChannel != null || _notesRealtimeChannel != null)
                {
                    _realtimeUserId = userId;
                    SupabaseSessionGuardian.LogGuardian($"[TagdosService] Subscribed to Realtime for tagdos_streams & tagdos_quick_notes (user={userId}).");
                }
            }
            catch (Exception ex)
            {
                SupabaseSessionGuardian.LogGuardian($"[TagdosService] Realtime setup warning: {ex.Message}");
            }
        }

        private void ScheduleDebouncedRemoteSync()
        {
            var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            if (nowMs - Interlocked.Read(ref _lastLocalPushMs) < 6000)
            {
                return;
            }

            var prev = Interlocked.Exchange(ref _realtimeDebounceCts, new CancellationTokenSource());
            try { prev?.Cancel(); prev?.Dispose(); } catch { }
            var token = _realtimeDebounceCts?.Token ?? CancellationToken.None;

            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(2500, token).ConfigureAwait(false);
                    if (!token.IsCancellationRequested)
                    {
                        await SyncWithRemoteAsync().ConfigureAwait(false);
                    }
                }
                catch { }
            }, token);
        }

        private string ResolveRemoteRowIdForSlot(int streamNumber, string localId)
        {
            lock (_remoteSlotLock)
            {
                if (_remoteSlotIdByNumber.TryGetValue(streamNumber, out var existingSlotId) && !string.IsNullOrWhiteSpace(existingSlotId))
                {
                    return existingSlotId;
                }

                // Never reuse a local ID that currently owns a different remote slot (prevents PK 23505 on reorder)
                if (Guid.TryParse(localId, out _) && !_remoteSlotIdByNumber.Values.Contains(localId))
                {
                    return localId;
                }
                return Guid.NewGuid().ToString();
            }
        }

        private async Task UpsertLocalStreamToRemoteAsync(LocalTagdoStream ls, string userId)
        {
            if (_supabaseClient == null) return;

            int streamNum = ls.OrderIndex + 1;
            var effectiveTitle = !string.IsNullOrWhiteSpace(ls.CustomTitle) ? ls.CustomTitle! : ls.Title;
            string? reminderStr = TagdosParser.EncodeReminderSpec(ls.StreamReminderTicks, ls.ClusterRemindersSpec);

            JToken attachmentsToken;
            try
            {
                attachmentsToken = string.IsNullOrWhiteSpace(ls.AttachmentsJson)
                    ? new JArray()
                    : JToken.Parse(ls.AttachmentsJson);
            }
            catch
            {
                attachmentsToken = new JArray();
            }

            var updatedUtc = ls.UpdatedAtTicks > DateTime.UnixEpoch.Ticks
                ? new DateTime(ls.UpdatedAtTicks, DateTimeKind.Utc)
                : DateTime.UtcNow;

            var remotePayload = new RemoteTagdoStream
            {
                Id = ResolveRemoteRowIdForSlot(streamNum, ls.Id),
                UserId = userId,
                StreamNumber = streamNum,
                Title = effectiveTitle,
                RawSyntax = ls.RawText ?? string.Empty,
                ReminderTime = reminderStr,
                ActiveMemos = ls.ActiveMemos ?? string.Empty,
                Attachments = attachmentsToken,
                UpdatedAt = updatedUtc
            };

            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            await ExecuteWithAuthAsync(
                () => _supabaseClient.From<RemoteTagdoStream>().Upsert(
                    remotePayload,
                    new Supabase.Postgrest.QueryOptions
                    {
                        OnConflict = "user_id,stream_number",
                        Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal
                    }),
                $"Tagdos.PushStream({streamNum})").ConfigureAwait(false);
            Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

            lock (_remoteSlotLock)
            {
                _remoteSlotIdByNumber[streamNum] = remotePayload.Id;
            }

            ls.UpdatedAtTicks = updatedUtc.Ticks;
            ls.SyncedAtTicks = DateTime.UtcNow.Ticks;
            await _databaseService.Connection.InsertOrReplaceAsync(ls).ConfigureAwait(false);
        }

        private async Task PushSingleStreamAsync(LocalTagdoStream ls)
        {
            if (_supabaseClient == null) return;
            try
            {
                if (_sessionGuardian != null)
                    await _sessionGuardian.EnsureValidSessionAsync().ConfigureAwait(false);

                var userId = _supabaseClient.Auth.CurrentUser?.Id;
                if (string.IsNullOrEmpty(userId)) return;

                await UpsertLocalStreamToRemoteAsync(ls, userId).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                _logger?.LogWarning("PushSingleStreamAsync warning: {Message}", ex.Message);
            }
        }

        private async Task PushSingleQuickNoteAsync(LocalTagdoQuickNote dn)
        {
            if (_supabaseClient == null) return;
            try
            {
                if (_sessionGuardian != null)
                    await _sessionGuardian.EnsureValidSessionAsync().ConfigureAwait(false);

                var userId = _supabaseClient.Auth.CurrentUser?.Id;
                if (string.IsNullOrEmpty(userId)) return;

                List<string> tags = new();
                try
                {
                    if (!string.IsNullOrWhiteSpace(dn.TagsJson))
                        tags = JsonSerializer.Deserialize<List<string>>(dn.TagsJson) ?? new();
                }
                catch { }

                var createdUtc = dn.CreatedAtTicks > DateTime.UnixEpoch.Ticks
                    ? new DateTime(dn.CreatedAtTicks, DateTimeKind.Utc)
                    : DateTime.UtcNow;
                var updatedUtc = dn.UpdatedAtTicks > DateTime.UnixEpoch.Ticks
                    ? new DateTime(dn.UpdatedAtTicks, DateTimeKind.Utc)
                    : DateTime.UtcNow;

                var remoteNote = new RemoteTagdoQuickNote
                {
                    Id = Guid.TryParse(dn.Id, out _) ? dn.Id : Guid.NewGuid().ToString(),
                    UserId = userId,
                    Title = dn.Title ?? string.Empty,
                    Content = dn.Content ?? string.Empty,
                    IsPinned = dn.IsPinned,
                    Tags = tags,
                    CreatedAt = createdUtc,
                    UpdatedAt = updatedUtc
                };

                Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                await ExecuteWithAuthAsync(
                    () => _supabaseClient.From<RemoteTagdoQuickNote>().Upsert(
                        remoteNote,
                        new Supabase.Postgrest.QueryOptions { Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal }),
                    $"Tagdos.PushSingleQuickNote({dn.Id})").ConfigureAwait(false);
                Interlocked.Exchange(ref _lastLocalPushMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

                dn.Id = remoteNote.Id;
                dn.UserId = userId;
                dn.SyncedAtTicks = DateTime.UtcNow.Ticks;
                await _databaseService.Connection.InsertOrReplaceAsync(dn).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                _logger?.LogWarning("PushSingleQuickNoteAsync warning: {Message}", ex.Message);
            }
        }

        private Task<T> ExecuteWithAuthAsync<T>(Func<Task<T>> op, string operationName)
        {
            if (_sessionGuardian != null)
                return _sessionGuardian.ExecuteWithAuthRetryAsync(op, operationName);
            return op();
        }

        private static long? ParseReminderTimeTicks(string? reminderTime)
        {
            if (string.IsNullOrWhiteSpace(reminderTime))
                return null;

            var parts = reminderTime.Trim().Split(':');
            if (parts.Length >= 2 &&
                int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var hour) &&
                int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var minute) &&
                hour >= 0 && hour < 24 && minute >= 0 && minute < 60)
            {
                var now = DateTime.UtcNow;
                return new DateTime(now.Year, now.Month, now.Day, hour, minute, 0, DateTimeKind.Utc).Ticks;
            }

            if (DateTime.TryParse(reminderTime, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsedDt))
            {
                return parsedDt.ToUniversalTime().Ticks;
            }

            return null;
        }
    }

    internal static class LocalTagdoStreamExtensions
    {
        public static bool DisplayNameCheck(this LocalTagdoStream local, string? remoteTitle)
        {
            var effectiveLocal = !string.IsNullOrWhiteSpace(local.CustomTitle) ? local.CustomTitle : local.Title;
            return !string.Equals(effectiveLocal ?? string.Empty, remoteTitle ?? string.Empty, StringComparison.Ordinal);
        }
    }
}
