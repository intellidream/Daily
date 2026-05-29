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
    }

    public class OnnxGenAiSmartService : ISmartIntelligenceService
    {
        private readonly AIManager _aiManager;

        public OnnxGenAiSmartService(AIManager aiManager)
        {
            _aiManager = aiManager;
        }

        public bool IsUsingCpuFallback => _aiManager.ActiveEngineName.Contains("CPU Fallback");

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
            return await _aiManager.GenerateBriefingAsync(prompt);
        }
    }

    public class SmartIntelligenceCoordinator : ISmartIntelligenceService
    {
        private readonly AIManager _aiManager;

        public SmartIntelligenceCoordinator(AIManager aiManager)
        {
            _aiManager = aiManager;
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
                prompt = selectedModelId switch
                {
                    "qwen25_15b" => 
                        $"<|im_start|>system\n{systemPrompt}<|im_end|>\n<|im_start|>user\n{userPrompt}<|im_end|>\n<|im_start|>assistant\n",
                    
                    "gemma3_1b" => 
                        $"<start_of_turn>system\n{systemPrompt}<end_of_turn>\n<start_of_turn>user\n{userPrompt}<end_of_turn>\n<start_of_turn>assistant\n",
                    
                    "phi35_mini" => 
                        $"<|system|>\n{systemPrompt}<|end|>\n<|user|>\n{userPrompt}<|end|>\n<|assistant|>\n",
                    
                    "llama32_1b" or _ => 
                        $"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
                };
            }

            string response = await _aiManager.GenerateBriefingAsync(prompt);

            // Save active engine explanation
            settings = SettingsService.Load();
            settings.LastExecutionExplanation = $"Executed successfully using dynamic strategy: {_aiManager.ActiveEngineName}.";
            SettingsService.Save(settings);

            return response;
        }
    }
}
