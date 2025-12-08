using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using Microsoft.Maui.Devices;
using Microsoft.Maui.Networking;

#if ANDROID
using Android.App;
using Android.Content;
using Android.OS;
using Android.Provider;
using Android.App.Usage;
#endif

namespace Daily.Services
{
    public interface ISystemMonitorService
    {
        event Action? SystemStatsUpdated;
        void StartMonitoring();
        void StopMonitoring();

        double GetCpuUsage();
        double GetMemoryUsage();
        (double Level, bool IsCharging) GetBatteryInfo();
        (string AccessType, string ConnectionProfiles) GetNetworkInfo();
        (double RxRate, double TxRate) GetNetworkRates();
        (double FreeGb, double TotalGb) GetMainDriveStorage();
        TimeSpan GetUptime();
        (double TempC, double VoltageV, int ProcessCount, TimeSpan? DailyUsage, bool IsUsagePermissionGranted) GetSystemHealth();
        (string Model, string Manufacturer, string Name, string Version, string Platform, string Idiom, string DeviceType) GetSystemDetails();
        void OpenUsageSettings();
    }

    public class SystemMonitorService : ISystemMonitorService
    {
        public event Action? SystemStatsUpdated;

#if WINDOWS
        private PerformanceCounter? _cpuCounter;
        private PerformanceCounter? _ramCounter;
#elif ANDROID
        private TimeSpan _lastTotalProcessorTime;
        private DateTime _lastCheckTime;
#endif
        // Caching fields
        private double _cachedCpuUsage;
        private double _cachedMemUsage;
        private (double Level, bool IsCharging) _cachedBattery;
        private (string AccessType, string ConnectionProfiles) _cachedNetworkInfo;
        private (double RxRate, double TxRate) _cachedNetworkRates;
        private (double FreeGb, double TotalGb) _cachedStorage;
        private TimeSpan _cachedUptime;
        private (double TempC, double VoltageV, int ProcessCount, TimeSpan? DailyUsage, bool IsUsagePermissionGranted) _cachedHealth;
        
        // Network Rate Calculation State
        private long _prevBytesRx = 0;
        private long _prevBytesTx = 0;
        private DateTime _prevRateCheckTime = DateTime.MinValue;
        
        // Monitoring State
        private System.Threading.Timer? _timer;
        private bool _isMonitoring;
        private readonly object _lock = new object();

        public SystemMonitorService()
        {
            InitializeCounters();
            // Initialize defaults
            _cachedNetworkInfo = ("Unknown", "Unknown");
            _cachedBattery = (0, false);
            _cachedNetworkRates = (0, 0);
            _cachedStorage = (0, 1);
            _cachedHealth = (0, 0, 0, null, false);
        }

        private void InitializeCounters()
        {
#if WINDOWS
            try
            {
                _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
                _ramCounter = new PerformanceCounter("Memory", "% Committed Bytes In Use");
                _cpuCounter.NextValue(); // First call is 0
                _ramCounter.NextValue();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to initialize PerformanceCounters: {ex.Message}");
            }
#endif
        }

        public void StartMonitoring()
        {
            lock (_lock)
            {
                if (_isMonitoring) return;
                
                _isMonitoring = true;
                // Start Timer (5 seconds)
                _timer = new System.Threading.Timer(_ => RefreshAllStats(), null, 0, 5000);
            }
        }

        public void StopMonitoring()
        {
            lock (_lock)
            {
                if (!_isMonitoring) return;

                _isMonitoring = false;
                _timer?.Change(System.Threading.Timeout.Infinite, 0);
                _timer?.Dispose();
                _timer = null;
            }
        }

        private void RefreshAllStats()
        {
            try
            {
                _cachedCpuUsage = CalculateCpuUsage();
                _cachedMemUsage = CalculateMemoryUsage();
                _cachedBattery = CalculateBatteryInfo();
                _cachedNetworkInfo = CalculateNetworkInfo();
                _cachedNetworkRates = CalculateNetworkRates();
                _cachedStorage = CalculateMainDriveStorage();
                _cachedUptime = CalculateUptime();
                _cachedHealth = CalculateSystemHealth();

                // Notify subscribers
                SystemStatsUpdated?.Invoke();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error calculating stats: {ex.Message}");
            }
        }

        // --- Getters return cached values ---

        public double GetCpuUsage() => _cachedCpuUsage;
        public double GetMemoryUsage() => _cachedMemUsage;
        public (double Level, bool IsCharging) GetBatteryInfo() => _cachedBattery;
        public (string AccessType, string ConnectionProfiles) GetNetworkInfo() => _cachedNetworkInfo;
        public (double RxRate, double TxRate) GetNetworkRates() => _cachedNetworkRates;
        public (double FreeGb, double TotalGb) GetMainDriveStorage() => _cachedStorage;
        public TimeSpan GetUptime() => _cachedUptime;
        public (double TempC, double VoltageV, int ProcessCount, TimeSpan? DailyUsage, bool IsUsagePermissionGranted) GetSystemHealth() => _cachedHealth;
        
        public (string Model, string Manufacturer, string Name, string Version, string Platform, string Idiom, string DeviceType) GetSystemDetails()
        {
             // Static info, no need to cache in loop, but okay to call direct
             try
             {
                 return (
                     DeviceInfo.Model,
                     DeviceInfo.Manufacturer,
                     DeviceInfo.Name,
                     DeviceInfo.VersionString,
                     DeviceInfo.Platform.ToString(),
                     DeviceInfo.Idiom.ToString(),
                     DeviceInfo.DeviceType.ToString()
                 );
             }
             catch
             {
                 return ("Unknown", "Unknown", "Unknown", "Unknown", "Unknown", "Unknown", "Unknown");
             }
        }

        // --- Calculation Logic (Moved from Getters) ---

        private double CalculateCpuUsage()
        {
#if WINDOWS
            try { return _cpuCounter?.NextValue() ?? 0; } catch { return 0; }
#elif ANDROID
            try
            {
                var currentProcess = System.Diagnostics.Process.GetCurrentProcess();
                var currentTotalProcessorTime = currentProcess.TotalProcessorTime;
                var currentTime = DateTime.UtcNow;

                if (_lastCheckTime != DateTime.MinValue)
                {
                    var cpuUsedMs = (currentTotalProcessorTime - _lastTotalProcessorTime).TotalMilliseconds;
                    var totalTimeMs = (currentTime - _lastCheckTime).TotalMilliseconds;
                    
                    if (totalTimeMs <= 0) return _cachedCpuUsage; // Return previous if invalid time

                    var cpuUsageTotal = cpuUsedMs / (totalTimeMs * System.Environment.ProcessorCount);
                    
                    _lastTotalProcessorTime = currentTotalProcessorTime;
                    _lastCheckTime = currentTime;

                    var result = cpuUsageTotal * 100;
                    return Math.Min(100, Math.Max(0, result));
                }
                else
                {
                    _lastTotalProcessorTime = currentTotalProcessorTime;
                    _lastCheckTime = currentTime;
                    return 0;
                }
            }
            catch { return 0; }
#else
            return 0;
#endif
        }

        private double CalculateMemoryUsage()
        {
#if WINDOWS
            try { return _ramCounter?.NextValue() ?? 0; } catch { return 0; }
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
                        double used = memoryInfo.TotalMem - memoryInfo.AvailMem;
                        return (used / (double)memoryInfo.TotalMem) * 100.0;
                    }
                }
                return 0;
            }
            catch { return 0; }
#else
            return 0;
#endif
        }

        private (double Level, bool IsCharging) CalculateBatteryInfo()
        {
            try
            {
                var battery = Battery.Default;
                return (battery.ChargeLevel, battery.State == BatteryState.Charging || battery.State == BatteryState.Full);
            }
            catch { return (0, false); }
        }

        private (string, string) CalculateNetworkInfo()
        {
             try
             {
                 var access = Connectivity.Current.NetworkAccess;
                 var profiles = Connectivity.Current.ConnectionProfiles;
                 string profileStr = "None";
                 
 #if ANDROID
                 var context = Android.App.Application.Context;
                 var wifiManager = (Android.Net.Wifi.WifiManager?)context.GetSystemService(Context.WifiService);
                 if (profiles.Contains(ConnectionProfile.WiFi))
                 {
                     if (wifiManager != null)
                     {
                         var info = wifiManager.ConnectionInfo;
                         if (info != null && !string.IsNullOrEmpty(info.SSID) && info.SSID != "<unknown ssid>")
                         {
                              profileStr = info.SSID.Trim('"');
                         }
                         else profileStr = "Wireless";
                     }
                     else profileStr = "Wireless";
                 }
                 else if (profiles.Contains(ConnectionProfile.Ethernet)) profileStr = "Ethernet";
                 else if (profiles.Contains(ConnectionProfile.Cellular)) profileStr = "Mobile Data";
 #else
                 if (profiles.Contains(ConnectionProfile.WiFi)) profileStr = "WiFi";
                 else if (profiles.Contains(ConnectionProfile.Ethernet)) profileStr = "Ethernet";
                 else if (profiles.Contains(ConnectionProfile.Cellular)) profileStr = "Cellular";
 #endif
                 return (access.ToString(), profileStr);
             }
             catch { return ("Unknown", "Unknown"); }
        }

        private (double RxRate, double TxRate) CalculateNetworkRates()
        {
#if ANDROID
            try
            {
                long totalRx = Android.Net.TrafficStats.TotalRxBytes;
                long totalTx = Android.Net.TrafficStats.TotalTxBytes;
                if (totalRx == -1 || totalTx == -1) return (0, 0);

                var now = DateTime.UtcNow;
                double rxRate = 0;
                double txRate = 0;

                if (_prevRateCheckTime != DateTime.MinValue)
                {
                    var timeDiff = (now - _prevRateCheckTime).TotalSeconds;
                    if (timeDiff > 0)
                    {
                        if (totalRx >= _prevBytesRx) rxRate = (totalRx - _prevBytesRx) / timeDiff;
                        if (totalTx >= _prevBytesTx) txRate = (totalTx - _prevBytesTx) / timeDiff;
                    }
                }
                _prevBytesRx = totalRx;
                _prevBytesTx = totalTx;
                _prevRateCheckTime = now;
                return (rxRate, txRate);
            }
            catch { return (0, 0); }
#else
             try
             {
                 if (!NetworkInterface.GetIsNetworkAvailable()) return (0, 0);
                 var interfaces = NetworkInterface.GetAllNetworkInterfaces();
                 long totalRx = 0;
                 long totalTx = 0;
                 foreach (var ni in interfaces)
                 {
                     if (ni.OperationalStatus == OperationalStatus.Up && 
                         ni.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                         ni.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
                     {
                         var stats = ni.GetIPStatistics();
                         totalRx += stats.BytesReceived;
                         totalTx += stats.BytesSent;
                     }
                 }
                 var now = DateTime.UtcNow;
                 double rxRate = 0;
                 double txRate = 0;
                 if (_prevRateCheckTime != DateTime.MinValue)
                 {
                     var timeDiff = (now - _prevRateCheckTime).TotalSeconds;
                     if (timeDiff > 0)
                     {
                         if (totalRx >= _prevBytesRx) rxRate = (totalRx - _prevBytesRx) / timeDiff;
                         if (totalTx >= _prevBytesTx) txRate = (totalTx - _prevBytesTx) / timeDiff;
                     }
                 }
                 _prevBytesRx = totalRx;
                 _prevBytesTx = totalTx;
                 _prevRateCheckTime = now;
                 return (rxRate, txRate);
             }
             catch { return (0, 0); }
#endif
        }

        private (double FreeGb, double TotalGb) CalculateMainDriveStorage()
        {
#if ANDROID
            try
            {
                var path = Android.OS.Environment.DataDirectory;
                var stat = new Android.OS.StatFs(path.Path);
                long blockSize = stat.BlockSizeLong;
                long totalBlocks = stat.BlockCountLong;
                long freeBlocks = stat.AvailableBlocksLong;
                double bytesToGb = 1024.0 * 1024.0 * 1024.0;
                return ((freeBlocks * blockSize) / bytesToGb, (totalBlocks * blockSize) / bytesToGb);
            }
            catch { return (0, 0); }
#else
             try
             {
                 DriveInfo? main = null;
                 var drives = DriveInfo.GetDrives().Where(d => d.IsReady).ToList();
                 main = drives.FirstOrDefault(d => d.Name.Equals(@"C:\", StringComparison.OrdinalIgnoreCase)) 
                        ?? drives.FirstOrDefault(d => d.Name == "/") 
                        ?? drives.Where(d => d.DriveType == DriveType.Fixed).OrderByDescending(d => d.TotalSize).FirstOrDefault()
                        ?? drives.OrderByDescending(d => d.TotalSize).FirstOrDefault();

                 if (main != null)
                 {
                     double bytesToGb = 1024.0 * 1024.0 * 1024.0;
                     return (main.TotalFreeSpace / bytesToGb, main.TotalSize / bytesToGb);
                 }
                 return (0, 0);
             }
             catch { return (0, 0); }
#endif
        }

        private TimeSpan CalculateUptime()
        {
            try { return TimeSpan.FromMilliseconds(System.Environment.TickCount64); } catch { return TimeSpan.Zero; }
        }

        private (double, double, int, TimeSpan?, bool) CalculateSystemHealth()
        {
#if WINDOWS
            try
            {
                int procCount = System.Diagnostics.Process.GetProcesses().Length;
                TimeSpan? sessionDuration = null;
                var explorers = System.Diagnostics.Process.GetProcessesByName("explorer");
                if (explorers.Length > 0)
                {
                    sessionDuration = DateTime.Now - explorers.Min(p => p.StartTime);
                }
                return (0, 0, procCount, sessionDuration, true);
            }
            catch { return (0, 0, 0, null, false); }
#elif ANDROID
            try
            {
                 double temp = 0;
                 double voltage = 0;
                 var context = Android.App.Application.Context;
                 var intent = context.RegisterReceiver(null, new IntentFilter(Intent.ActionBatteryChanged));
                 if (intent != null)
                 {
                     temp = intent.GetIntExtra(BatteryManager.ExtraTemperature, 0) / 10.0;
                     voltage = intent.GetIntExtra(BatteryManager.ExtraVoltage, 0) / 1000.0;
                 }
                 
                 bool granted = false;
                 TimeSpan? usage = null;
                 var appOps = (AppOpsManager?)context.GetSystemService(Context.AppOpsService);
                 var mode = appOps?.CheckOpNoThrow(AppOpsManager.OpstrGetUsageStats, Android.OS.Process.MyUid(), context.PackageName!);
                 granted = (mode == AppOpsManagerMode.Allowed);

                 if (granted)
                 {
                     var usageStatsManager = (UsageStatsManager?)context.GetSystemService(Context.UsageStatsService);
                     if (usageStatsManager != null)
                     {
                         var cal = Java.Util.Calendar.Instance;
                         cal!.Set(Java.Util.CalendarField.HourOfDay, 0);
                         cal.Set(Java.Util.CalendarField.Minute, 0);
                         cal.Set(Java.Util.CalendarField.Second, 0);
                         cal.Set(Java.Util.CalendarField.Millisecond, 0);
                         var stats = usageStatsManager.QueryUsageStats(UsageStatsInterval.Daily, cal.TimeInMillis, Java.Lang.JavaSystem.CurrentTimeMillis());
                         if (stats != null)
                         {
                             long totalMs = 0;
                             foreach (var stat in stats) totalMs += stat.TotalTimeInForeground;
                             usage = TimeSpan.FromMilliseconds(totalMs);
                         }
                     }
                 }
                 return (temp, voltage, 0, usage, granted);
            }
            catch { return (0, 0, 0, null, false); }
#else
            return (0, 0, 0, null, false);
#endif
        }

        public void OpenUsageSettings()
        {
#if ANDROID
            try
            {
                var intent = new Intent(Settings.ActionUsageAccessSettings);
                intent.AddFlags(ActivityFlags.NewTask);
                Android.App.Application.Context.StartActivity(intent);
            }
            catch { }
#endif
        }
    }
}
