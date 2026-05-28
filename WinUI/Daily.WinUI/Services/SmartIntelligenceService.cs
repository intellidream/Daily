using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Windows.AI.Text;
using Microsoft.Windows.AI;
using Microsoft.ML.OnnxRuntimeGenAI;

namespace Daily_WinUI.Services
{
    public interface ISmartIntelligenceService
    {
        Task<bool> IsModelReadyAsync();
        Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
    }

    public class PhiSilicaSmartService : ISmartIntelligenceService
    {
        private LanguageModel? _model;

        public async Task<bool> IsModelReadyAsync()
        {
            try
            {
                // In WinAppSDK 1.8, the ready state is checked using static GetReadyState()
                var state = LanguageModel.GetReadyState();
                return state == AIFeatureReadyState.Ready || state == AIFeatureReadyState.NotReady;
            }
            catch
            {
                return false;
            }
        }

        private async Task EnsureLoadedAsync()
        {
            if (_model == null)
            {
                try
                {
                    var state = LanguageModel.GetReadyState();
                    if (state == AIFeatureReadyState.NotReady)
                    {
                        var result = await LanguageModel.EnsureReadyAsync();
                        if (result.Status != AIFeatureReadyResultState.Success)
                        {
                            throw new InvalidOperationException($"Phi Silica model provisioning failed. Status: {result.Status}, Error: {result.ErrorDisplayText}");
                        }
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[PhiSilica] Provisioning error: {ex}");
                }

                _model = await LanguageModel.CreateAsync();
            }
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            if (!await IsModelReadyAsync())
            {
                throw new InvalidOperationException("Phi Silica model is not ready/available on this system.");
            }

            await EnsureLoadedAsync();

            if (_model == null)
            {
                throw new InvalidOperationException("Failed to initialize Phi Silica model.");
            }

            // Standard format prompt for Phi Silica
            string prompt = $"<|system|>\n{systemPrompt}<|end|>\n<|user|>\n{userPrompt}<|end|>\n<|assistant|>\n";
            
            var result = await _model.GenerateResponseAsync(prompt).AsTask(ct);
            if (result.Status == LanguageModelResponseStatus.Complete)
            {
                return result.Text;
            }
            else
            {
                throw new Exception($"Phi Silica generation failed or was blocked. Status: {result.Status}");
            }
        }
    }

    public class OnnxGenAiSmartService : ISmartIntelligenceService
    {
        private Model? _model;
        private Tokenizer? _tokenizer;
        private string? _lastUsedAccelerator;
        private string? _lastConfiguredAccelerator;
        private string? _lastUsedModelId;
        private bool _useCpuFallback = false;
        private string? _runtimeModelOverride;
        private string? _runtimeAcceleratorOverride;

        public bool IsUsingCpuFallback
        {
            get
            {
                var settings = SettingsService.Load();
                string choice = settings.SelectedAiAccelerator ?? "Auto";
                string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
                if (_lastConfiguredAccelerator != choice || _lastUsedModelId != selectedModelId)
                {
                    _useCpuFallback = false;
                }
                return _useCpuFallback;
            }
        }

        public Task<bool> IsModelReadyAsync()
        {
            var settings = SettingsService.Load();
            string modelId = settings.SelectedLocalAiModel ?? "llama32_1b";
            return IsModelReadyAsync(modelId);
        }

        public Task<bool> IsModelReadyAsync(string modelId)
        {
            bool ready = SettingsService.IsModelDownloaded(modelId);
            return Task.FromResult(ready);
        }

        private async Task EnsureLoadedAsync()
        {
            var settings = SettingsService.Load();
            string choice = _runtimeAcceleratorOverride ?? settings.SelectedAiAccelerator ?? "Auto";
            string selectedModelId = _runtimeModelOverride ?? settings.SelectedLocalAiModel ?? "llama32_1b";

            if (_lastConfiguredAccelerator != choice || _lastUsedModelId != selectedModelId)
            {
                _useCpuFallback = false;
                _lastConfiguredAccelerator = choice;
            }

            string actualChoice = _useCpuFallback ? "CPU" : choice;

            if (_model != null && (_lastUsedAccelerator != actualChoice || _lastUsedModelId != selectedModelId))
            {
                System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Reloading model because accelerator or model ID changed.");
                _model.Dispose();
                _model = null;
                _tokenizer?.Dispose();
                _tokenizer = null;
            }

            if (_model == null)
            {
                if (!await IsModelReadyAsync(selectedModelId))
                {
                    throw new InvalidOperationException($"ONNX model {selectedModelId} is not downloaded or verified yet.");
                }

                string currentModelPath = SettingsService.GetModelDirectory(selectedModelId);

                await Task.Run(() =>
                {
                    _lastUsedAccelerator = actualChoice;
                    _lastUsedModelId = selectedModelId;

                    string resolvedChoice = actualChoice;
                    if (actualChoice == "Auto")
                    {
                        // Resolve Auto based on recommendation and execution history
                        string? npu = SettingsService.GetDetectedNpuName();
                        if (!string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
                        {
                            resolvedChoice = "NPU";
                        }
                        else
                        {
                            // Check if GPU is marked as Failed in history
                            var gpuHistory = settings.ModelExecutionHistories?.FirstOrDefault(h => h.ModelId == selectedModelId && h.Accelerator == "GPU");
                            if (gpuHistory != null && gpuHistory.Status == "Failed")
                            {
                                resolvedChoice = "CPU"; // Auto fallback to CPU
                            }
                            else
                            {
                                resolvedChoice = "GPU";
                            }
                        }
                    }

                    using var config = new Config(currentModelPath);
                    config.ClearProviders();

                    if (resolvedChoice == "CPU")
                    {
                        System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Loading model {selectedModelId} on CPU (Cleared providers)");
                    }
                    else if (resolvedChoice == "NPU_IntelAmd")
                    {
                        config.AppendProvider("dml");
                        int npuIndex = Daily_WinUI.Helpers.DeviceHelper.GetAdapterIndex("NPU");
                        config.SetProviderOption("dml", "device_id", npuIndex.ToString());
                        System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Loading model {selectedModelId} on NPU (DirectML Adapter Index: {npuIndex})");
                    }
                    else // GPU
                    {
                        config.AppendProvider("dml");
                        int gpuIndex = Daily_WinUI.Helpers.DeviceHelper.GetAdapterIndex("GPU");
                        config.SetProviderOption("dml", "device_id", gpuIndex.ToString());
                        System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Loading model {selectedModelId} on GPU (DirectML Adapter Index: {gpuIndex})");
                    }

                    try
                    {
                        _model = new Model(config);
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Failed to load model with customized config: {ex.Message}. Falling back to CPU.");
                        _useCpuFallback = true;
                        _lastUsedAccelerator = "CPU";
                        try
                        {
                            using var cpuConfig = new Config(currentModelPath);
                            cpuConfig.ClearProviders();
                            _model = new Model(cpuConfig);
                        }
                        catch (Exception innerEx)
                        {
                            System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] CPU fallback load failed: {innerEx.Message}. Trying default fallback.");
                            using var fallbackConfig = new Config(currentModelPath);
                            _model = new Model(fallbackConfig);
                        }
                    }

                    _tokenizer = new Tokenizer(_model);
                });
            }
        }

        private string FormatPrompt(string modelId, string systemPrompt, string userPrompt)
        {
            return modelId switch
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

        private string GetModelFriendlyName(string modelId)
        {
            return modelId switch
            {
                "llama32_1b" => "Llama 3.2 1B Instruct",
                "qwen25_15b" => "Qwen 2.5 1.5B Instruct",
                "gemma3_1b" => "Gemma 3 1B Instruct",
                "phi35_mini" => "Phi 3.5 Mini Instruct",
                _ => modelId
            };
        }

        private string GetAcceleratorFriendlyName(string acc)
        {
            return acc switch
            {
                "GPU" => "DirectML GPU",
                "CPU" => "DirectML CPU",
                "NPU" => "NPU",
                "NPU_IntelAmd" => "Intel/AMD NPU",
                _ => acc
            };
        }

        private string GetUserFriendlyError(Exception ex)
        {
            string msg = ex.Message;
            if (msg.Contains("DmlFusedNode") || msg.Contains("DirectML") || msg.Contains("dml"))
            {
                return "encountered a graphics card driver error or compatibility issue.";
            }
            if (msg.Contains("vocab_size"))
            {
                return "encountered a vocabulary size initialization mismatch.";
            }
            if (msg.Contains("context_length"))
            {
                return "encountered a context length configuration mismatch.";
            }
            if (msg.Contains("File doesn't exist") || msg.Contains("failed:Load model"))
            {
                return "could not find model files on disk.";
            }
            return "encountered an unexpected execution error.";
        }

        private void RecordExecutionResult(string modelId, string acc, string status, string explanation)
        {
            try
            {
                var settings = SettingsService.Load();
                if (settings.ModelExecutionHistories == null)
                {
                    settings.ModelExecutionHistories = new List<ModelExecutionHistory>();
                }

                var existing = settings.ModelExecutionHistories.FirstOrDefault(h => h.ModelId == modelId && h.Accelerator == acc);
                if (existing != null)
                {
                    existing.Status = status;
                    existing.LastExplanation = explanation;
                    existing.LastAttempted = System.DateTime.Now;
                }
                else
                {
                    settings.ModelExecutionHistories.Add(new ModelExecutionHistory
                    {
                        ModelId = modelId,
                        Accelerator = acc,
                        Status = status,
                        LastExplanation = explanation,
                        LastAttempted = System.DateTime.Now
                    });
                }
                SettingsService.Save(settings);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Error recording execution result: {ex.Message}");
            }
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            var settings = SettingsService.Load();
            string initialModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
            string initialAccelerator = settings.SelectedAiAccelerator ?? "Auto";

            // Helper to get resolved accelerator
            string ResolveAccelerator(string acc, string modelId)
            {
                if (acc != "Auto") return acc;
                string? npu = SettingsService.GetDetectedNpuName();
                if (!string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
                {
                    return "NPU";
                }
                return "GPU";
            }

            string targetAcc = ResolveAccelerator(initialAccelerator, initialModelId);

            var configsToTry = new List<(string ModelId, string Accelerator)>();

            // 1. The user's requested configuration
            configsToTry.Add((initialModelId, targetAcc));

            // 2. If it was GPU/NPU, the same model on CPU
            if (targetAcc != "CPU" && targetAcc != "NPU")
            {
                configsToTry.Add((initialModelId, "CPU"));
            }

            // 3. Other downloaded models in preference order
            string[] allModels = { "llama32_1b", "qwen25_15b", "gemma3_1b", "phi35_mini" };
            foreach (var modelId in allModels)
            {
                if (modelId == initialModelId) continue;
                if (await IsModelReadyAsync(modelId))
                {
                    var hist = settings.ModelExecutionHistories?.FirstOrDefault(h => h.ModelId == modelId);
                    if (hist != null && hist.Status == "Working")
                    {
                        configsToTry.Add((modelId, hist.Accelerator));
                    }
                    else
                    {
                        configsToTry.Add((modelId, "CPU"));
                    }
                }
            }

            Exception? lastError = null;
            string? workingModelId = null;
            string? workingAccelerator = null;
            string finalResponse = string.Empty;
            var failedLogs = new List<string>();

            for (int i = 0; i < configsToTry.Count; i++)
            {
                var config = configsToTry[i];

                // Skip if marked as Failed in memory, unless it is the user's primary selection
                if (i > 0)
                {
                    var hist = settings.ModelExecutionHistories?.FirstOrDefault(h => h.ModelId == config.ModelId && h.Accelerator == config.Accelerator);
                    if (hist != null && hist.Status == "Failed")
                    {
                        failedLogs.Add($"{GetModelFriendlyName(config.ModelId)} on {GetAcceleratorFriendlyName(config.Accelerator)} (skipped - previously failed)");
                        continue;
                    }
                }

                try
                {
                    System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Cascading fallback: Attempting {config.ModelId} on {config.Accelerator}");

                    _runtimeModelOverride = config.ModelId;
                    _runtimeAcceleratorOverride = config.Accelerator;

                    await EnsureLoadedAsync();

                    if (_model == null || _tokenizer == null)
                    {
                        throw new InvalidOperationException("Model or tokenizer failed to load.");
                    }

                    string formattedPrompt = FormatPrompt(config.ModelId, systemPrompt, userPrompt);
                    StringBuilder responseText = new StringBuilder();

                    await Task.Run(() =>
                    {
                        using var tokens = _tokenizer.Encode(formattedPrompt);
                        using var generatorParams = new GeneratorParams(_model);
                        generatorParams.SetSearchOption("max_length", 2048);

                        using var generator = new Generator(_model, generatorParams);
                        generator.AppendTokenSequences(tokens);
                        using var tokenizerStream = _tokenizer.CreateStream();

                        while (!generator.IsDone() && !ct.IsCancellationRequested)
                        {
                            generator.GenerateNextToken();
                            var seq = generator.GetSequence(0);
                            var newToken = seq[^1];
                            string chunk = tokenizerStream.Decode(newToken);
                            responseText.Append(chunk);
                        }
                    }, ct);

                    finalResponse = responseText.ToString();
                    workingModelId = config.ModelId;
                    workingAccelerator = config.Accelerator;
                    break; // Success!
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Execution of {config.ModelId} on {config.Accelerator} failed: {ex.Message}");
                    lastError = ex;

                    RecordExecutionResult(config.ModelId, config.Accelerator, "Failed", GetUserFriendlyError(ex));
                    failedLogs.Add($"{GetModelFriendlyName(config.ModelId)} on {GetAcceleratorFriendlyName(config.Accelerator)}");

                    _model?.Dispose();
                    _model = null;
                    _tokenizer?.Dispose();
                    _tokenizer = null;
                }
            }

            _runtimeModelOverride = null;
            _runtimeAcceleratorOverride = null;

            if (workingModelId != null && workingAccelerator != null)
            {
                RecordExecutionResult(workingModelId, workingAccelerator, "Working", "Executed successfully.");

                string explanation;
                if (workingModelId == initialModelId && workingAccelerator == targetAcc)
                {
                    explanation = $"Executed successfully using your selected configuration: {GetModelFriendlyName(workingModelId)} on {GetAcceleratorFriendlyName(workingAccelerator)}.";
                }
                else
                {
                    explanation = $"Your selected configuration ({GetModelFriendlyName(initialModelId)} on {GetAcceleratorFriendlyName(targetAcc)}) fell back due to execution issues ({string.Join(", ", failedLogs)}). We successfully defaulted to {GetModelFriendlyName(workingModelId)} on {GetAcceleratorFriendlyName(workingAccelerator)}.";
                }

                settings = SettingsService.Load();
                settings.LastExecutionExplanation = explanation;
                SettingsService.Save(settings);

                return finalResponse;
            }

            string finalErrExplain = $"All attempted local AI models fell back due to errors ({string.Join(", ", failedLogs)}). Procedural Fallback Template Engine was activated to ensure stability.";
            settings = SettingsService.Load();
            settings.LastExecutionExplanation = finalErrExplain;
            SettingsService.Save(settings);

            throw new InvalidOperationException(finalErrExplain, lastError);
        }
    }

    public class SmartIntelligenceCoordinator : ISmartIntelligenceService
    {
        private readonly PhiSilicaSmartService _phiSilica;
        private readonly OnnxGenAiSmartService _onnxGenAi;

        public SmartIntelligenceCoordinator(PhiSilicaSmartService phiSilica, OnnxGenAiSmartService onnxGenAi)
        {
            _phiSilica = phiSilica;
            _onnxGenAi = onnxGenAi;
        }

        public async Task<ISmartIntelligenceService?> GetActiveServiceAsync()
        {
            var settings = SettingsService.Load();
            string choice = settings.SelectedAiAccelerator ?? "Auto";

            if (choice == "Fallback")
            {
                return null;
            }

            bool useInternalAi = settings.UseWindowsInternalAi;

            if (choice == "NPU")
            {
                if (useInternalAi)
                {
                    if (await _phiSilica.IsModelReadyAsync()) return _phiSilica;
                }
                else
                {
                    if (await _onnxGenAi.IsModelReadyAsync()) return _onnxGenAi;
                }
            }
            else if (choice == "GPU" || choice == "CPU" || choice == "NPU_IntelAmd")
            {
                if (await _onnxGenAi.IsModelReadyAsync()) return _onnxGenAi;
            }
            else // Auto
            {
                if (useInternalAi)
                {
                    // Prioritize Phi Silica if hardware is ready
                    if (await _phiSilica.IsModelReadyAsync())
                    {
                        return _phiSilica;
                    }
                }
                
                // Fallback to downloaded ONNX model
                if (await _onnxGenAi.IsModelReadyAsync())
                {
                    return _onnxGenAi;
                }
            }

            return null; // Graceful fallback to procedural generator
        }

        public async Task<bool> IsModelReadyAsync()
        {
            var service = await GetActiveServiceAsync();
            return service != null && await service.IsModelReadyAsync();
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            var service = await GetActiveServiceAsync();
            if (service == null)
            {
                var settings = SettingsService.Load();
                settings.LastExecutionExplanation = "No local AI service is ready or configured. Procedural Fallback Template Engine was activated.";
                SettingsService.Save(settings);
                throw new InvalidOperationException("No local AI service is ready or configured.");
            }

            if (service is PhiSilicaSmartService)
            {
                try
                {
                    string response = await service.GenerateResponseAsync(systemPrompt, userPrompt, ct);
                    
                    var settings = SettingsService.Load();
                    settings.LastExecutionExplanation = "Executed successfully using built-in Windows Copilot Runtime (Phi Silica) on Qualcomm Hexagon NPU.";
                    SettingsService.Save(settings);
                    
                    return response;
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[SmartIntelligenceCoordinator] Phi Silica execution failed: {ex.Message}");
                    string phiError = ex.Message;
                    if (ex.InnerException != null)
                    {
                        phiError += $" (Inner: {ex.InnerException.Message})";
                    }

                    // Attempt fallback to custom model if ready
                    if (await _onnxGenAi.IsModelReadyAsync())
                    {
                        try
                        {
                            System.Diagnostics.Debug.WriteLine("[SmartIntelligenceCoordinator] Falling back to custom ONNX model...");
                            string response = await _onnxGenAi.GenerateResponseAsync(systemPrompt, userPrompt, ct);
                            
                            var settings = SettingsService.Load();
                            string modelId = settings.SelectedLocalAiModel ?? "llama32_1b";
                            string modelName = modelId switch
                            {
                                "llama32_1b" => "Llama 3.2 1B Instruct",
                                "qwen25_15b" => "Qwen 2.5 1.5B Instruct",
                                "gemma3_1b" => "Gemma 3 1B Instruct",
                                "phi35_mini" => "Phi 3.5 Mini Instruct",
                                _ => modelId
                            };
                            
                            settings.LastExecutionExplanation = $"Windows Copilot Runtime (Phi Silica) execution failed ({phiError}). Successfully fell back to custom model: {modelName} on DirectML GPU.";
                            SettingsService.Save(settings);
                            
                            return response;
                        }
                        catch (Exception innerEx)
                        {
                            System.Diagnostics.Debug.WriteLine($"[SmartIntelligenceCoordinator] Resilient ONNX fallback failed: {innerEx.Message}");
                            phiError += $" | Fallback to custom model failed: {innerEx.Message}";
                        }
                    }

                    // Save failure explanation if we couldn't run ONNX either
                    var settingsFail = SettingsService.Load();
                    settingsFail.LastExecutionExplanation = $"Windows Copilot Runtime (Phi Silica) failed ({phiError}). Procedural Fallback Template Engine was activated to ensure stability.";
                    SettingsService.Save(settingsFail);
                    
                    throw new InvalidOperationException($"Windows Copilot Runtime (Phi Silica) failed ({phiError})", ex);
                }
            }
            else
            {
                // For OnnxGenAiSmartService, it has its own cascading fallbacks and saves its own execution status
                return await service.GenerateResponseAsync(systemPrompt, userPrompt, ct);
            }
        }
    }
}
