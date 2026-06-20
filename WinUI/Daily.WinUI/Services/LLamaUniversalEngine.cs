using System;
using System.IO;
using System.Threading.Tasks;
using System.Management;
using LLama;
using LLama.Common;
using LLama.Sampling;

namespace Daily_WinUI.Services
{
    public class LLamaUniversalEngine : ISmartBriefingEngine, IDisposable
    {
        private readonly bool _allowGpuOffload;
        private LLamaWeights? _weights;
        private bool _initialized;
        private string? _loadedModelPath;
        private static readonly object _initLock = new();

        public LLamaUniversalEngine(bool allowGpuOffload)
        {
            _allowGpuOffload = allowGpuOffload;
        }

        public Task<bool> IsSupportedAsync()
        {
            return Task.FromResult(true); // CPU/GPU works everywhere
        }

        public async Task InitializeAsync()
        {
            var settings = SettingsService.Load();
            string selectedModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
            string modelDir = SettingsService.GetModelDirectory(selectedModelId);
            string modelPath = Path.Combine(modelDir, "model.gguf");

            if (_initialized && _loadedModelPath == modelPath && _weights != null) return;

            await Task.Run(() =>
            {
                lock (_initLock)
                {
                    if (_initialized && _loadedModelPath == modelPath && _weights != null) return;

                    // Clean up previous weights before loading new ones
                    _weights?.Dispose();
                    _weights = null;
                    _initialized = false;

                    if (!File.Exists(modelPath))
                    {
                        throw new FileNotFoundException($"GGUF model file not found at {modelPath}. Please download the model in settings.");
                    }

                    var parameters = new ModelParams(modelPath)
                    {
                        ContextSize = 8192,
                        GpuLayerCount = _allowGpuOffload ? 99 : 0 // Offload layers to GPU if allowed
                    };

                    _weights = LLamaWeights.LoadFromFile(parameters);
                    _loadedModelPath = modelPath;
                    _initialized = true;
                }
            });
        }

        public async Task<string> GenerateBriefingAsync(string prompt)
        {
            if (!_initialized || _weights == null || string.IsNullOrEmpty(_loadedModelPath))
            {
                throw new InvalidOperationException("LLamaUniversalEngine is not initialized.");
            }

            return await Task.Run(async () =>
            {
                var parameters = new ModelParams(_loadedModelPath)
                {
                    ContextSize = 8192,
                    GpuLayerCount = _allowGpuOffload ? 99 : 0
                };

                var executor = new StatelessExecutor(_weights, parameters);

                var inferenceParams = new InferenceParams
                {
                    MaxTokens = 1024,
                    AntiPrompts = new[] { "<|eot_id|>", "<|end|>" },
                    SamplingPipeline = new DefaultSamplingPipeline
                    {
                        Temperature = 0.2f,
                        TopP = 0.9f
                    }
                };

                var sb = new System.Text.StringBuilder();
                await foreach (var token in executor.InferAsync(prompt, inferenceParams))
                {
                    sb.Append(token);
                }

                return sb.ToString();
            });
        }

        public void Dispose()
        {
            lock (_initLock)
            {
                _weights?.Dispose();
                _weights = null;
                _loadedModelPath = null;
                _initialized = false;
            }
        }
    }
}
