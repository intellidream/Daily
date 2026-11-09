using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily_WinUI.Services;

public interface IPrismService
{
    event EventHandler? DataChanged;

    IReadOnlyList<PrismClip> Clips { get; }
    IReadOnlyList<PrismPinnedSite> PinnedSites { get; }
    IReadOnlyList<PrismTabState> Tabs { get; }
    string? ActiveTabId { get; }
    string? PendingUrlRequest { get; }
    string? ClipboardCandidateUrl { get; }

    Task EnsureLoadedAsync();
    Task SyncWithRemoteAsync();

    PrismTabState? GetActiveTab();
    void SelectTab(string tabId);
    PrismTabState OpenNewTab(string url = "", string? title = null, bool isPrivate = false);
    void CloseTab(string tabId);
    void UpdateActiveTabMetadata(
        string? url = null,
        string? title = null,
        int? scrollY = null,
        bool? isReaderMode = null,
        string? detectedRssUrl = "__keep__",
        string? detectedRssTitle = "__keep__");

    void RequestOpenUrlInPrism(string rawUrl, string? title = null, bool openInNewTab = false);
    string? ConsumePendingUrlRequest();
    void CheckClipboardCandidate(string? rawClipboardText, bool enabled);
    void DismissClipboardCandidate();

    Task<PrismClip> SaveLinkClipAsync(string url, string title, string? previewImageUrl = null, string userNote = "", IReadOnlyList<string>? tags = null);
    Task<PrismClip> SaveQuoteClipAsync(string quoteText, string sourceUrl, string pageTitle, string userNote = "", IReadOnlyList<string>? tags = null);
    Task<PrismClip> SaveAiSummaryClipAsync(PrismCoPilotTurn turn);
    Task<PrismClip> SaveImageClipAsync(byte[]? rawImageBytes, string? remoteImageUrl, string sourceUrl, string title, int? width = null, int? height = null, IReadOnlyList<string>? tags = null);

    Task ToggleFavoriteClipAsync(string clipId);
    Task DeleteClipAsync(string clipId);
    Task<string?> ResolveClipImageLocalPathAsync(PrismClip clip, CancellationToken ct = default);

    Task TogglePinSiteAsync(string title, string url);
    Task DeletePinnedSiteAsync(string pinId);

    Task SendClipToTagdosAsync(PrismClip clip);
    Task SendTasksToTagdosAsync(IReadOnlyList<string> tasks, string pageTitle, string sourceUrl);
    Task SaveClipToReadLaterAsync(PrismClip clip);
    Task SubscribeRssFeedAsync(string feedUrl, string feedTitle);

    Task<PrismCoPilotTurn> RunCoPilotActionAsync(
        PrismCoPilotAction action,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string? selectedText,
        CancellationToken ct = default);

    Task<PrismCoPilotTurn> AskCoPilotQuestionAsync(
        string question,
        string pageTitle,
        string sourceUrl,
        string bodyText,
        string? selectedText,
        CancellationToken ct = default);
}
