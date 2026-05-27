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

    public sealed class ModelDownloadManager
    {
        private readonly HttpClient _httpClient;
        private readonly string _targetDir;
        private const string BaseUrl = "https://huggingface.co/onnx-community/Llama-3.2-1B-Instruct-GENAI-ONNX/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32-acc-level-4/";

        private readonly List<string> _files = new()
        {
            "config.json",
            "genai_config.json",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "model.onnx",
            "model.onnx.data"
        };

        private Task? _downloadTask;
        private CancellationTokenSource? _cts;
        private bool _isDownloading;
        private double _percentage;
        private string _statusText = "Not started";
        private DownloadProgressEventArgs? _lastProgress;

        public event EventHandler<DownloadProgressEventArgs>? ProgressChanged;
        public event EventHandler<string>? StatusChanged;
        public event EventHandler? DownloadCompleted;
        public event EventHandler<Exception>? DownloadFailed;

        public bool IsDownloading => _isDownloading;
        public double Percentage => _percentage;
        public string StatusText => _statusText;
        public DownloadProgressEventArgs? LastProgress => _lastProgress;

        public ModelDownloadManager(HttpClient httpClient)
        {
            _httpClient = httpClient;
            // Set 10-minute timeout for requests
            _httpClient.Timeout = TimeSpan.FromMinutes(10);
            _targetDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Daily.WinUI",
                "models",
                "llama1b");
        }

        public void StartDownload()
        {
            lock (this)
            {
                if (_isDownloading) return;
                _isDownloading = true;
                _percentage = 0;
                _statusText = "Starting download...";
                _lastProgress = null;
                _cts = new CancellationTokenSource();
            }

            _downloadTask = Task.Run(async () =>
            {
                try
                {
                    await DownloadModelInternalAsync(_cts.Token);
                    
                    lock (this)
                    {
                        _isDownloading = false;
                        _statusText = "Download complete.";
                        _percentage = 100;
                    }
                    
                    // Mark model as downloaded in settings
                    var settings = SettingsService.Load();
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

        private async Task DownloadModelInternalAsync(CancellationToken ct)
        {
            Directory.CreateDirectory(_targetDir);
            UpdateStatus("Resolving model sizes...");

            // 1. Get total expected size of all files using headers
            long totalExpectedBytes = 0;
            var fileSizes = new Dictionary<string, long>();

            foreach (var file in _files)
            {
                ct.ThrowIfCancellationRequested();
                string fileUrl = $"{BaseUrl}{file}";
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Head, fileUrl);
                    using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
                    if (response.IsSuccessStatusCode && response.Content.Headers.ContentLength.HasValue)
                    {
                        long size = response.Content.Headers.ContentLength.Value;
                        fileSizes[file] = size;
                        totalExpectedBytes += size;
                    }
                    else
                    {
                        // Fallback estimate if HEAD fails (approx ~1776MB total)
                        fileSizes[file] = file == "model.onnx.data" ? 1750000000 : (file == "model.onnx" ? 16000000 : (file == "tokenizer.json" ? 9100000 : 100000));
                        totalExpectedBytes += fileSizes[file];
                    }
                }
                catch
                {
                    fileSizes[file] = file == "model.onnx.data" ? 1750000000 : (file == "model.onnx" ? 16000000 : (file == "tokenizer.json" ? 9100000 : 100000));
                    totalExpectedBytes += fileSizes[file];
                }
            }

            long totalBytesDownloaded = 0;
            var stopwatch = Stopwatch.StartNew();
            long lastUpdateMs = 0;

            // 2. Download files sequentially
            byte[] buffer = new byte[81920]; // 80KB buffer
            for (int i = 0; i < _files.Count; i++)
            {
                string file = _files[i];
                string fileUrl = $"{BaseUrl}{file}";
                string targetPath = Path.Combine(_targetDir, file);

                long expectedSize = 0;
                if (fileSizes.TryGetValue(file, out long size))
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
                        UpdateStatus($"Verified {file} on disk.");
                        continue;
                    }
                }

                UpdateStatus($"Downloading {file} ({i + 1}/{_files.Count})...");

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
                                file
                            );

                            lock (this)
                            {
                                _percentage = percentage;
                                _lastProgress = progressArgs;
                                _statusText = $"Downloading: {file} ({downloadedMBs:F1}/{totalMBs:F1} MB) | Speed: {speedMBs:F2} MB/s | Remaining: {timeRemaining:mm\\:ss}";
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
                    throw new IOException($"Download truncated for {file}. Expected {expectedSize} bytes, but only received {fileBytesDownloaded} bytes.");
                }
            }

            stopwatch.Stop();
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
