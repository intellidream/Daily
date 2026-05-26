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
        private readonly string _modelPath;

        public OnnxGenAiSmartService()
        {
            _modelPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Daily.WinUI",
                "models",
                "llama1b");
        }

        public Task<bool> IsModelReadyAsync()
        {
            // Verify model file exists
            string filePath = Path.Combine(_modelPath, "model.onnx");
            bool ready = Directory.Exists(_modelPath) && File.Exists(filePath);
            return Task.FromResult(ready);
        }

        private async Task EnsureLoadedAsync()
        {
            if (_model == null)
            {
                if (!await IsModelReadyAsync())
                {
                    throw new InvalidOperationException("ONNX model is not downloaded or verified yet.");
                }

                await Task.Run(() =>
                {
                    _model = new Model(_modelPath);
                    _tokenizer = new Tokenizer(_model);
                });
            }
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
        {
            await EnsureLoadedAsync();

            if (_model == null || _tokenizer == null)
            {
                throw new InvalidOperationException("ONNX model could not be loaded.");
            }

            // Llama 3 Chat Format
            string formattedPrompt = $"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";

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
                    
                    var sequence = generator.GetSequence(0);
                    var newToken = sequence[^1];
                    
                    string chunk = tokenizerStream.Decode(newToken);
                    responseText.Append(chunk);
                }
            }, ct);

            return responseText.ToString();
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
