using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily.Services
{
    public interface ITagdosService
    {
        event EventHandler? DataChanged;
        event EventHandler? PendingNavigationChanged;

        TagdosNavigationTarget? PendingNavigation { get; }
        void RequestNavigation(string? streamId = null, int? clusterIndex = null, string? pillId = null, bool openPillEditor = false);
        void HandleDeepLink(Uri uri);
        TagdosNavigationTarget? ConsumePendingNavigation();

        Task<List<TagDoStream>> GetStreamsAsync();
        Task<TagDoStream?> GetStreamByIndexAsync(int orderIndex);
        Task SaveStreamAsync(TagDoStream stream);
        Task UpdateStreamRawTextAsync(string streamId, string newRawText);
        Task UpdateStreamTitleAsync(string streamId, string? newTitle);
        Task SetStreamReminderAsync(string streamId, DateTime? reminder);
        Task SetClusterReminderAsync(string streamId, int clusterIndex, DateTime? reminder);
        Task ReloadFromLocalAsync();
        Task UpdateStreamMemosAsync(string streamId, string memos, string attachmentsJson);
        Task<TagDoStream> CreateStreamAsync(string? title = null, string rawText = "", string activeMemos = "");
        Task DeleteStreamAsync(string streamId);
        Task MoveStreamAsync(int fromIndex, int toIndex);
        Task ReorderStreamsAsync(List<string> orderedIds);
        Task<string?> ImportExternalTaskBatchAsync(List<TagdosTaskImportItem> items);
        Task<TagDoStream> ImportExternalTasksAsync(string mode, string? targetStreamId, string? newStreamTitle, List<string> rawDslChunks, List<string> memoLines);

        Task<List<TagDoQuickNote>> GetQuickNotesAsync();
        Task<TagDoQuickNote> CreateQuickNoteAsync(string title, string content, bool isPinned = false);
        Task UpdateQuickNoteAsync(TagDoQuickNote note);
        Task TogglePinQuickNoteAsync(string noteId);
        Task DeleteQuickNoteAsync(string noteId);

        Task SyncWithRemoteAsync();
    }
}
