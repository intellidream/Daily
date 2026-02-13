using System.Text.Json.Serialization;

namespace Daily.Models;

public class ReadabilityResult
{
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("content")]
    public string? Content { get; set; }

    [JsonPropertyName("textContent")]
    public string? TextContent { get; set; }

    [JsonPropertyName("excerpt")]
    public string? Excerpt { get; set; }

    [JsonPropertyName("byline")]
    public string? Byline { get; set; }
}
