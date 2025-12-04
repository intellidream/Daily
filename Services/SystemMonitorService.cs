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
            // Getting total system CPU on Android is restricted.
            // We could return App CPU, but for now we'll return 0 or a placeholder.
            return 0; 
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
