namespace Daily_WinUI.Models;

public sealed class LocationSuggestion
{
    public string DisplayName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Country { get; set; } = string.Empty;
    public string? State { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public string FavoriteCategory { get; set; } = "Travel";
    public bool IsPinned { get; set; }
    public string PinTag => IsPinned ? "[P]" : string.Empty;

    public override string ToString() => DisplayName;
}