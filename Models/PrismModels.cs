using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using SQLite;

namespace Daily.Models;

public enum PrismClipType
{
    Link,
    Quote,
    Image,
    AiSummary
}

public static class PrismClipTypeExtensions
{
    public static string ToRawValue(this PrismClipType type) => type switch
    {
        PrismClipType.Link => "link",
        PrismClipType.Quote => "quote",
        PrismClipType.Image => "image",
        PrismClipType.AiSummary => "ai_summary",
        _ => "link"
    };

    public static PrismClipType FromRawValue(string? raw) => (raw ?? string.Empty).Trim().ToLowerInvariant() switch
    {
        "quote" => PrismClipType.Quote,
        "image" => PrismClipType.Image,
        "ai_summary" => PrismClipType.AiSummary,
        _ => PrismClipType.Link
    };

    public static string DisplayLabel(this PrismClipType type) => type switch
    {
        PrismClipType.Link => "Link",
        PrismClipType.Quote => "Quote",
        PrismClipType.Image => "Image",
        PrismClipType.AiSummary => "AI Note",
        _ => "Link"
    };

    public static string FluentGlyph(this PrismClipType type) => type switch
    {
        PrismClipType.Link => "\uE71B",
        PrismClipType.Quote => "\uE9B1",
        PrismClipType.Image => "\uEB9F",
        PrismClipType.AiSummary => "\uF4A5",
        _ => "\uE71B"
    };
}

public enum PrismSearchEngine
{
    Google,
    DuckDuckGo,
    Brave,
    Perplexity
}

public static class PrismSearchEngineHelper
{
    public static string ToId(this PrismSearchEngine engine) => engine switch
    {
        PrismSearchEngine.DuckDuckGo => "duckduckgo",
        PrismSearchEngine.Brave => "brave",
        PrismSearchEngine.Perplexity => "perplexity",
        _ => "google"
    };

    public static PrismSearchEngine FromId(string? id) => (id ?? string.Empty).Trim().ToLowerInvariant() switch
    {
        "duckduckgo" => PrismSearchEngine.DuckDuckGo,
        "brave" => PrismSearchEngine.Brave,
        "perplexity" => PrismSearchEngine.Perplexity,
        _ => PrismSearchEngine.Google
    };

    public static string DisplayName(this PrismSearchEngine engine) => engine switch
    {
        PrismSearchEngine.DuckDuckGo => "DuckDuckGo",
        PrismSearchEngine.Brave => "Brave Search",
        PrismSearchEngine.Perplexity => "Perplexity",
        _ => "Google"
    };

    public static string BuildSearchUrl(this PrismSearchEngine engine, string query)
    {
        string encoded = Uri.EscapeDataString(query.Trim());
        return engine switch
        {
            PrismSearchEngine.DuckDuckGo => $"https://duckduckgo.com/?q={encoded}",
            PrismSearchEngine.Brave => $"https://search.brave.com/search?q={encoded}",
            PrismSearchEngine.Perplexity => $"https://www.perplexity.ai/search?q={encoded}",
            _ => $"https://www.google.com/search?q={encoded}"
        };
    }

    public static string? ResolveOmniboxInput(string? raw, PrismSearchEngine engine = PrismSearchEngine.Google)
    {
        string trimmed = (raw ?? string.Empty).Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        string lower = trimmed.ToLowerInvariant();
        if (lower.StartsWith("javascript:", StringComparison.Ordinal) ||
            lower.StartsWith("vbscript:", StringComparison.Ordinal) ||
            lower.StartsWith("file:", StringComparison.Ordinal) ||
            lower.StartsWith("data:", StringComparison.Ordinal))
        {
            return null;
        }

        if (lower.StartsWith("https://", StringComparison.Ordinal) ||
            lower.StartsWith("http://", StringComparison.Ordinal))
        {
            return Uri.TryCreate(trimmed, UriKind.Absolute, out _) ? trimmed : engine.BuildSearchUrl(trimmed);
        }

        bool looksLikeDomain = !trimmed.Contains(' ') &&
                               trimmed.Contains('.') &&
                               !trimmed.StartsWith('.') &&
                               !trimmed.EndsWith('.');
        if (looksLikeDomain)
        {
            string candidate = $"https://{trimmed}";
            if (Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) && !string.IsNullOrEmpty(parsed.Host))
            {
                return candidate;
            }
        }

        return engine.BuildSearchUrl(trimmed);
    }

    public static string ExtractCleanDomain(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            return string.Empty;
        }

        if (Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri) && !string.IsNullOrEmpty(uri.Host))
        {
            string host = uri.Host.ToLowerInvariant();
            return host.StartsWith("www.", StringComparison.Ordinal) ? host.Substring(4) : host;
        }

        return string.Empty;
    }
}

public static class PrismShieldRules
{
    private static readonly string[] BlockedDomains =
    {
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adnxs.com",
        "taboola.com",
        "outbrain.com",
        "criteo.com",
        "scorecardresearch.com",
        "quantserve.com",
        "rubiconproject.com",
        "pubmatic.com",
        "openx.net",
        "moatads.com",
        "adsafeprotected.com",
        "hotjar.com",
        "mouseflow.com",
        "amazon-adsystem.com"
    };

    public static bool ShouldBlockRequest(
        string? requestUrl,
        string? pageUrl,
        bool shieldEnabled,
        IReadOnlyCollection<string>? allowlistDomains)
    {
        if (!shieldEnabled || string.IsNullOrWhiteSpace(requestUrl))
        {
            return false;
        }

        string pageDomain = PrismSearchEngineHelper.ExtractCleanDomain(pageUrl);
        if (!string.IsNullOrEmpty(pageDomain) && allowlistDomains != null &&
            allowlistDomains.Any(d => string.Equals(d, pageDomain, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        string reqDomain = PrismSearchEngineHelper.ExtractCleanDomain(requestUrl);
        if (string.IsNullOrEmpty(reqDomain))
        {
            return false;
        }

        if (!string.IsNullOrEmpty(pageDomain) &&
            (string.Equals(reqDomain, pageDomain, StringComparison.OrdinalIgnoreCase) ||
             reqDomain.EndsWith("." + pageDomain, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        foreach (string blocked in BlockedDomains)
        {
            if (string.Equals(reqDomain, blocked, StringComparison.OrdinalIgnoreCase) ||
                reqDomain.EndsWith("." + blocked, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}

public enum PrismCoPilotAction
{
    TldrSummary,
    ExtractTasks,
    KeyFactsAndNumbers,
    ExplainSelection
}

public sealed class PrismCoPilotTurn
{
    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public string Prompt { get; set; } = string.Empty;
    public string ResponseMarkdown { get; set; } = string.Empty;
    public List<string> KeyBullets { get; set; } = new();
    public List<string> SuggestedTasks { get; set; } = new();
    public string EngineBadge { get; set; } = "Gemini 2.5 Flash";
    public string SourceUrl { get; set; } = string.Empty;
    public string PageTitle { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class PrismTabState
{
    public const int MaxOpenTabs = 8;

    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public string Url { get; set; } = string.Empty;
    public string Title { get; set; } = "Start Page";
    public string Domain { get; set; } = string.Empty;
    public bool IsPrivate { get; set; }
    public bool IsHibernated { get; set; }
    public bool IsReaderMode { get; set; }
    public int ScrollY { get; set; }
    public string? DetectedRssUrl { get; set; }
    public string? DetectedRssTitle { get; set; }
    public long LastAccessedEpochMs { get; set; } = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

    [JsonIgnore]
    public bool IsStartPage => string.IsNullOrWhiteSpace(Url) || Url.Equals("about:blank", StringComparison.OrdinalIgnoreCase);
}

public sealed class PrismClip
{
    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public string? UserId { get; set; }
    public PrismClipType ClipType { get; set; } = PrismClipType.Link;
    public string Title { get; set; } = string.Empty;
    public string SourceUrl { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string ContentText { get; set; } = string.Empty;
    public string UserNote { get; set; } = string.Empty;
    public List<string> Tags { get; set; } = new();
    public string? PreviewImageUrl { get; set; }
    public string? StoragePath { get; set; }
    public int? ImageWidth { get; set; }
    public int? ImageHeight { get; set; }
    public bool IsFavorite { get; set; }
    public bool IsDeleted { get; set; }
    public string? TagdosNoteId { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    public string TypeBadge => ClipType.DisplayLabel();
    public string TypeGlyph => ClipType.FluentGlyph();
    public string TagsSummary => Tags.Count == 0 ? string.Empty : string.Join(" ", Tags.Select(t => $"#{t}"));
    public string Snippet => !string.IsNullOrWhiteSpace(ContentText) ? ContentText : SourceUrl;
}

public sealed class PrismPinnedSite
{
    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public string? UserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string? IconUrl { get; set; }
    public int DisplayOrder { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    public string ResolvedFaviconUrl =>
        !string.IsNullOrWhiteSpace(IconUrl)
            ? IconUrl
            : $"https://www.google.com/s2/favicons?domain={Uri.EscapeDataString(string.IsNullOrEmpty(Domain) ? PrismSearchEngineHelper.ExtractCleanDomain(Url) : Domain)}&sz=64";

    public static string DeterministicId(string userScope, string url)
    {
        string normalized = $"{userScope.Trim().ToLowerInvariant()}|prism_pin|{url.Trim().TrimEnd('/').ToLowerInvariant()}";
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(normalized));
        byte[] guidBytes = new byte[16];
        Array.Copy(hash, 0, guidBytes, 0, 16);
        guidBytes[6] = (byte)((guidBytes[6] & 0x0F) | 0x50);
        guidBytes[8] = (byte)((guidBytes[8] & 0x3F) | 0x80);
        return new Guid(guidBytes).ToString("D");
    }

    public static List<PrismPinnedSite> CreateDefaultStarterSites(string userScope = "local")
    {
        var seeds = new (string Title, string Url)[]
        {
            ("GitHub", "https://github.com"),
            ("Hacker News", "https://news.ycombinator.com"),
            ("Substack", "https://substack.com/inbox"),
            ("Medium", "https://medium.com"),
            ("Perplexity", "https://www.perplexity.ai"),
            ("Wikipedia", "https://en.wikipedia.org")
        };

        var result = new List<PrismPinnedSite>(seeds.Length);
        for (int i = 0; i < seeds.Length; i++)
        {
            string domain = PrismSearchEngineHelper.ExtractCleanDomain(seeds[i].Url);
            result.Add(new PrismPinnedSite
            {
                Id = DeterministicId(userScope, seeds[i].Url),
                UserId = userScope == "local" ? null : userScope,
                Title = seeds[i].Title,
                Url = seeds[i].Url,
                Domain = domain,
                IconUrl = $"https://www.google.com/s2/favicons?domain={domain}&sz=64",
                DisplayOrder = i
            });
        }

        return result;
    }
}

// ── Local SQLite Entities (`Daily.db3`) ────────────────────────────────────

[SQLite.Table("prism_clips")]
public class LocalPrismClip
{
    [SQLite.PrimaryKey]
    public string Id { get; set; } = Guid.NewGuid().ToString("D");

    [SQLite.Indexed]
    public string? UserId { get; set; }

    [SQLite.Indexed]
    public string ClipType { get; set; } = "link";

    public string Title { get; set; } = string.Empty;
    public string SourceUrl { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string ContentText { get; set; } = string.Empty;
    public string UserNote { get; set; } = string.Empty;
    public string TagsJson { get; set; } = "[]";
    public string? PreviewImageUrl { get; set; }
    public string? StoragePath { get; set; }
    public int? ImageWidth { get; set; }
    public int? ImageHeight { get; set; }
    public bool IsFavorite { get; set; }
    public bool IsDeleted { get; set; }
    public string? TagdosNoteId { get; set; }
    public long CreatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
    public long UpdatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
    public long? SyncedAtTicks { get; set; }
}

[SQLite.Table("prism_pinned_sites")]
public class LocalPrismPinnedSite
{
    [SQLite.PrimaryKey]
    public string Id { get; set; } = Guid.NewGuid().ToString("D");

    [SQLite.Indexed]
    public string? UserId { get; set; }

    public string Title { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string? IconUrl { get; set; }
    public int DisplayOrder { get; set; }
    public bool IsDeleted { get; set; }
    public long CreatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
    public long UpdatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
    public long? SyncedAtTicks { get; set; }
}

// ── Supabase PostgREST Entities (Strictly Newtonsoft.Json) ─────────────────

[Supabase.Postgrest.Attributes.Table("prism_clips")]
public class RemotePrismClip : Supabase.Postgrest.Models.BaseModel
{
    [Supabase.Postgrest.Attributes.PrimaryKey("id", true)]
    [Supabase.Postgrest.Attributes.Column("id")]
    public string Id { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("clip_type")]
    public string ClipType { get; set; } = "link";

    [Supabase.Postgrest.Attributes.Column("title")]
    public string Title { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("source_url")]
    public string SourceUrl { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("domain")]
    public string Domain { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("content_text")]
    public string ContentText { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("user_note")]
    public string UserNote { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("tags")]
    public List<string> Tags { get; set; } = new();

    [Supabase.Postgrest.Attributes.Column("preview_image_url")]
    public string? PreviewImageUrl { get; set; }

    [Supabase.Postgrest.Attributes.Column("storage_path")]
    public string? StoragePath { get; set; }

    [Supabase.Postgrest.Attributes.Column("image_width")]
    public int? ImageWidth { get; set; }

    [Supabase.Postgrest.Attributes.Column("image_height")]
    public int? ImageHeight { get; set; }

    [Supabase.Postgrest.Attributes.Column("is_favorite")]
    public bool IsFavorite { get; set; }

    [Supabase.Postgrest.Attributes.Column("is_deleted")]
    public bool IsDeleted { get; set; }

    [Supabase.Postgrest.Attributes.Column("tagdos_note_id")]
    public string? TagdosNoteId { get; set; }

    [Supabase.Postgrest.Attributes.Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [Supabase.Postgrest.Attributes.Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

[Supabase.Postgrest.Attributes.Table("prism_pinned_sites")]
public class RemotePrismPinnedSite : Supabase.Postgrest.Models.BaseModel
{
    [Supabase.Postgrest.Attributes.PrimaryKey("id", true)]
    [Supabase.Postgrest.Attributes.Column("id")]
    public string Id { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("title")]
    public string Title { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("url")]
    public string Url { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("domain")]
    public string Domain { get; set; } = string.Empty;

    [Supabase.Postgrest.Attributes.Column("icon_url")]
    public string? IconUrl { get; set; }

    [Supabase.Postgrest.Attributes.Column("display_order")]
    public int DisplayOrder { get; set; }

    [Supabase.Postgrest.Attributes.Column("is_deleted")]
    public bool IsDeleted { get; set; }

    [Supabase.Postgrest.Attributes.Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [Supabase.Postgrest.Attributes.Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
