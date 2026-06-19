using System;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace Daily_WinUI.Services
{
    public class AIManager : ISmartBriefingEngine, IDisposable
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(string lpLibFileName, IntPtr hFile, uint dwFlags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FreeLibrary(IntPtr hLibModule);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetDllDirectory(string lpPathName);

        private const uint LOAD_WITH_ALTERED_SEARCH_PATH = 0x00000008;

        private readonly PhiSilicaNpuEngine _npuEngine;
        private readonly LLamaUniversalEngine _gpuEngine;
        private readonly LLamaUniversalEngine _cpuEngine;
        
        private ISmartBriefingEngine? _activeEngine;
        private string _activeEngineName = "Uninitialized";
        private IntPtr _cpuBackendHandle = IntPtr.Zero;

        public ISmartBriefingEngine? ActiveEngine => _activeEngine;
        public string ActiveEngineName => _activeEngineName;
        public bool HasDedicatedGpu => DetectDedicatedGpu(out _);

        public AIManager()
        {
            _npuEngine = new PhiSilicaNpuEngine();
            _gpuEngine = new LLamaUniversalEngine(allowGpuOffload: true);
            _cpuEngine = new LLamaUniversalEngine(allowGpuOffload: false);
        }

        public Task<bool> IsSupportedAsync()
        {
            return Task.FromResult(true); // Always supported (falls back to CPU if needed)
        }

        public async Task InitializeAsync()
        {
            var settings = SettingsService.Load();
            string selectedAcc = settings.SelectedAiAccelerator ?? "Auto";
            Console.WriteLine($"[AIManager] Initializing AI Manager. Selected Accelerator: {selectedAcc}");

            // Route 1: Explicit CPU Selection
            if (selectedAcc.Equals("CPU", StringComparison.OrdinalIgnoreCase))
            {
                await InitializeCpuEngineAsync();
                return;
            }

            // Route 2: Explicit Qualcomm NPU Selection
            if (selectedAcc.Equals("NPU", StringComparison.OrdinalIgnoreCase))
            {
                if (await TryInitializeNpuAsync())
                {
                    return;
                }
                Console.WriteLine("[AIManager] NPU not supported/failed. Falling back to CPU.");
                await InitializeCpuEngineAsync();
                return;
            }

            // Route 3: Explicit GPU Selection
            if (selectedAcc.Equals("GPU", StringComparison.OrdinalIgnoreCase))
            {
                if (await TryInitializeGpuAsync(forceGpuCheck: true))
                {
                    return;
                }
                Console.WriteLine("[AIManager] GPU initialization failed. Falling back to CPU.");
                await InitializeCpuEngineAsync();
                return;
            }

            // Route 4: Intel/AMD NPU Selection (Not supported locally, fallback to CPU)
            if (selectedAcc.Equals("NPU_IntelAmd", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("[AIManager] Intel/AMD NPU is not supported directly yet. Falling back to CPU...");
                await InitializeCpuEngineAsync();
                return;
            }

            // Route 5: Auto selection (best available)
            if (selectedAcc.Equals("Auto", StringComparison.OrdinalIgnoreCase))
            {
                // 1. Try Qualcomm NPU first
                if (await TryInitializeNpuAsync())
                {
                    return;
                }

                // 2. Try GPU
                if (await TryInitializeGpuAsync(forceGpuCheck: true))
                {
                    return;
                }

                // 3. Fallback to CPU
                await InitializeCpuEngineAsync();
                return;
            }

            // Fallback for any other case
            await InitializeCpuEngineAsync();
        }

        private void SetActiveEngine(ISmartBriefingEngine engine, string name)
        {
            if (_activeEngine != engine)
            {
                if (_activeEngine is IDisposable disposable)
                {
                    try
                    {
                        disposable.Dispose();
                        Console.WriteLine($"[AIManager] Disposed previously active engine: {_activeEngineName}");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[AIManager] Error disposing previously active engine: {ex.Message}");
                    }
                }
            }
            _activeEngine = engine;
            _activeEngineName = name;
        }

        private async Task InitializeCpuEngineAsync()
        {
            Console.WriteLine("[AIManager] Initializing Tier 3: LLamaUniversalEngine (Strict CPU mode)...");
            try
            {
                LLama.Native.NativeLibraryConfig.All.WithLibrary(null, null); // Clear custom library settings to force auto-detect
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AIManager] Warning: could not reset NativeLibraryConfig: {ex.Message}");
            }

            await _cpuEngine.InitializeAsync();
            SetActiveEngine(_cpuEngine, "CPU Fallback Mode");
        }

        private async Task<bool> TryInitializeNpuAsync()
        {
            try
            {
                var settings = SettingsService.Load();
                if (!settings.UseWindowsInternalAi)
                {
                    Console.WriteLine("[AIManager] NPU engine requested but UseWindowsInternalAi is disabled in settings.");
                    LlmDebugLogger.InitializationError += "[NPU Status] UseWindowsInternalAi is disabled in settings.\n\n";
                    return false;
                }

                if (await _npuEngine.IsSupportedAsync())
                {
                    Console.WriteLine("[AIManager] Attempting to load Tier 1: Phi Silica NPU Engine...");
                    await _npuEngine.InitializeAsync();
                    SetActiveEngine(_npuEngine, "Qualcomm Hexagon NPU (Phi Silica)");
                    return true;
                }
                else
                {
                    LlmDebugLogger.InitializationError += "[NPU Status] Phi Silica NPU engine is not supported on this device.\n\n";
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AIManager] NPU Engine initialization failed: {ex.Message}");
                LlmDebugLogger.InitializationError += $"[NPU Init Error] {ex.Message}\n{ex.StackTrace}\n\n";
            }
            return false;
        }

        private async Task<bool> TryInitializeGpuAsync(bool forceGpuCheck)
        {
            bool gpuSelected = false;
            string gpuMode = "";
            string gpuPath = "";
            string gpuName = "";

            try
            {
                bool hasGpu = DetectDedicatedGpu(out gpuName);
                if (hasGpu || forceGpuCheck)
                {
                    if (!hasGpu)
                    {
                        gpuName = "Generic Graphics Card (Forced)";
                    }

                    bool isNvidia = gpuName.ToLowerInvariant().Contains("nvidia") || 
                                    gpuName.ToLowerInvariant().Contains("geforce") || 
                                    gpuName.ToLowerInvariant().Contains("quadro") || 
                                    gpuName.ToLowerInvariant().Contains("rtx");
                    
                    string targetBackend = isNvidia ? "cuda12" : "vulkan";
                    string arch = RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant();
                    string archFolder = arch.Contains("arm64") ? "win-arm64" : "win-x64";
                    
                    string dllPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "runtimes", archFolder, "native", targetBackend, "llama.dll");

                    Console.WriteLine($"[AIManager] GPU detected/requested: {gpuName}. Target: {targetBackend}. Path: {dllPath}");

                    if (File.Exists(dllPath))
                    {
                        if (TestBackendLoadable(targetBackend))
                        {
                            gpuSelected = true;
                            gpuMode = targetBackend;
                            gpuPath = dllPath;
                            Console.WriteLine($"[AIManager] DLL {targetBackend} verified successfully.");
                        }
                        else
                        {
                            Console.WriteLine($"[AIManager] Verification failed for {targetBackend}.");
                            LlmDebugLogger.InitializationError += $"[GPU Verification Failed] Verification failed for target backend: {targetBackend}.\n";
                            // If Nvidia failed, try Vulkan as a fallback
                            if (isNvidia)
                            {
                                string vulkanDllPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "runtimes", archFolder, "native", "vulkan", "llama.dll");
                                if (File.Exists(vulkanDllPath) && TestBackendLoadable("vulkan"))
                                {
                                    gpuSelected = true;
                                    gpuMode = "vulkan";
                                    gpuPath = vulkanDllPath;
                                    Console.WriteLine("[AIManager] NVIDIA failed to load CUDA, but Vulkan verified successfully.");
                                }
                                else
                                {
                                    LlmDebugLogger.InitializationError += "[GPU Verification Failed] Fallback Vulkan verification also failed or DLL not found.\n\n";
                                }
                            }
                        }
                    }
                    else
                    {
                        Console.WriteLine($"[AIManager] GPU backend DLL not found at: {dllPath}");
                        LlmDebugLogger.InitializationError += $"[GPU DLL Not Found] DLL not found at: {dllPath}\n\n";
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AIManager] Error during GPU detection or verification: {ex.Message}");
                LlmDebugLogger.InitializationError += $"[GPU Detection Error] {ex.Message}\n{ex.StackTrace}\n\n";
            }

            if (gpuSelected)
            {
                try
                {
                    PreloadCpuBackend();
                    Console.WriteLine($"[AIManager] Configuring LLamaSharp to load GPU backend: {gpuMode} ({gpuPath})");
                    LLama.Native.NativeLibraryConfig.All.WithLibrary(gpuPath, null);
                    
                    await _gpuEngine.InitializeAsync();
                    SetActiveEngine(_gpuEngine, $"GPU Acceleration ({gpuMode})");
                    return true;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[AIManager] Failed to initialize GPU engine even after successful child process dry-run: {ex.Message}");
                    LlmDebugLogger.InitializationError += $"[GPU Init Error] Failed to initialize GPU engine: {ex.Message}\n{ex.StackTrace}\n\n";
                }
            }

            return false;
        }

        public async Task<string> GenerateBriefingAsync(string prompt)
        {
            if (_activeEngine == null)
            {
                Console.WriteLine("[AIManager] Active engine is uninitialized. Running InitializeAsync now.");
                await InitializeAsync();
            }

            if (_activeEngine == null)
            {
                throw new InvalidOperationException("Failed to initialize any local AI briefing engines.");
            }

            return await _activeEngine.GenerateBriefingAsync(prompt);
        }

        private bool DetectDedicatedGpu(out string gpuName)
        {
            gpuName = "";
            try
            {
                using var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_VideoController");
                using var collection = searcher.Get();
                foreach (var obj in collection)
                {
                    var name = obj["Name"]?.ToString() ?? "";
                    var desc = obj["Description"]?.ToString() ?? "";
                    var vendor = obj["AdapterCompatibility"]?.ToString() ?? "";
                    string searchString = $"{name} {desc} {vendor}".ToLowerInvariant();

                    if (searchString.Contains("microsoft basic render") || searchString.Contains("virtual") || searchString.Contains("citrix"))
                    {
                        continue;
                    }

                    // Check for dedicated graphics cards
                    if (searchString.Contains("nvidia") || searchString.Contains("geforce") || searchString.Contains("quadro") || searchString.Contains("rtx") ||
                        searchString.Contains("amd") || searchString.Contains("radeon") || searchString.Contains("rx"))
                    {
                        gpuName = name;
                        return true;
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AIManager] Error querying WMI for GPU: {ex.Message}");
            }
            return false;
        }

        private bool TestBackendLoadable(string backend)
        {
            try
            {
                string runtimesRoot = AppDomain.CurrentDomain.BaseDirectory;
                string arch = RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant();
                string archFolder = arch.Contains("arm64") ? "win-arm64" : "win-x64";
                
                string backendDir = Path.Combine(runtimesRoot, "runtimes", archFolder, "native", backend);
                string dllPath = Path.Combine(backendDir, "llama.dll");
                
                if (!File.Exists(dllPath))
                {
                    Console.WriteLine($"[AIManager] DLL not found at: {dllPath}");
                    return false;
                }

                // Add backendDir to search path
                SetDllDirectory(backendDir);

                string[] libsToLoad;
                if (backend.Equals("vulkan", StringComparison.OrdinalIgnoreCase))
                {
                    libsToLoad = new[] { "ggml-base.dll", "ggml-vulkan.dll", "ggml.dll", "llama.dll" };
                }
                else if (backend.Equals("cuda12", StringComparison.OrdinalIgnoreCase))
                {
                    libsToLoad = new[] { "ggml-base.dll", "ggml.dll", "llama.dll" };
                }
                else
                {
                    libsToLoad = new[] { "ggml-base.dll", "ggml-cpu.dll", "ggml.dll", "llama.dll" };
                }

                var loadedHandles = new System.Collections.Generic.List<IntPtr>();
                bool success = true;

                // Pre-load CPU backend dll from the appropriate subfolder as it is a dependency
                string[] cpuFolders = { "avx2", "avx", "noavx" };
                foreach (var folder in cpuFolders)
                {
                    string cpuDllPath = Path.Combine(runtimesRoot, "runtimes", archFolder, "native", folder, "ggml-cpu.dll");
                    if (File.Exists(cpuDllPath))
                    {
                        IntPtr hCpu = LoadLibraryEx(cpuDllPath, IntPtr.Zero, LOAD_WITH_ALTERED_SEARCH_PATH);
                        if (hCpu != IntPtr.Zero)
                        {
                            loadedHandles.Add(hCpu);
                            break;
                        }
                    }
                }

                foreach (var libName in libsToLoad)
                {
                    if (libName == "ggml-cpu.dll" && loadedHandles.Count > 0)
                    {
                        continue;
                    }

                    string fullLibPath = Path.Combine(backendDir, libName);
                    if (File.Exists(fullLibPath))
                    {
                        IntPtr handle = LoadLibraryEx(fullLibPath, IntPtr.Zero, LOAD_WITH_ALTERED_SEARCH_PATH);
                        if (handle == IntPtr.Zero)
                        {
                            int err = Marshal.GetLastWin32Error();
                            Console.WriteLine($"[AIManager] Failed to load {libName}. Win32 Error: {err}");
                            success = false;
                            break;
                        }
                        loadedHandles.Add(handle);
                    }
                    else
                    {
                        if (libName == "llama.dll" || libName == "ggml.dll" || libName == "ggml-base.dll")
                        {
                            Console.WriteLine($"[AIManager] Required library {libName} not found.");
                            success = false;
                            break;
                        }
                    }
                }

                // Free all handles we loaded during verification
                foreach (var h in loadedHandles)
                {
                    FreeLibrary(h);
                }
                SetDllDirectory(null);

                return success;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AIManager] Error verifying loadability for {backend}: {ex.Message}");
                SetDllDirectory(null);
                return false;
            }
        }

        private void PreloadCpuBackend()
        {
            if (_cpuBackendHandle != IntPtr.Zero) return;

            try
            {
                string arch = RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant();
                string archFolder = arch.Contains("arm64") ? "win-arm64" : "win-x64";
                
                string[] cpuFolders = { "avx2", "avx", "noavx" };
                foreach (var folder in cpuFolders)
                {
                    string cpuDllPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "runtimes", archFolder, "native", folder, "ggml-cpu.dll");
                    if (File.Exists(cpuDllPath))
                    {
                        Console.WriteLine($"[AIManager] Pre-loading CPU backend dependency: {cpuDllPath}");
                        
                        string cpuDir = Path.GetDirectoryName(cpuDllPath) ?? "";
                        if (!string.IsNullOrEmpty(cpuDir))
                        {
                            SetDllDirectory(cpuDir);
                        }

                        IntPtr handle = LoadLibraryEx(cpuDllPath, IntPtr.Zero, LOAD_WITH_ALTERED_SEARCH_PATH);
                        
                        SetDllDirectory(null);

                        if (handle != IntPtr.Zero)
                        {
                            _cpuBackendHandle = handle;
                            Console.WriteLine($"[AIManager] Successfully preloaded CPU backend from: {folder}");
                            break;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AIManager] Failed to preload CPU backend dependency: {ex.Message}");
            }
        }

        public void Dispose()
        {
            _gpuEngine.Dispose();
            _cpuEngine.Dispose();

            if (_cpuBackendHandle != IntPtr.Zero)
            {
                FreeLibrary(_cpuBackendHandle);
                _cpuBackendHandle = IntPtr.Zero;
            }

            _activeEngine = null;
            _activeEngineName = "Disposed";
        }
    }
}
