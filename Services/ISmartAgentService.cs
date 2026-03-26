namespace Daily.Services
{
    public class WidgetSuggestion
    {
        public string WidgetType { get; set; } = "";
        public double Confidence { get; set; }
        public string Icon { get; set; } = "";
        public string Label { get; set; } = "";
        public bool IsTransitionBased { get; set; }
    }

    public interface ISmartAgentService
    {
        Task RecordEventAsync(string widgetType, string action = "view");

        /// <summary>
        /// Returns the best suggestion based on time patterns + current context.
        /// </summary>
        Task<WidgetSuggestion?> GetSuggestionAsync(string? currentVisibleWidget = null);

        Task InitializeAsync();

        /// <summary>
        /// Records a navigation transition: user scrolled from one widget to another.
        /// </summary>
        Task RecordTransitionAsync(string fromWidget, string toWidget);

        /// <summary>
        /// Whether the service has loaded and the user is authenticated.
        /// </summary>
        bool IsReady { get; }

        event Action? OnSuggestionChanged;
    }
}
