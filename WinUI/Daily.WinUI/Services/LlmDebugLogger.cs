using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Daily_WinUI.Services
{
    public sealed class LlmExecutionLog
    {
        public string SystemPrompt { get; set; } = string.Empty;
        public string UserPrompt { get; set; } = string.Empty;
        public string FormattedPrompt { get; set; } = string.Empty;
        public string Response { get; set; } = string.Empty;
        public string Error { get; set; } = string.Empty;
        public string ActiveEngine { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public long DurationMs { get; set; }
    }

    public static class LlmDebugLogger
    {
        private static readonly object _lock = new();
        public static List<LlmExecutionLog> Logs { get; } = new();
        public static string InitializationError { get; set; } = string.Empty;

        private static string _activeEngine = string.Empty;
        private static DateTime _lastExecutionTime;

        public static string ActiveEngine
        {
            get => _activeEngine;
            set => _activeEngine = value;
        }

        public static DateTime LastExecutionTime
        {
            get => _lastExecutionTime;
            set => _lastExecutionTime = value;
        }

        public static void Clear()
        {
            lock (_lock)
            {
                Logs.Clear();
                InitializationError = string.Empty;
            }
        }

        public static void Log(LlmExecutionLog log)
        {
            lock (_lock)
            {
                Logs.Add(log);
                _activeEngine = log.ActiveEngine;
                _lastExecutionTime = log.Timestamp;
            }
        }

        public static string SystemPrompt
        {
            get
            {
                lock (_lock)
                {
                    if (Logs.Count == 0) return string.Empty;
                    return string.Join("\n\n=========================================\n\n", Logs.Select((l, i) => $"[Prompt #{i+1} ({l.Timestamp:T}) - {l.SystemPrompt.Length} chars]\n{l.SystemPrompt}"));
                }
            }
            set
            {
                lock (_lock)
                {
                    EnsureSingleLog();
                    Logs[0].SystemPrompt = value;
                    Logs[0].Timestamp = DateTime.Now;
                }
            }
        }

        public static string UserPrompt
        {
            get
            {
                lock (_lock)
                {
                    if (Logs.Count == 0) return string.Empty;
                    return string.Join("\n\n=========================================\n\n", Logs.Select((l, i) => $"[Prompt #{i+1} ({l.Timestamp:T}) - {l.UserPrompt.Length} chars]\n{l.UserPrompt}"));
                }
            }
            set
            {
                lock (_lock)
                {
                    EnsureSingleLog();
                    Logs[0].UserPrompt = value;
                    Logs[0].Timestamp = DateTime.Now;
                }
            }
        }

        public static string FormattedPrompt
        {
            get
            {
                lock (_lock)
                {
                    if (Logs.Count == 0) return string.Empty;
                    return string.Join("\n\n=========================================\n\n", Logs.Select((l, i) => $"[Prompt #{i+1} ({l.Timestamp:T})]\n{l.FormattedPrompt}"));
                }
            }
            set
            {
                lock (_lock)
                {
                    EnsureSingleLog();
                    Logs[0].FormattedPrompt = value;
                    Logs[0].Timestamp = DateTime.Now;
                }
            }
        }

        public static string Response
        {
            get
            {
                lock (_lock)
                {
                    if (Logs.Count == 0) return string.Empty;
                    return string.Join("\n\n=========================================\n\n", Logs.Select((l, i) => $"[Prompt #{i+1} ({l.Timestamp:T}) - {l.DurationMs} ms]\n{l.Response}"));
                }
            }
            set
            {
                lock (_lock)
                {
                    EnsureSingleLog();
                    Logs[0].Response = value;
                    Logs[0].Timestamp = DateTime.Now;
                }
            }
        }

        public static string LastError
        {
            get
            {
                lock (_lock)
                {
                    var sb = new StringBuilder();
                    if (!string.IsNullOrEmpty(InitializationError))
                    {
                        sb.AppendLine("=== SYSTEM / INITIALIZATION ERRORS ===");
                        sb.AppendLine(InitializationError);
                        sb.AppendLine();
                    }

                    var errorLogs = Logs.Where(l => !string.IsNullOrEmpty(l.Error)).ToList();
                    if (errorLogs.Count > 0)
                    {
                        sb.AppendLine("=== MICRO-PROMPT EXECUTION ERRORS ===");
                        sb.AppendLine(string.Join("\n\n=========================================\n\n", errorLogs.Select((l, i) => $"[Prompt #{i+1} ({l.Timestamp:T})]\n{l.Error}")));
                    }
                    return sb.ToString().Trim();
                }
            }
            set
            {
                lock (_lock)
                {
                    EnsureSingleLog();
                    Logs[0].Error = value;
                    Logs[0].Timestamp = DateTime.Now;
                }
            }
        }

        private static void EnsureSingleLog()
        {
            if (Logs.Count == 0)
            {
                Logs.Add(new LlmExecutionLog { Timestamp = DateTime.Now });
            }
        }
    }
}
