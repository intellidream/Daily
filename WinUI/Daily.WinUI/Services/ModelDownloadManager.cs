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
            "model.onnx"
        };

        public event EventHandler<DownloadProgressEventArgs>? ProgressChanged;
        public event EventHandler<string>? StatusChanged;

        public ModelDownloadManager(HttpClient httpClient)
        {
            _httpClient = httpClient;
            _targetDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Daily.WinUI",
                "models",
                "llama1b");
        }

        public async Task DownloadModelAsync(CancellationToken ct = default)
        {
            Directory.CreateDirectory(_targetDir);
            StatusChanged?.Invoke(this, "Resolving model sizes...");

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
                        // Fallback estimate if HEAD fails (approx ~670MB)
                        fileSizes[file] = file == "model.onnx" ? 656000000 : (file == "tokenizer.json" ? 9100000 : 100000);
                        totalExpectedBytes += fileSizes[file];
                    }
                }
                catch
                {
                    fileSizes[file] = file == "model.onnx" ? 656000000 : (file == "tokenizer.json" ? 9100000 : 100000);
                    totalExpectedBytes += fileSizes[file];
                }
            }

            long totalBytesDownloaded = 0;
            var stopwatch = Stopwatch.StartNew();

            // 2. Download files sequentially
            byte[] buffer = new byte[81920]; // 80KB buffer
            for (int i = 0; i < _files.Count; i++)
            {
                string file = _files[i];
                string fileUrl = $"{BaseUrl}{file}";
                string targetPath = Path.Combine(_targetDir, file);

                StatusChanged?.Invoke(this, $"Downloading {file} ({i + 1}/{_files.Count})...");

                using var response = await _httpClient.SendAsync(new HttpRequestMessage(HttpMethod.Get, fileUrl), HttpCompletionOption.ResponseHeadersRead, ct);
                response.EnsureSuccessStatusCode();

                using var stream = await response.Content.ReadAsStreamAsync(ct);
                using var fileStream = new FileStream(targetPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

                int bytesRead;
                while ((bytesRead = await stream.ReadAsync(buffer, 0, buffer.Length, ct)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, bytesRead, ct);
                    totalBytesDownloaded += bytesRead;

                    double elapsedSec = stopwatch.Elapsed.TotalSeconds;
                    double speedMBs = elapsedSec > 0 ? (totalBytesDownloaded / (1024.0 * 1024.0)) / elapsedSec : 0;
                    double percentage = totalExpectedBytes > 0 ? ((double)totalBytesDownloaded / totalExpectedBytes) * 100.0 : 0;
                    
                    double downloadedMBs = totalBytesDownloaded / (1024.0 * 1024.0);
                    double totalMBs = totalExpectedBytes / (1024.0 * 1024.0);

                    double remainingBytes = totalExpectedBytes - totalBytesDownloaded;
                    double remainingSec = speedMBs > 0 ? (remainingBytes / (1024.0 * 1024.0)) / speedMBs : 0;
                    TimeSpan timeRemaining = TimeSpan.FromSeconds(Math.Max(0, remainingSec));

                    ProgressChanged?.Invoke(this, new DownloadProgressEventArgs(
                        percentage,
                        speedMBs,
                        downloadedMBs,
                        totalMBs,
                        timeRemaining,
                        file
                    ));
                }
            }

            stopwatch.Stop();
            StatusChanged?.Invoke(this, "Verifying model files...");
        }
    }
}
