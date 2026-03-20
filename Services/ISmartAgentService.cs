namespace Daily.Services
{
    public class WidgetSuggestion
    {
        public string WidgetType { get; set; } = "";
        public double Confidence { get; set; }
        public string Icon { get; set; } = "";
        public string Label { get; set; } = "";
    }

    public interface ISmartAgentService
    {
        /// <summary>
        /// Records a user interaction with a widget.
        /// </summary>
        Task RecordEventAsync(string widgetType, string action = "view");

        /// <summary>
        /// Returns the best suggestion for right now based on learned patterns.
        /// </summary>
        Task<WidgetSuggestion?> GetSuggestionAsync();

        /// <summary>
        /// Initializes the service (loads data from SQLite).
        /// </summary>
        Task InitializeAsync();

        /// <summary>
        /// Fires when the suggestion changes.
        /// </summary>
        event Action? OnSuggestionChanged;
    }
}
