using System;
using System.IO;
using System.IO.Pipes;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Daily_WinUI.DesktopWidgets
{
    public static class WidgetsHostIpc
    {
        public const string MutexName = "Daily_WidgetsHost_SingleInstance_Mutex";
        public const string PipeName = "Daily_WidgetsHost_IpcPipe";

        /// <summary>
        /// True when this code is executing inside the Daily.WidgetsHost.exe process.
        /// </summary>
        public static bool IsRunningInHostProcess { get; set; } = false;

        public static string GetHostExecutablePath()
        {
            var baseDir = AppContext.BaseDirectory;
            var localPath = Path.Combine(baseDir, "Daily.WidgetsHost.exe");
            var candidates = new System.Collections.Generic.List<string>();
            if (File.Exists(localPath))
            {
                candidates.Add(localPath);
            }

            // Search parallel build directories in dev environment and prefer newest build
            try
            {
                var dir = new DirectoryInfo(baseDir);
                while (dir != null && !dir.Name.Equals("WinUI", StringComparison.OrdinalIgnoreCase) && dir.Parent != null)
                {
                    dir = dir.Parent;
                }

                if (dir != null && dir.Name.Equals("WinUI", StringComparison.OrdinalIgnoreCase))
                {
                    var hostBin = Path.Combine(dir.FullName, "Daily.WidgetsHost", "bin");
                    if (Directory.Exists(hostBin))
                    {
                        var archTag = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64
                            ? "win-arm64"
                            : "win-x64";
                        var found = Directory.GetFiles(hostBin, "Daily.WidgetsHost.exe", SearchOption.AllDirectories);
                        var archMatched = found.Where(p => p.Contains(archTag, StringComparison.OrdinalIgnoreCase)).ToArray();
                        candidates.AddRange(archMatched.Length > 0 ? archMatched : found);
                    }
                }
            }
            catch { }

            if (candidates.Count > 0)
            {
                return candidates.OrderByDescending(File.GetLastWriteTimeUtc).First();
            }

            return localPath;
        }

        public static bool IsHostAvailable()
        {
            if (IsRunningInHostProcess) return false;
            return File.Exists(GetHostExecutablePath());
        }

        public static bool IsHostRunning()
        {
            if (IsRunningInHostProcess) return true;
            try
            {
                using var mutex = Mutex.OpenExisting(MutexName);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public static async Task<bool> SendCommandAsync(string command, int timeoutMs = 1500)
        {
            try
            {
                using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
                using var cts = new CancellationTokenSource(timeoutMs);
                await client.ConnectAsync(cts.Token);
                using var writer = new StreamWriter(client) { AutoFlush = true };
                await writer.WriteLineAsync(command.AsMemory(), cts.Token);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public static void EnsureHostRunning()
        {
            if (IsRunningInHostProcess) return;
            string exePath = GetHostExecutablePath();
            if (!File.Exists(exePath)) return;

            if (IsHostRunning())
            {
                try
                {
                    var latestWriteUtc = File.GetLastWriteTimeUtc(exePath);
                    var runningHost = Process.GetProcessesByName("Daily.WidgetsHost").FirstOrDefault();
                    var runningExe = runningHost?.MainModule?.FileName;
                    if (!string.IsNullOrEmpty(runningExe) && File.GetLastWriteTimeUtc(runningExe) < latestWriteUtc.AddSeconds(-2))
                    {
                        _ = Task.Run(async () =>
                        {
                            await SendCommandAsync("shutdown", 800);
                            await Task.Delay(350);
                            try
                            {
                                Process.Start(new ProcessStartInfo
                                {
                                    FileName = exePath,
                                    UseShellExecute = true,
                                    CreateNoWindow = true,
                                    WindowStyle = ProcessWindowStyle.Hidden
                                });
                            }
                            catch { }
                        });
                    }
                }
                catch { }
                return;
            }

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = exePath,
                    UseShellExecute = true,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[WidgetsHostIpc] EnsureHostRunning warning: {ex.Message}");
            }
        }

        public static void ForwardNavigationToMainApp(int tabIndex)
        {
            Task.Run(async () =>
            {
                try
                {
                    using var client = new NamedPipeClientStream(".", "DailyWinUI_ProtocolPipe", PipeDirection.Out);
                    using var cts = new CancellationTokenSource(600);
                    await client.ConnectAsync(cts.Token);
                    using var writer = new StreamWriter(client) { AutoFlush = true };
                    await writer.WriteLineAsync($"nav:{tabIndex}".AsMemory(), cts.Token);
                    return;
                }
                catch
                {
                    // Main app is not running; launch it
                }

                try
                {
                    var baseDir = AppContext.BaseDirectory;
                    var winUiExe = Path.Combine(baseDir, "Daily.WinUI.exe");
                    if (!File.Exists(winUiExe))
                    {
                        var dir = new DirectoryInfo(baseDir);
                        while (dir != null && !dir.Name.Equals("WinUI", StringComparison.OrdinalIgnoreCase) && dir.Parent != null)
                        {
                            dir = dir.Parent;
                        }

                        if (dir != null && dir.Name.Equals("WinUI", StringComparison.OrdinalIgnoreCase))
                        {
                            var winUiBin = Path.Combine(dir.FullName, "Daily.WinUI", "bin");
                            if (Directory.Exists(winUiBin))
                            {
                                var candidates = Directory.GetFiles(winUiBin, "Daily.WinUI.exe", SearchOption.AllDirectories);
                                if (candidates.Length > 0)
                                {
                                    winUiExe = candidates.OrderByDescending(File.GetLastWriteTimeUtc).First();
                                }
                            }
                        }
                    }

                    if (File.Exists(winUiExe))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = winUiExe,
                            Arguments = $"--nav:{tabIndex}",
                            UseShellExecute = true
                        });
                    }
                    else
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = $"com.intellidream.daily.desktop://navigate?tab={tabIndex}",
                            UseShellExecute = true
                        });
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"[WidgetsHostIpc] Failed to launch main app: {ex.Message}");
                }
            });
        }

        public static void NotifyMainApp(string command)
        {
            if (string.IsNullOrWhiteSpace(command)) return;
            Task.Run(async () =>
            {
                try
                {
                    using var client = new NamedPipeClientStream(".", "DailyWinUI_ProtocolPipe", PipeDirection.Out);
                    using var cts = new CancellationTokenSource(600);
                    await client.ConnectAsync(cts.Token);
                    using var writer = new StreamWriter(client) { AutoFlush = true };
                    await writer.WriteLineAsync(command.AsMemory(), cts.Token);
                }
                catch { }
            });
        }

        public static void ForwardUriToMainApp(string uriString)
        {
            if (string.IsNullOrWhiteSpace(uriString)) return;
            Task.Run(async () =>
            {
                try
                {
                    using var client = new NamedPipeClientStream(".", "DailyWinUI_ProtocolPipe", PipeDirection.Out);
                    using var cts = new CancellationTokenSource(700);
                    await client.ConnectAsync(cts.Token);
                    using var writer = new StreamWriter(client) { AutoFlush = true };
                    await writer.WriteLineAsync(uriString.AsMemory(), cts.Token);
                    return;
                }
                catch
                {
                    // Main app is not running; launch it with URI
                }

                try
                {
                    var baseDir = AppContext.BaseDirectory;
                    var winUiExe = Path.Combine(baseDir, "Daily.WinUI.exe");
                    if (!File.Exists(winUiExe))
                    {
                        var dir = new DirectoryInfo(baseDir);
                        while (dir != null && !dir.Name.Equals("WinUI", StringComparison.OrdinalIgnoreCase) && dir.Parent != null)
                        {
                            dir = dir.Parent;
                        }
                        if (dir != null && dir.Name.Equals("WinUI", StringComparison.OrdinalIgnoreCase))
                        {
                            var winUiBin = Path.Combine(dir.FullName, "Daily.WinUI", "bin");
                            if (Directory.Exists(winUiBin))
                            {
                                var candidates = Directory.GetFiles(winUiBin, "Daily.WinUI.exe", SearchOption.AllDirectories);
                                if (candidates.Length > 0)
                                {
                                    winUiExe = candidates.OrderByDescending(File.GetLastWriteTimeUtc).First();
                                }
                            }
                        }
                    }

                    if (File.Exists(winUiExe))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = winUiExe,
                            Arguments = $"\"{uriString}\"",
                            UseShellExecute = true
                        });
                    }
                    else
                    {
                        ForwardNavigationToMainApp(3);
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"[WidgetsHostIpc] ForwardUriToMainApp failed: {ex.Message}");
                }
            });
        }
    }
}
