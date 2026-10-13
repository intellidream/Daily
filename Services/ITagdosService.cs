using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily.Services
{
    public interface ITagdosService
    {
        event EventHandler? DataChanged;

        Task<List<TagDoStream>> GetStreamsAsync();
        Task<TagDoStream?> GetStreamByIndexAsync(int orderIndex);
        Task SaveStreamAsync(TagDoStream stream);
        Task UpdateStreamRawTextAsync(string streamId, string newRawText);
        Task UpdateStreamTitleAsync(string streamId, string newTitle);
        Task SetStreamReminderAsync(string streamId, DateTime? reminder);
        Task UpdateStreamMemosAsync(string streamId, string memos, string attachmentsJson);

        Task<List<TagDoQuickNote>> GetQuickNotesAsync();
        Task<TagDoQuickNote> CreateQuickNoteAsync(string title, string content, bool isPinned = false);
        Task UpdateQuickNoteAsync(TagDoQuickNote note);
        Task TogglePinQuickNoteAsync(string noteId);
        Task DeleteQuickNoteAsync(string noteId);

        Task SyncWithRemoteAsync();
    }
}
