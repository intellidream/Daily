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
                return state == AIFeatureReadyState.Ready;
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
            bool ready = SettingsService.IsModelDownloaded(modelId);
            return Task.FromResult(ready);
        }

        private async Task EnsureLoadedAsync()
        {
            var settings = SettingsService.Load();
            string choice = settings.SelectedAiAccelerator ?? "Auto";
            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";

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
                if (!await IsModelReadyAsync())
                {
                    throw new InvalidOperationException("ONNX model is not downloaded or verified yet.");
                }

                string currentModelPath = SettingsService.GetModelDirectory(selectedModelId);

                await Task.Run(() =>
                {
                    _lastUsedAccelerator = actualChoice;
                    _lastUsedModelId = selectedModelId;

                    string resolvedChoice = actualChoice;
                    if (actualChoice == "Auto")
                      {
                        resolvedChoice = "GPU";
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

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            await EnsureLoadedAsync();

            if (_model == null || _tokenizer == null)
            {
                throw new InvalidOperationException("ONNX model could not be loaded.");
            }

            var settings = SettingsService.Load();
            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
            string formattedPrompt = FormatPrompt(selectedModelId, systemPrompt, userPrompt);

            StringBuilder responseText = new StringBuilder();

            try
            {
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
                        
                        var sequence = generator.GetSequence(0);
                        var newToken = sequence[^1];
                        
                        string chunk = tokenizerStream.Decode(newToken);
                        responseText.Append(chunk);
                    }
                }, ct);

                return responseText.ToString();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[OnnxGenAi] Generation exception: {ex.Message}");

                // If we were not already using CPU, attempt CPU fallback
                if (_lastUsedAccelerator != "CPU")
                {
                    System.Diagnostics.Debug.WriteLine("[OnnxGenAi] Generation failed on hardware accelerator. Attempting CPU fallback...");
                    _useCpuFallback = true;

                    // Clean up and load CPU model
                    _model?.Dispose();
                    _model = null;
                    _tokenizer?.Dispose();
                    _tokenizer = null;

                    await EnsureLoadedAsync();

                    if (_model == null || _tokenizer == null)
                    {
                        throw new InvalidOperationException("ONNX model could not be loaded during CPU fallback.", ex);
                    }

                    responseText.Clear();

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
                            
                            var sequence = generator.GetSequence(0);
                            var newToken = sequence[^1];
                            
                            string chunk = tokenizerStream.Decode(newToken);
                            responseText.Append(chunk);
                        }
                    }, ct);

                    return responseText.ToString();
                }
                else
                {
                    // If CPU also failed, propagate the exception
                    throw;
                }
            }
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

            if (choice == "NPU")
            {
                if (await _phiSilica.IsModelReadyAsync()) return _phiSilica;
            }
            else if (choice == "GPU" || choice == "CPU" || choice == "NPU_IntelAmd")
            {
                if (await _onnxGenAi.IsModelReadyAsync()) return _onnxGenAi;
            }
            else // Auto
            {
                // Prioritize Phi Silica if hardware is ready
                if (await _phiSilica.IsModelReadyAsync())
                {
                    return _phiSilica;
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
                throw new InvalidOperationException("No local AI service is ready or configured.");
            }
            return await service.GenerateResponseAsync(systemPrompt, userPrompt, ct);
        }
    }
}
