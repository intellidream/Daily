using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Daily_WinUI.Services
{
    public interface ISmartIntelligenceService
    {
        Task<bool> IsModelReadyAsync();
        Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
        IAsyncEnumerable<string> GenerateResponseStreamAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
        Task InitializeAsync();
        bool IsPhiSilicaActive { get; }
        string ActiveEngineName { get; }
    }

    public class OnnxGenAiSmartService : ISmartIntelligenceService
    {
        private readonly AIManager _aiManager;

        public OnnxGenAiSmartService(AIManager aiManager)
        {
            _aiManager = aiManager;
        }

        public bool IsUsingCpuFallback => _aiManager.ActiveEngineName.Contains("CPU Fallback");

        public string ActiveEngineName => _aiManager.ActiveEngineName;

        public bool IsPhiSilicaActive => _aiManager.ActiveEngine is PhiSilicaNpuEngine;

        public async Task InitializeAsync()
        {
            await _aiManager.InitializeAsync();
        }

        public async Task<bool> IsModelReadyAsync()
        {
            var settings = SettingsService.Load();
            string selectedAcc = settings.SelectedAiAccelerator ?? "Auto";
            if (selectedAcc.Equals("Fallback", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (settings.UseWindowsInternalAi && 
                (selectedAcc.Equals("Auto", StringComparison.OrdinalIgnoreCase) || selectedAcc.Equals("NPU", StringComparison.OrdinalIgnoreCase)))
            {
                var npuEngine = new PhiSilicaNpuEngine();
                if (await npuEngine.IsSupportedAsync())
                {
                    return true;
                }
            }

            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
            return SettingsService.IsModelDownloaded(selectedModelId);
        }

        public Task<bool> IsModelReadyAsync(string modelId)
        {
            return Task.FromResult(SettingsService.IsModelDownloaded(modelId));
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            // Format using llama format (standard GGUF fallback format)
            string prompt = $"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";

            var log = new LlmExecutionLog
            {
                SystemPrompt = systemPrompt,
                UserPrompt = userPrompt,
                FormattedPrompt = prompt,
                ActiveEngine = _aiManager.ActiveEngineName,
                Timestamp = DateTime.Now
            };

            try
            {
                var sw = System.Diagnostics.Stopwatch.StartNew();
                string response = await _aiManager.GenerateBriefingAsync(prompt);
                sw.Stop();
                log.DurationMs = sw.ElapsedMilliseconds;
                log.Response = response;
                LlmDebugLogger.Log(log);
                return SmartIntelligenceHelper.SanitizeResponse(response, systemPrompt, userPrompt, prompt);
            }
            catch (Exception ex)
            {
                log.Error = ex.ToString();
                LlmDebugLogger.Log(log);
                throw;
            }
        }

        public async IAsyncEnumerable<string> GenerateResponseStreamAsync(string systemPrompt, string userPrompt, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default)
        {
            string prompt = $"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";

            var log = new LlmExecutionLog
            {
                SystemPrompt = systemPrompt,
                UserPrompt = userPrompt,
                FormattedPrompt = prompt,
                ActiveEngine = _aiManager.ActiveEngineName,
                Timestamp = DateTime.Now
            };

            var stream = _aiManager.GenerateBriefingStreamAsync(prompt);
            var sb = new System.Text.StringBuilder();
            var sw = System.Diagnostics.Stopwatch.StartNew();

            try
            {
                await foreach (var token in stream.WithCancellation(ct))
                {
                    sb.Append(token);
                    yield return token;
                }
            }
            finally
            {
                sw.Stop();
                log.DurationMs = sw.ElapsedMilliseconds;
                log.Response = sb.ToString();
                // If there's an exception, it will bubble up, but we log what we got so far
                LlmDebugLogger.Log(log);
            }
        }
    }

    public class SmartIntelligenceCoordinator : ISmartIntelligenceService
    {
        private readonly AIManager _aiManager;

        public SmartIntelligenceCoordinator(AIManager aiManager)
        {
            _aiManager = aiManager;
        }

        public string ActiveEngineName => _aiManager.ActiveEngineName;

        public bool IsPhiSilicaActive => _aiManager.ActiveEngine is PhiSilicaNpuEngine;

        public async Task InitializeAsync()
        {
            await _aiManager.InitializeAsync();
        }

        public async Task<bool> IsModelReadyAsync()
        {
            var settings = SettingsService.Load();
            string selectedAcc = settings.SelectedAiAccelerator ?? "Auto";
            if (selectedAcc.Equals("Fallback", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (settings.UseWindowsInternalAi && 
                (selectedAcc.Equals("Auto", StringComparison.OrdinalIgnoreCase) || selectedAcc.Equals("NPU", StringComparison.OrdinalIgnoreCase)))
            {
                var npuEngine = new PhiSilicaNpuEngine();
                if (await npuEngine.IsSupportedAsync())
                {
                    return true;
                }
            }

            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
            return SettingsService.IsModelDownloaded(selectedModelId);
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            var settings = SettingsService.Load();
            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";

            // Ensure the AIManager is initialized
            await _aiManager.InitializeAsync();

            string prompt;
            if (_aiManager.ActiveEngine is PhiSilicaNpuEngine)
            {
                // Format for Phi Silica
                prompt = $"<|system|>\n{systemPrompt}<|end|>\n<|user|>\n{userPrompt}<|end|>\n<|assistant|>\n";
            }
            else
            {
                // Format for GGUF model
                string lowerId = selectedModelId.ToLowerInvariant();
                if (lowerId.Contains("qwen") || lowerId.Contains("chatml"))
                {
                    prompt = $"<|im_start|>system\n{systemPrompt}<|im_end|>\n<|im_start|>user\n{userPrompt}<|im_end|>\n<|im_start|>assistant\n";
                }
                else if (lowerId.Contains("gemma"))
                {
                    prompt = $"<start_of_turn>system\n{systemPrompt}<end_of_turn>\n<start_of_turn>user\n{userPrompt}<end_of_turn>\n<start_of_turn>assistant\n";
                }
                else if (lowerId.Contains("phi"))
                {
                    prompt = $"<|system|>\n{systemPrompt}<|end|>\n<|user|>\n{userPrompt}<|end|>\n<|assistant|>\n";
                }
                else
                {
                    // Llama 3 format is the safest fallback for most modern models
                    prompt = $"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";
                }
            }

            var log = new LlmExecutionLog
            {
                SystemPrompt = systemPrompt,
                UserPrompt = userPrompt,
                FormattedPrompt = prompt,
                ActiveEngine = _aiManager.ActiveEngineName,
                Timestamp = DateTime.Now
            };

            try
            {
                var sw = System.Diagnostics.Stopwatch.StartNew();
                string response = await _aiManager.GenerateBriefingAsync(prompt);
                sw.Stop();
                log.DurationMs = sw.ElapsedMilliseconds;
                log.Response = response;
                LlmDebugLogger.Log(log);

                // Save active engine explanation
                settings = SettingsService.Load();
                settings.LastExecutionExplanation = $"Executed successfully using dynamic strategy: {_aiManager.ActiveEngineName}.";
                SettingsService.Save(settings);

                return SmartIntelligenceHelper.SanitizeResponse(response, systemPrompt, userPrompt, prompt);
            }
            catch (Exception ex)
            {
                log.Error = ex.ToString();
                LlmDebugLogger.Log(log);
                throw;
            }
        }

        public async IAsyncEnumerable<string> GenerateResponseStreamAsync(string systemPrompt, string userPrompt, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default)
        {
            var settings = SettingsService.Load();
            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";

            await _aiManager.InitializeAsync();

            string prompt;
            if (_aiManager.ActiveEngine is PhiSilicaNpuEngine)
            {
                prompt = $"<|system|>\n{systemPrompt}<|end|>\n<|user|>\n{userPrompt}<|end|>\n<|assistant|>\n";
            }
            else
            {
                string lowerId = selectedModelId.ToLowerInvariant();
                if (lowerId.Contains("qwen") || lowerId.Contains("chatml"))
                {
                    prompt = $"<|im_start|>system\n{systemPrompt}<|im_end|>\n<|im_start|>user\n{userPrompt}<|im_end|>\n<|im_start|>assistant\n";
                }
                else if (lowerId.Contains("gemma"))
                {
                    prompt = $"<start_of_turn>system\n{systemPrompt}<end_of_turn>\n<start_of_turn>user\n{userPrompt}<end_of_turn>\n<start_of_turn>assistant\n";
                }
                else if (lowerId.Contains("phi"))
                {
                    prompt = $"<|system|>\n{systemPrompt}<|end|>\n<|user|>\n{userPrompt}<|end|>\n<|assistant|>\n";
                }
                else
                {
                    prompt = $"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";
                }
            }

            var log = new LlmExecutionLog
            {
                SystemPrompt = systemPrompt,
                UserPrompt = userPrompt,
                FormattedPrompt = prompt,
                ActiveEngine = _aiManager.ActiveEngineName,
                Timestamp = DateTime.Now
            };

            var stream = _aiManager.GenerateBriefingStreamAsync(prompt);
            var sb = new System.Text.StringBuilder();
            var sw = System.Diagnostics.Stopwatch.StartNew();
            
            try
            {
                await foreach (var token in stream.WithCancellation(ct))
                {
                    sb.Append(token);
                    yield return token;
                }
            }
            finally
            {
                sw.Stop();
                log.DurationMs = sw.ElapsedMilliseconds;
                log.Response = sb.ToString();
                LlmDebugLogger.Log(log);
            }
        }
    }

    internal static class SmartIntelligenceHelper
    {
        public static string SanitizeResponse(string response, string systemPrompt, string userPrompt, string prompt)
        {
            if (string.IsNullOrEmpty(response)) return string.Empty;

            string cleanResponse = response.Trim();

            // 1. Strip exact formatted prompt if leaked
            if (cleanResponse.StartsWith(prompt))
            {
                cleanResponse = cleanResponse.Substring(prompt.Length).Trim();
            }

            // 2. Strip user prompt if leaked
            int userPromptIdx = cleanResponse.IndexOf(userPrompt);
            if (userPromptIdx >= 0)
            {
                cleanResponse = cleanResponse.Substring(userPromptIdx + userPrompt.Length).Trim();
            }

            // 3. Strip system prompt if leaked
            int systemPromptIdx = cleanResponse.IndexOf(systemPrompt);
            if (systemPromptIdx >= 0)
            {
                cleanResponse = cleanResponse.Substring(systemPromptIdx + systemPrompt.Length).Trim();
            }

            // 4. Strip common delimiters/headers/assistant tags/system prompt repeats
            string[] prefixToStrip = new[]
            {
                "<|start_header_id|>assistant<|end_header_id|>",
                "<|assistant|>",
                "<|im_start|>assistant",
                "<|im_end|>",
                "<|eot_id|>",
                "<|end|>",
                "assistant\n",
                "assistant:\n",
                "assistant:",
                "system\n",
                "system:\n",
                "system:",
                "user\n",
                "user:\n",
                "user:",
                "System: Write exactly one concise, encouraging sentence commenting on the user's active tasks. CRITICAL: Do NOT list or enumerate the tasks (do not write down task titles or details). Instead, write a natural statement mentioning the number of pending tasks (e.g. 'You still have 3 tasks to complete today' or 'You have 4 active tasks left on your agenda') or comment on their workload/importance (e.g. 'You have a few high-priority tasks to focus on' or 'You have a light task list today').",
                "System: Write exactly one concise, encouraging sentence commenting on the user's upcoming calendar events today. CRITICAL: Do NOT list or enumerate the events (do not write down event names, times, or locations). Instead, write a natural statement mentioning the number of upcoming events (e.g. 'You have 3 events scheduled for today' or 'You have only 2 more events today') or comment on their workload/importance (e.g. 'Your schedule is looking very light today' or 'You have a busy afternoon ahead').",
                "System: You are a weather briefing assistant. Summarize today's weather in one concise, natural, and encouraging sentence.",
                "System: Summarize the user's financial state into one concise sentence based on net worth and stock tickers.",
                "System: Summarize these 5 headlines into one concise sentence extracting the main topic. CRITICAL: Do NOT output any introductory text, prefix, or conversational phrases (such as \"Here's a concise sentence...\", \"Here is a summary...\", \"Headlines Summary:\", or \"The main topic is...\"). Start directly with the summary sentence itself.",
                "Active tasks:\n",
                "Active tasks:",
                "Headlines:\n",
                "Headlines:",
                "Upcoming events:\n",
                "Upcoming events:",
                "Weather:\n",
                "Weather:"
            };

            bool changed = true;
            while (changed)
            {
                changed = false;
                foreach (var prefix in prefixToStrip)
                {
                    if (cleanResponse.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    {
                        cleanResponse = cleanResponse.Substring(prefix.Length).Trim();
                        changed = true;
                        break;
                    }
                }
                
                // Trim trailing tags/chars
                string oldClean = cleanResponse;
                cleanResponse = cleanResponse.Trim(':', ' ', '\n', '\r', '\t', '•', '-', '*', '<', '>');
                if (cleanResponse != oldClean)
                {
                    changed = true;
                }
            }

            return cleanResponse;
        }
    }
}
