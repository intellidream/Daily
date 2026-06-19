using System;

namespace Daily_WinUI.Services
{
    public static class LlmDebugLogger
    {
        public static string SystemPrompt { get; set; } = string.Empty;
        public static string UserPrompt { get; set; } = string.Empty;
        public static string FormattedPrompt { get; set; } = string.Empty;
        public static string Response { get; set; } = string.Empty;
        public static string LastError { get; set; } = string.Empty;
        public static string ActiveEngine { get; set; } = string.Empty;
        public static DateTime LastExecutionTime { get; set; }
    }
}
