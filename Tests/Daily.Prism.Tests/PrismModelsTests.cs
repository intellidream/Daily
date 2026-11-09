using System.Collections.Generic;
using Daily.Models;
using Xunit;

namespace Daily.Prism.Tests;

public sealed class PrismModelsTests
{
    [Fact]
    public void ResolveOmniboxInput_WithDangerousScheme_ReturnsNull()
    {
        // Arrange
        const string dangerous = "javascript:alert(1)";

        // Act
        string? result = PrismSearchEngineHelper.ResolveOmniboxInput(dangerous);

        // Assert
        Assert.Null(result);
    }

    [Fact]
    public void ResolveOmniboxInput_WithBareDomain_PrependsHttps()
    {
        // Arrange
        const string bareDomain = "news.ycombinator.com";

        // Act
        string? result = PrismSearchEngineHelper.ResolveOmniboxInput(bareDomain);

        // Assert
        Assert.Equal("https://news.ycombinator.com", result);
    }

    [Fact]
    public void ResolveOmniboxInput_WithSearchQuery_BuildsEngineSearchUrl()
    {
        // Arrange
        const string query = "winui 3 webview2 npu";

        // Act
        string? result = PrismSearchEngineHelper.ResolveOmniboxInput(query, PrismSearchEngine.DuckDuckGo);

        // Assert
        Assert.Equal("https://duckduckgo.com/?q=winui%203%20webview2%20npu", result);
    }

    [Fact]
    public void ShouldBlockRequest_ThirdPartyTrackerWhenShieldActive_ReturnsTrue()
    {
        // Arrange
        const string requestUrl = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js";
        const string pageUrl = "https://arstechnica.com/gadgets/2026/11/test/";

        // Act
        bool blocked = PrismShieldRules.ShouldBlockRequest(requestUrl, pageUrl, shieldEnabled: true, allowlistDomains: null);

        // Assert
        Assert.True(blocked);
    }

    [Fact]
    public void ShouldBlockRequest_WhenDomainAllowlisted_ReturnsFalse()
    {
        // Arrange
        const string requestUrl = "https://securepubads.g.doubleclick.net/tag/js/gpt.js";
        const string pageUrl = "https://www.theverge.com/tech";
        var allowlist = new List<string> { "theverge.com" };

        // Act
        bool blocked = PrismShieldRules.ShouldBlockRequest(requestUrl, pageUrl, shieldEnabled: true, allowlistDomains: allowlist);

        // Assert
        Assert.False(blocked);
    }

    [Fact]
    public void DeterministicId_SameUserAndNormalizedUrl_ProducesIdenticalUuid()
    {
        // Arrange
        const string userId = "88888888-4444-4444-4444-121212121212";

        // Act
        string idA = PrismPinnedSite.DeterministicId(userId, "https://Substack.com/inbox/");
        string idB = PrismPinnedSite.DeterministicId(userId, "https://substack.com/inbox");

        // Assert
        Assert.Equal(idA, idB);
        Assert.True(System.Guid.TryParse(idA, out _));
    }
}
