using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Daily.Models;
using Microsoft.Extensions.Logging;

namespace Daily.Services
{
    public class TagdosService : ITagdosService
    {
        private readonly IDatabaseService _databaseService;
        private readonly Supabase.Client? _supabaseClient;
        private readonly ILogger<TagdosService>? _logger;

        private readonly List<TagDoStream> _cachedStreams = new();
        private readonly List<TagDoQuickNote> _cachedNotes = new();
        private bool _isLoaded = false;
        private readonly SemaphoreSlim _lock = new(1, 1);

        public event EventHandler? DataChanged;

        public TagdosService(
            IDatabaseService databaseService,
            Supabase.Client? supabaseClient = null,
            ILogger<TagdosService>? logger = null)
        {
            _databaseService = databaseService;
            _supabaseClient = supabaseClient;
            _logger = logger;
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

                _cachedStreams.Clear();
                foreach (var ls in localStreams)
                {
                    DateTime? reminder = ls.StreamReminderTicks.HasValue ? new DateTime(ls.StreamReminderTicks.Value, DateTimeKind.Utc) : null;
                    var parsed = TagdosParser.ParseStream(ls.RawText, ls.OrderIndex, ls.Title, reminder, ls.ActiveMemos, ls.AttachmentsJson, ls.CustomTitle);
                    parsed.Id = ls.Id;
                    _cachedStreams.Add(parsed);
                }

                var localNotes = await conn.Table<LocalTagdoQuickNote>().OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAtTicks).ToListAsync().ConfigureAwait(false);
                if (localNotes.Count == 0)
                {
                    await SeedDefaultNotesAsync().ConfigureAwait(false);
                    localNotes = await conn.Table<LocalTagdoQuickNote>().OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAtTicks).ToListAsync().ConfigureAwait(false);
                }

                _cachedNotes.Clear();
                foreach (var ln in localNotes)
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

                    _cachedNotes.Add(new TagDoQuickNote
                    {
                        Id = ln.Id,
                        UserId = ln.UserId,
                        Title = ln.Title,
                        Content = ln.Content,
                        IsPinned = ln.IsPinned,
                        Tags = tags,
                        CreatedAt = new DateTime(ln.CreatedAtTicks, DateTimeKind.Utc),
                        UpdatedAt = new DateTime(ln.UpdatedAtTicks, DateTimeKind.Utc)
                    });
                }

                _isLoaded = true;
            }
            finally
            {
                _lock.Release();
            }
        }

        private async Task SeedDefaultStreamsAsync()
        {
            var conn = _databaseService.Connection;
            var defaults = new (int index, string title, string raw, int hour, int min)[]
            {
                (0, "Morning Prime", "MG/GM/TG & FSH/LDL & C$T/INV & 22/HAB & MED/CHK & REV/DEP & WRK/PRJ", 8, 30),
                (1, "Work Execution", "WRK/PRJ/REV & MET/ZOOM & CALL/CLI & BUG/FIX", 10, 0),
                (2, "Fitness & Health", "FIT/GYM & RUN/5K & PROT/SHK & CREAT/5G & SLP/REC", 17, 30),
                (3, "Finances & Ledger", "FIN/CARD & CASH/EUR & INV/STK & CRYP/BTC", 19, 0),
                (4, "Home & Routine", "HOM/ORD & CLN/KIT & BUY/MKT & GROC/VEG", 21, 0)
            };

            var now = DateTime.UtcNow;
            foreach (var d in defaults)
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
                    UpdatedAtTicks = now.Ticks
                };
                await conn.InsertOrReplaceAsync(row).ConfigureAwait(false);
            }
        }

        private async Task SeedDefaultNotesAsync()
        {
            var conn = _databaseService.Connection;
            var now = DateTime.UtcNow;

            var n1 = new LocalTagdoQuickNote
            {
                Id = Guid.NewGuid().ToString(),
                Title = "Executive Briefing Focus",
                Content = "1. Focus on top 3 deep work streams\n2. Review quarterly financial roadmap\n3. Sync multi-device biometrics",
                IsPinned = true,
                TagsJson = "[\"#focus\",\"#executive\"]",
                CreatedAtTicks = now.Ticks,
                UpdatedAtTicks = now.Ticks
            };

            var n2 = new LocalTagdoQuickNote
            {
                Id = Guid.NewGuid().ToString(),
                Title = "Desktop Reading Queue",
                Content = "• Windows App SDK & WinUI 3 Composition APIs\n• Cross-platform shared architecture with DailyCore",
                IsPinned = false,
                TagsJson = "[\"#reading\",\"#dev\"]",
                CreatedAtTicks = now.AddMinutes(-30).Ticks,
                UpdatedAtTicks = now.AddMinutes(-30).Ticks
            };

            await conn.InsertOrReplaceAsync(n1).ConfigureAwait(false);
            await conn.InsertOrReplaceAsync(n2).ConfigureAwait(false);
        }

        public async Task<List<TagDoStream>> GetStreamsAsync()
        {
            await EnsureLoadedAsync().ConfigureAwait(false);
            lock (_cachedStreams)
            {
                return _cachedStreams.ToList();
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
                ActiveMemos = stream.ActiveMemos,
                AttachmentsJson = stream.AttachmentsJson,
                UpdatedAtTicks = DateTime.UtcNow.Ticks
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

            var note = new TagDoQuickNote
            {
                Id = Guid.NewGuid().ToString(),
                Title = title,
                Content = content,
                IsPinned = isPinned,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            var local = new LocalTagdoQuickNote
            {
                Id = note.Id,
                Title = note.Title,
                Content = note.Content,
                IsPinned = note.IsPinned,
                TagsJson = "[]",
                CreatedAtTicks = note.CreatedAt.Ticks,
                UpdatedAtTicks = note.UpdatedAt.Ticks
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
                Title = note.Title,
                Content = note.Content,
                IsPinned = note.IsPinned,
                TagsJson = JsonSerializer.Serialize(note.Tags),
                CreatedAtTicks = note.CreatedAt.Ticks,
                UpdatedAtTicks = note.UpdatedAt.Ticks
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
            _ = Task.Run(SyncWithRemoteAsync);
        }

        public async Task SyncWithRemoteAsync()
        {
            if (_supabaseClient == null || _supabaseClient.Auth.CurrentUser == null)
            {
                return;
            }

            try
            {
                var userId = _supabaseClient.Auth.CurrentUser.Id;

                // 1. Sync streams
                List<TagDoStream> streamsToPush;
                lock (_cachedStreams)
                {
                    streamsToPush = _cachedStreams.ToList();
                }

                foreach (var s in streamsToPush)
                {
                    var remote = new RemoteTagdoStream
                    {
                        Id = s.Id,
                        UserId = userId,
                        OrderIndex = s.OrderIndex,
                        Title = s.DisplayTitle,
                        RawText = s.RawText,
                        StreamReminder = s.StreamReminder,
                        ActiveMemos = s.ActiveMemos,
                        UpdatedAt = DateTime.UtcNow
                    };
                    await _supabaseClient.From<RemoteTagdoStream>().Upsert(remote).ConfigureAwait(false);
                }

                // 2. Sync notes
                List<TagDoQuickNote> notesToPush;
                lock (_cachedNotes)
                {
                    notesToPush = _cachedNotes.ToList();
                }

                foreach (var n in notesToPush)
                {
                    var remoteNote = new RemoteTagdoQuickNote
                    {
                        Id = n.Id,
                        UserId = userId,
                        Title = n.Title,
                        Content = n.Content,
                        IsPinned = n.IsPinned,
                        CreatedAt = n.CreatedAt,
                        UpdatedAt = n.UpdatedAt
                    };
                    await _supabaseClient.From<RemoteTagdoQuickNote>().Upsert(remoteNote).ConfigureAwait(false);
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning("Tagdos remote sync failed (operating offline): {Message}", ex.Message);
            }
        }
    }
}
