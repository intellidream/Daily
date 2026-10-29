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
        private readonly IGotrueClient<User, Session>.AuthEventHandler? _authListener;

        public event EventHandler? DataChanged;

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
                    await SetupRealtimeAsync(forceRecreate: state == Supabase.Gotrue.Constants.AuthState.TokenRefreshed).ConfigureAwait(false);
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

            var conn = _databaseService.Connection;
            var local = new LocalTagdoStream
            {
                Id = stream.Id,
                OrderIndex = stream.OrderIndex,
                Title = stream.Title,
                CustomTitle = stream.CustomTitle,
                RawText = stream.RawText,
                StreamReminderTicks = stream.StreamReminder?.Ticks,
                ActiveMemos = stream.ActiveMemos ?? string.Empty,
                AttachmentsJson = string.IsNullOrWhiteSpace(stream.AttachmentsJson) ? "[]" : stream.AttachmentsJson,
                UpdatedAtTicks = DateTime.UtcNow.Ticks,
                SyncedAtTicks = null
            };

            await conn.InsertOrReplaceAsync(local).ConfigureAwait(false);

            lock (_cachedStreams)
            {
                var idx = _cachedStreams.FindIndex(s => s.Id == stream.Id || s.OrderIndex == stream.OrderIndex);
                if (idx >= 0)
                {
                    _cachedStreams[idx] = stream;
                }
                else
                {
                    _cachedStreams.Add(stream);
                }
            }

            DataChanged?.Invoke(this, EventArgs.Empty);
            _ = Task.Run(SyncWithRemoteAsync);
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
                var parsed = TagdosParser.ParseStream(newRawText, stream.OrderIndex, stream.Title, stream.StreamReminder, stream.ActiveMemos, stream.AttachmentsJson, stream.CustomTitle);
                parsed.Id = stream.Id;
                await SaveStreamAsync(parsed).ConfigureAwait(false);
            }
        }

        public async Task UpdateStreamTitleAsync(string streamId, string newTitle)
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            TagDoStream? stream = null;
            lock (_cachedStreams)
            {
                stream = _cachedStreams.FirstOrDefault(s => s.Id == streamId);
            }

            if (stream != null)
            {
                stream.CustomTitle = newTitle;
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
            _ = Task.Run(SyncWithRemoteAsync);
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
            _ = Task.Run(SyncWithRemoteAsync);
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
                            await ExecuteWithAuthAsync(async () =>
                            {
                                await _supabaseClient.From<RemoteTagdoQuickNote>()
                                    .Where(x => x.Id == noteId && x.UserId == userId)
                                    .Delete()
                                    .ConfigureAwait(false);
                                return true;
                            }, "Tagdos.DeleteQuickNote").ConfigureAwait(false);
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
                    foreach (var remote in remoteStreams)
                    {
                        int orderIdx = Math.Clamp(remote.StreamNumber - 1, 0, 4);
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

                            var reminderTicks = ParseReminderTimeTicks(remote.ReminderTime);
                            var attachmentsJson = remote.Attachments != null
                                ? remote.Attachments.ToString(Newtonsoft.Json.Formatting.None)
                                : "[]";

                            var updatedLocal = new LocalTagdoStream
                            {
                                Id = remote.Id,
                                OrderIndex = orderIdx,
                                Title = remote.Title ?? string.Empty,
                                CustomTitle = !string.IsNullOrWhiteSpace(remote.Title) ? remote.Title : null,
                                RawText = remote.RawSyntax ?? string.Empty,
                                StreamReminderTicks = reminderTicks,
                                ActiveMemos = remote.ActiveMemos ?? string.Empty,
                                AttachmentsJson = string.IsNullOrWhiteSpace(attachmentsJson) ? "[]" : attachmentsJson,
                                UpdatedAtTicks = remoteUpdatedUtc.Ticks,
                                SyncedAtTicks = DateTime.UtcNow.Ticks
                            };

                            await conn.InsertOrReplaceAsync(updatedLocal).ConfigureAwait(false);
                            anyLocalUpdatedFromRemote = true;
                        }
                        else if (existing != null && !string.Equals(existing.Id, remote.Id, StringComparison.OrdinalIgnoreCase))
                        {
                            // Adopt canonical remote UUID before pushing local dirty edit
                            var oldId = existing.Id;
                            existing.Id = remote.Id;
                            await conn.DeleteAsync<LocalTagdoStream>(oldId).ConfigureAwait(false);
                            await conn.InsertOrReplaceAsync(existing).ConfigureAwait(false);
                        }
                    }
                }

                // Refresh localStreams snapshot and push dirty (or initial when remote is completely empty)
                localStreams = await conn.Table<LocalTagdoStream>().OrderBy(s => s.OrderIndex).ToListAsync().ConfigureAwait(false);
                var streamsToPush = remoteStreams.Count == 0
                    ? localStreams
                    : localStreams.Where(s => s.SyncedAtTicks == null && !IsUntouchedSeedStream(s)).ToList();

                foreach (var ls in streamsToPush)
                {
                    var effectiveTitle = !string.IsNullOrWhiteSpace(ls.CustomTitle) ? ls.CustomTitle! : ls.Title;
                    string? reminderStr = null;
                    if (ls.StreamReminderTicks.HasValue)
                    {
                        var dt = new DateTime(ls.StreamReminderTicks.Value, DateTimeKind.Utc);
                        reminderStr = $"{dt.Hour:D2}:{dt.Minute:D2}";
                    }

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
                        Id = Guid.TryParse(ls.Id, out _) ? ls.Id : Guid.NewGuid().ToString(),
                        UserId = userId,
                        StreamNumber = ls.OrderIndex + 1,
                        Title = effectiveTitle,
                        RawSyntax = ls.RawText ?? string.Empty,
                        ReminderTime = reminderStr,
                        ActiveMemos = ls.ActiveMemos ?? string.Empty,
                        Attachments = attachmentsToken,
                        UpdatedAt = updatedUtc
                    };

                    await ExecuteWithAuthAsync(
                        () => _supabaseClient.From<RemoteTagdoStream>().Upsert(
                            remotePayload,
                            new Supabase.Postgrest.QueryOptions { OnConflict = "user_id,stream_number" }),
                        $"Tagdos.PushStream({ls.OrderIndex + 1})").ConfigureAwait(false);

                    ls.Id = remotePayload.Id;
                    ls.UpdatedAtTicks = updatedUtc.Ticks;
                    ls.SyncedAtTicks = DateTime.UtcNow.Ticks;
                    await conn.InsertOrReplaceAsync(ls).ConfigureAwait(false);
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

                    await ExecuteWithAuthAsync(
                        () => _supabaseClient.From<RemoteTagdoQuickNote>().Upsert(remoteNote),
                        $"Tagdos.PushQuickNote({dn.Id})").ConfigureAwait(false);

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

                _streamsRealtimeChannel = await _supabaseClient.From<RemoteTagdoStream>()
                    .On(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, (_, _) =>
                    {
                        _ = Task.Run(SyncWithRemoteAsync);
                    });

                _notesRealtimeChannel = await _supabaseClient.From<RemoteTagdoQuickNote>()
                    .On(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, (_, _) =>
                    {
                        _ = Task.Run(SyncWithRemoteAsync);
                    });

                _realtimeUserId = userId;
                SupabaseSessionGuardian.LogGuardian($"[TagdosService] Subscribed to Realtime for tagdos_streams & tagdos_quick_notes (user={userId}).");
            }
            catch (Exception ex)
            {
                SupabaseSessionGuardian.LogGuardian($"[TagdosService] Realtime setup warning: {ex.Message}");
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
