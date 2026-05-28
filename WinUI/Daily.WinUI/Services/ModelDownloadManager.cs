using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Diagnostics;

namespace Daily_WinUI.Services
{
    public sealed class DownloadProgressEventArgs : EventArgs
    {
        public double Percentage { get; }
        public double SpeedMBs { get; }
        public double DownloadedMBs { get; }
        public double TotalMBs { get; }
        public TimeSpan TimeRemaining { get; }
        public string CurrentFileName { get; }

        public DownloadProgressEventArgs(
            double percentage,
            double speedMBs,
            double downloadedMBs,
            double totalMBs,
            TimeSpan timeRemaining,
            string currentFileName)
        {
            Percentage = percentage;
            SpeedMBs = speedMBs;
            DownloadedMBs = downloadedMBs;
            TotalMBs = totalMBs;
            TimeRemaining = timeRemaining;
            CurrentFileName = currentFileName;
        }
    }

    public sealed class ModelDownloadFile
    {
        public string SourceRelativePath { get; }
        public string TargetFileName { get; }
        public long EstimatedSize { get; }

        public ModelDownloadFile(string sourceRelativePath, string targetFileName, long estimatedSize)
        {
            SourceRelativePath = sourceRelativePath;
            TargetFileName = targetFileName;
            EstimatedSize = estimatedSize;
        }
    }

    public sealed class ModelDownloadInfo
    {
        public string ModelId { get; }
        public string RepoUrl { get; }
        public string FolderName { get; }
        public List<ModelDownloadFile> Files { get; }
        public bool GenerateGenAiConfig { get; }
        public string ModelType { get; }

        public ModelDownloadInfo(string modelId, string repoUrl, string folderName, List<ModelDownloadFile> files, bool generateGenAiConfig, string modelType)
        {
            ModelId = modelId;
            RepoUrl = repoUrl;
            FolderName = folderName;
            Files = files;
            GenerateGenAiConfig = generateGenAiConfig;
            ModelType = modelType;
        }
    }

    public sealed class ModelDownloadManager
    {
        private readonly HttpClient _httpClient;
        
        private static readonly Dictionary<string, ModelDownloadInfo> ModelDefinitions = new()
        {
            {
                "llama32_1b", new ModelDownloadInfo(
                    "llama32_1b",
                    "https://huggingface.co/onnx-community/Llama-3.2-1B-Instruct-GENAI-ONNX/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32-acc-level-4/",
                    "llama1b",
                    new()
                    {
                        new("config.json", "config.json", 50000),
                        new("genai_config.json", "genai_config.json", 1000),
                        new("special_tokens_map.json", "special_tokens_map.json", 100000),
                        new("tokenizer.json", "tokenizer.json", 9100000),
                        new("tokenizer_config.json", "tokenizer_config.json", 100000),
                        new("model.onnx", "model.onnx", 16000000),
                        new("model.onnx.data", "model.onnx.data", 1750000000)
                    },
                    false,
                    "llama"
                )
            },
            {
                "qwen25_15b", new ModelDownloadInfo(
                    "qwen25_15b",
                    "https://huggingface.co/onnx-community/Qwen2.5-1.5B-Instruct/resolve/main/",
                    "qwen15b",
                    new()
                    {
                        new("config.json", "config.json", 1000),
                        new("special_tokens_map.json", "special_tokens_map.json", 1000),
                        new("tokenizer.json", "tokenizer.json", 7100000),
                        new("tokenizer_config.json", "tokenizer_config.json", 1000),
                        new("onnx/model_q4.onnx", "model.onnx", 950000000)
                    },
                    true,
                    "qwen2"
                )
            },
            {
                "gemma3_1b", new ModelDownloadInfo(
                    "gemma3_1b",
                    "https://huggingface.co/onnx-community/gemma-3-1b-it-ONNX/resolve/main/",
                    "gemma1b",
                    new()
                    {
                        new("config.json", "config.json", 1000),
                        new("special_tokens_map.json", "special_tokens_map.json", 1000),
                        new("tokenizer.json", "tokenizer.json", 8100000),
                        new("tokenizer_config.json", "tokenizer_config.json", 1000),
                        new("onnx/model_q4.onnx", "model.onnx", 500000),
                        new("onnx/model_q4.onnx_data", "model_q4.onnx_data", 750000000)
                    },
                    true,
                    "gemma2"
                )
            },
            {
                "phi35_mini", new ModelDownloadInfo(
                    "phi35_mini",
                    "https://huggingface.co/microsoft/Phi-3.5-mini-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-awq-block-128-acc-level-4/",
                    "phi35",
                    new()
                    {
                        new("config.json", "config.json", 50000),
                        new("genai_config.json", "genai_config.json", 1000),
                        new("special_tokens_map.json", "special_tokens_map.json", 100000),
                        new("tokenizer.json", "tokenizer.json", 9100000),
                        new("tokenizer_config.json", "tokenizer_config.json", 100000),
                        new("phi-3.5-mini-instruct-cpu-int4-awq-block-128-acc-level-4.onnx", "model.onnx", 55000000),
                        new("phi-3.5-mini-instruct-cpu-int4-awq-block-128-acc-level-4.onnx.data", "model.onnx.data", 2730000000)
                    },
                    false,
                    "phi"
                )
            }
        };

        private Task? _downloadTask;
        private CancellationTokenSource? _cts;
        private bool _isDownloading;
        private double _percentage;
        private string _statusText = "Not started";
        private DownloadProgressEventArgs? _lastProgress;
        private string? _downloadingModelId;

        public event EventHandler<DownloadProgressEventArgs>? ProgressChanged;
        public event EventHandler<string>? StatusChanged;
        public event EventHandler? DownloadCompleted;
        public event EventHandler<Exception>? DownloadFailed;

        public bool IsDownloading => _isDownloading;
        public double Percentage => _percentage;
        public string StatusText => _statusText;
        public DownloadProgressEventArgs? LastProgress => _lastProgress;
        public string? DownloadingModelId => _downloadingModelId;

        public ModelDownloadManager(HttpClient httpClient)
        {
            _httpClient = httpClient;
            // Set 10-minute timeout for requests
            _httpClient.Timeout = TimeSpan.FromMinutes(10);
        }

        public void StartDownload()
        {
            // Legacy / fallback method: default to Llama 3.2 1B
            StartDownload("llama32_1b");
        }

        public void StartDownload(string modelId)
        {
            lock (this)
            {
                if (_isDownloading) return;
                _isDownloading = true;
                _percentage = 0;
                _statusText = "Starting download...";
                _lastProgress = null;
                _downloadingModelId = modelId;
                _cts = new CancellationTokenSource();
            }

            _downloadTask = Task.Run(async () =>
            {
                try
                {
                    await DownloadModelInternalAsync(modelId, _cts.Token);
                    
                    lock (this)
                    {
                        _isDownloading = false;
                        _statusText = "Download complete.";
                        _percentage = 100;
                    }
                    
                    // Mark model as downloaded and selected in settings
                    var settings = SettingsService.Load();
                    settings.SelectedLocalAiModel = modelId;
                    settings.LocalAiModelDownloaded = true;
                    SettingsService.Save(settings);

                    DownloadCompleted?.Invoke(this, EventArgs.Empty);
                }
                catch (OperationCanceledException)
                {
                    lock (this)
                    {
                        _isDownloading = false;
                        _statusText = "Download canceled.";
                    }
                    DownloadFailed?.Invoke(this, new OperationCanceledException("Download canceled by user."));
                }
                catch (Exception ex)
                {
                    lock (this)
                    {
                        _isDownloading = false;
                        _statusText = $"Download failed: {ex.Message}";
                    }
                    DownloadFailed?.Invoke(this, ex);
                }
                finally
                {
                    lock (this)
                    {
                        _cts?.Dispose();
                        _cts = null;
                        _downloadingModelId = null;
                    }
                }
            });
        }

        public void CancelDownload()
        {
            lock (this)
            {
                if (!_isDownloading) return;
                _statusText = "Canceling download...";
                _cts?.Cancel();
            }
        }

        private async Task DownloadModelInternalAsync(string modelId, CancellationToken ct)
        {
            if (!ModelDefinitions.TryGetValue(modelId, out var info))
            {
                throw new ArgumentException($"Unknown model ID: {modelId}");
            }

            string targetDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Daily.WinUI",
                "models",
                info.FolderName);

            Directory.CreateDirectory(targetDir);
            UpdateStatus("Resolving model sizes...");

            // 1. Get total expected size of all files using headers
            long totalExpectedBytes = 0;
            var fileSizes = new Dictionary<string, long>();

            foreach (var file in info.Files)
            {
                ct.ThrowIfCancellationRequested();
                string fileUrl = $"{info.RepoUrl}{file.SourceRelativePath}";
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Head, fileUrl);
                    using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
                    if (response.IsSuccessStatusCode && response.Content.Headers.ContentLength.HasValue)
                    {
                        long size = response.Content.Headers.ContentLength.Value;
                        fileSizes[file.SourceRelativePath] = size;
                        totalExpectedBytes += size;
                    }
                    else
                    {
                        fileSizes[file.SourceRelativePath] = file.EstimatedSize;
                        totalExpectedBytes += file.EstimatedSize;
                    }
                }
                catch
                {
                    fileSizes[file.SourceRelativePath] = file.EstimatedSize;
                    totalExpectedBytes += file.EstimatedSize;
                }
            }

            long totalBytesDownloaded = 0;
            var stopwatch = Stopwatch.StartNew();
            long lastUpdateMs = 0;

            // 2. Download files sequentially
            byte[] buffer = new byte[81920]; // 80KB buffer
            for (int i = 0; i < info.Files.Count; i++)
            {
                var file = info.Files[i];
                string fileUrl = $"{info.RepoUrl}{file.SourceRelativePath}";
                string targetPath = Path.Combine(targetDir, file.TargetFileName);

                long expectedSize = 0;
                if (fileSizes.TryGetValue(file.SourceRelativePath, out long size))
                {
                    expectedSize = size;
                }

                // If file already exists and size matches, skip it!
                if (expectedSize > 0 && File.Exists(targetPath))
                {
                    var fileInfo = new FileInfo(targetPath);
                    if (fileInfo.Length == expectedSize)
                    {
                        totalBytesDownloaded += expectedSize;
                        UpdateStatus($"Verified {file.TargetFileName} on disk.");
                        continue;
                    }
                }

                UpdateStatus($"Downloading {file.TargetFileName} ({i + 1}/{info.Files.Count})...");

                long fileBytesDownloaded = 0;
                using (var response = await _httpClient.SendAsync(new HttpRequestMessage(HttpMethod.Get, fileUrl), HttpCompletionOption.ResponseHeadersRead, ct))
                {
                    response.EnsureSuccessStatusCode();

                    using (var stream = await response.Content.ReadAsStreamAsync(ct))
                    using (var fileStream = new FileStream(targetPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
                    {
                        int bytesRead;
                        while ((bytesRead = await stream.ReadAsync(buffer, 0, buffer.Length, ct)) > 0)
                        {
                            await fileStream.WriteAsync(buffer, 0, bytesRead, ct);
                            fileBytesDownloaded += bytesRead;
                            totalBytesDownloaded += bytesRead;

                            double elapsedSec = stopwatch.Elapsed.TotalSeconds;
                            double speedMBs = elapsedSec > 0 ? (totalBytesDownloaded / (1024.0 * 1024.0)) / elapsedSec : 0;
                            double percentage = totalExpectedBytes > 0 ? ((double)totalBytesDownloaded / totalExpectedBytes) * 100.0 : 0;
                            
                            double downloadedMBs = totalBytesDownloaded / (1024.0 * 1024.0);
                            double totalMBs = totalExpectedBytes / (1024.0 * 1024.0);

                            double remainingBytes = totalExpectedBytes - totalBytesDownloaded;
                            double remainingSec = speedMBs > 0 ? (remainingBytes / (1024.0 * 1024.0)) / speedMBs : 0;
                            TimeSpan timeRemaining = TimeSpan.FromSeconds(Math.Max(0, remainingSec));

                            var progressArgs = new DownloadProgressEventArgs(
                                percentage,
                                speedMBs,
                                downloadedMBs,
                                totalMBs,
                                timeRemaining,
                                file.TargetFileName
                            );

                            lock (this)
                            {
                                _percentage = percentage;
                                _lastProgress = progressArgs;
                                _statusText = $"Downloading: {file.TargetFileName} ({downloadedMBs:F1}/{totalMBs:F1} MB) | Speed: {speedMBs:F2} MB/s | Remaining: {timeRemaining:mm\\:ss}";
                            }

                            // Throttle updates to UI at max once every 250ms
                            long currentMs = stopwatch.ElapsedMilliseconds;
                            if (currentMs - lastUpdateMs >= 250 || percentage >= 100.0)
                            {
                                lastUpdateMs = currentMs;
                                ProgressChanged?.Invoke(this, progressArgs);
                            }
                        }
                    }
                }

                // Check for truncation (safely outside using block, so file is unlocked)
                if (expectedSize > 0 && fileBytesDownloaded < expectedSize)
                {
                    try { File.Delete(targetPath); } catch { }
                    throw new IOException($"Download truncated for {file.TargetFileName}. Expected {expectedSize} bytes, but only received {fileBytesDownloaded} bytes.");
                }
            }

            stopwatch.Stop();

            // 3. Generate genai_config.json if requested
            if (info.GenerateGenAiConfig)
            {
                UpdateStatus("Generating GenAI configuration...");
                string genaiConfigPath = Path.Combine(targetDir, "genai_config.json");
                string json;
                if (info.ModelId == "qwen25_15b")
                {
                    json = @"{
  ""model"": {
    ""type"": ""qwen2"",
    ""decoder"": {
      ""filename"": ""model.onnx""
    }
  },
  ""search"": {
    ""bos_token_id"": 151643,
    ""eos_token_id"": 151645,
    ""pad_token_id"": 151643,
    ""max_length"": 2048
  }
}";
                }
                else // gemma3_1b
                {
                    json = @"{
  ""model"": {
    ""type"": ""gemma2"",
    ""decoder"": {
      ""filename"": ""model.onnx""
    }
  },
  ""search"": {
    ""bos_token_id"": 2,
    ""eos_token_id"": 106,
    ""pad_token_id"": 0,
    ""max_length"": 2048
  }
}";
                }
                await File.WriteAllTextAsync(genaiConfigPath, json, ct);
            }

            UpdateStatus("Verifying model files...");
        }

        private void UpdateStatus(string status)
        {
            lock (this)
            {
                _statusText = status;
            }
            StatusChanged?.Invoke(this, status);
        }
    }
}
