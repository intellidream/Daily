using System;
using System.Diagnostics;

#if ANDROID
using Android.App;
using Android.Content;
#endif

namespace Daily.Services
{
    public interface ISystemMonitorService
    {
        double GetCpuUsage();
        double GetMemoryUsage();
    }

    public class SystemMonitorService : ISystemMonitorService
    {
#if WINDOWS
        private PerformanceCounter? _cpuCounter;
        private PerformanceCounter? _ramCounter;
#elif ANDROID
        private TimeSpan _lastTotalProcessorTime;
        private DateTime _lastCheckTime;
#endif

        public SystemMonitorService()
        {
            InitializeCounters();
        }

        private void InitializeCounters()
        {
#if WINDOWS
            try
            {
                // Note: This might require specific permissions or might throw if counters are missing.
                // "_Total" gives the total processor usage across all cores.
                _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
                // "% Committed Bytes In Use" gives a good approximation of memory load.
                _ramCounter = new PerformanceCounter("Memory", "% Committed Bytes In Use");
                
                // First call usually returns 0, so we call it once to initialize.
                _cpuCounter.NextValue();
                _ramCounter.NextValue();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to initialize PerformanceCounters: {ex.Message}");
            }
#endif
        }

        public double GetCpuUsage()
        {
#if WINDOWS
            try
            {
                return _cpuCounter?.NextValue() ?? 0;
            }
            catch
            {
                return 0;
            }
#elif ANDROID
            try
            {
                var currentProcess = Process.GetCurrentProcess();
                var currentTotalProcessorTime = currentProcess.TotalProcessorTime;
                var currentTime = DateTime.UtcNow;

                if (_lastCheckTime != DateTime.MinValue)
                {
                    var cpuUsedMs = (currentTotalProcessorTime - _lastTotalProcessorTime).TotalMilliseconds;
                    var totalTimeMs = (currentTime - _lastCheckTime).TotalMilliseconds;
                    var cpuUsageTotal = cpuUsedMs / (totalTimeMs * Environment.ProcessorCount);
                    
                    _lastTotalProcessorTime = currentTotalProcessorTime;
                    _lastCheckTime = currentTime;

                    return cpuUsageTotal * 100;
                }
                else
                {
                    _lastTotalProcessorTime = currentTotalProcessorTime;
                    _lastCheckTime = currentTime;
                    return 0;
                }
            }
            catch
            {
                return 0;
            }
#else
            return 0;
#endif
        }

        public double GetMemoryUsage()
        {
#if WINDOWS
            try
            {
                return _ramCounter?.NextValue() ?? 0;
            }
            catch
            {
                return 0;
            }
#elif ANDROID
            try
            {
                var context = Android.App.Application.Context;
                var activityManager = (ActivityManager?)context.GetSystemService(Context.ActivityService);
                if (activityManager != null)
                {
                    var memoryInfo = new ActivityManager.MemoryInfo();
                    activityManager.GetMemoryInfo(memoryInfo);

                    if (memoryInfo.TotalMem > 0)
                    {
                        // Calculate percentage used
                        double used = memoryInfo.TotalMem - memoryInfo.AvailMem;
                        return (used / (double)memoryInfo.TotalMem) * 100.0;
                    }
                }
                return 0;
            }
            catch
            {
                return 0;
            }
#else
            return 0;
#endif
        }
    }
}
