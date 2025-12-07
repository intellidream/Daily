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
        double GetCpuUsage();
        double GetMemoryUsage();
        (double Level, bool IsCharging) GetBatteryInfo();
        (string AccessType, string ConnectionProfiles) GetNetworkInfo();
        (double RxRate, double TxRate) GetNetworkRates();
        (double FreeGb, double TotalGb) GetMainDriveStorage();
        TimeSpan GetUptime();
        (double TempC, double VoltageV, int ProcessCount, TimeSpan? DailyUsage, bool IsUsagePermissionGranted) GetSystemHealth();
        void OpenUsageSettings();
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
        private long _prevBytesRx = 0;
        private long _prevBytesTx = 0;
        private DateTime _prevRateCheckTime = DateTime.MinValue;

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

                var currentProcess = System.Diagnostics.Process.GetCurrentProcess();
                var currentTotalProcessorTime = currentProcess.TotalProcessorTime;
                var currentTime = DateTime.UtcNow;

                if (_lastCheckTime != DateTime.MinValue)
                {
                    var cpuUsedMs = (currentTotalProcessorTime - _lastTotalProcessorTime).TotalMilliseconds;
                    var totalTimeMs = (currentTime - _lastCheckTime).TotalMilliseconds;
                    var cpuUsageTotal = cpuUsedMs / (totalTimeMs * System.Environment.ProcessorCount);
                    
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
        public (double Level, bool IsCharging) GetBatteryInfo()
        {
            try
            {
                var battery = Battery.Default;
                return (battery.ChargeLevel, battery.State == BatteryState.Charging || battery.State == BatteryState.Full);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Battery Info Error: {ex.Message}");
                return (0, false);
            }
        }

        public (double RxRate, double TxRate) GetNetworkRates()
        {
#if ANDROID
            try
            {
                // Use TrafficStats for Android as NetworkInterface is unreliable
                long totalRx = Android.Net.TrafficStats.TotalRxBytes;
                long totalTx = Android.Net.TrafficStats.TotalTxBytes;
                
                // If device doesn't support it, returns -1
                if (totalRx == -1 || totalTx == -1) return (0, 0);

                var now = DateTime.UtcNow;
                double rxRate = 0;
                double txRate = 0;

                if (_prevRateCheckTime != DateTime.MinValue)
                {
                    var timeDiff = (now - _prevRateCheckTime).TotalSeconds;
                    if (timeDiff > 0)
                    {
                        if (totalRx >= _prevBytesRx)
                        rxRate = (totalRx - _prevBytesRx) / timeDiff;
                        
                        if (totalTx >= _prevBytesTx)
                        txRate = (totalTx - _prevBytesTx) / timeDiff;
                    }
                }

                _prevBytesRx = totalRx;
                _prevBytesTx = totalTx;
                _prevRateCheckTime = now;

                return (rxRate, txRate);
            }
            catch
            {
                return (0, 0);
            }
#else
             try
             {
                 if (!NetworkInterface.GetIsNetworkAvailable())
                    return (0, 0);

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
                         // Handle potential overflow or reset
                         if (totalRx >= _prevBytesRx)
                            rxRate = (totalRx - _prevBytesRx) / timeDiff;
                         
                         if (totalTx >= _prevBytesTx)
                            txRate = (totalTx - _prevBytesTx) / timeDiff;
                     }
                 }

                 _prevBytesRx = totalRx;
                 _prevBytesTx = totalTx;
                 _prevRateCheckTime = now;

                 return (rxRate, txRate);
             }
             catch
             {
                 return (0, 0);
             }
#endif
        }

        public (string AccessType, string ConnectionProfiles) GetNetworkInfo()
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
                             // Android returns SSID with quotes, e.g. "MyNetwork", remove them
                             profileStr = info.SSID.Trim('"');
                        }
                        else 
                        {
                            profileStr = "Wireless";
                        }
                    }
                    else
                    {
                         profileStr = "Wireless";
                    }
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
            catch
            {
                return ("Unknown", "Unknown");
            }
        }

        public (double FreeGb, double TotalGb) GetMainDriveStorage()
        {
#if ANDROID
            try
            {
                // Use StatFs for internal storage (Data Path)
                var path = Android.OS.Environment.DataDirectory;
                var stat = new Android.OS.StatFs(path.Path);
                
                long blockSize = stat.BlockSizeLong;
                long totalBlocks = stat.BlockCountLong;
                long freeBlocks = stat.AvailableBlocksLong;

                long total = totalBlocks * blockSize;
                long free = freeBlocks * blockSize;

                double bytesToGb = 1024.0 * 1024.0 * 1024.0;
                return (free / bytesToGb, total / bytesToGb);
            }
            catch
            {
                return (0, 0);
            }
#else
             try
             {
                 DriveInfo? main = null;

                 // 1. Try to identify the System Drive (C:\ on Windows, / on Unix)
                 var drives = DriveInfo.GetDrives().Where(d => d.IsReady).ToList();
                 
                 // Check for Windows System Drive (Usually C:\)
                 main = drives.FirstOrDefault(d => d.Name.Equals(@"C:\", StringComparison.OrdinalIgnoreCase));
                 
                 // Check for Mac/Linux Root (/)
                 if (main == null)
                 {
                     main = drives.FirstOrDefault(d => d.Name == "/");
                 }

                 // 2. Fallback: Largest Fixed Drive
                 if (main == null)
                 {
                     main = drives
                        .Where(d => d.DriveType == DriveType.Fixed)
                        .OrderByDescending(d => d.TotalSize)
                        .FirstOrDefault();
                 }

                 // 3. Last Resort: Any Ready Drive
                 if (main == null)
                 {
                     main = drives.OrderByDescending(d => d.TotalSize).FirstOrDefault();
                 }

                 if (main != null)
                 {
                     double bytesToGb = 1024.0 * 1024.0 * 1024.0;
                     return (main.TotalFreeSpace / bytesToGb, main.TotalSize / bytesToGb);
                 }
                 return (0, 0);
             }
             catch
             {
                 return (0, 0);
             }
#endif
        }

        public TimeSpan GetUptime()
        {
            try
            {
                 return TimeSpan.FromMilliseconds(System.Environment.TickCount64);
            }
            catch
            {
                return TimeSpan.Zero;
            }
        }
        public (double TempC, double VoltageV, int ProcessCount, TimeSpan? DailyUsage, bool IsUsagePermissionGranted) GetSystemHealth()
        {
#if WINDOWS
            try
            {
                int procCount = System.Diagnostics.Process.GetProcesses().Length;
                
                TimeSpan? sessionDuration = null;
                var explorers = System.Diagnostics.Process.GetProcessesByName("explorer");
                
                // Use the oldest explorer process as the session start time
                if (explorers.Length > 0)
                {
                    var startTime = explorers.Min(p => p.StartTime);
                    sessionDuration = DateTime.Now - startTime;
                }

                return (0, 0, procCount, sessionDuration, true);
            }
            catch
            {
                return (0, 0, 0, null, false);
            }
#elif ANDROID
            try
            {
                 // Battery Temp & Voltage
                 double temp = 0;
                 double voltage = 0;
                 var context = Android.App.Application.Context;
                 var intent = context.RegisterReceiver(null, new IntentFilter(Intent.ActionBatteryChanged));
                 if (intent != null)
                 {
                     int tempInt = intent.GetIntExtra(BatteryManager.ExtraTemperature, 0);
                     temp = tempInt / 10.0; // Tenths of a degree C
                     int voltInt = intent.GetIntExtra(BatteryManager.ExtraVoltage, 0);
                     voltage = voltInt / 1000.0; // mV to V
                 }

                 // Usage Stats (Process Count blocked on Android)
                 bool granted = false;
                 TimeSpan? usage = null;
                 
                 var appOps = (AppOpsManager?)context.GetSystemService(Context.AppOpsService);
                 string packageName = context.PackageName!;
                 int uid = Android.OS.Process.MyUid();
                 
                 var mode = appOps?.CheckOpNoThrow(AppOpsManager.OpstrGetUsageStats, uid, packageName);
                 granted = (mode == AppOpsManagerMode.Allowed);

                 if (granted)
                 {
                     var usageStatsManager = (UsageStatsManager?)context.GetSystemService(Context.UsageStatsService);
                     if (usageStatsManager != null)
                     {
                         // Calculate time from start of today
                         var cal = Java.Util.Calendar.Instance;
                         cal!.Set(Java.Util.CalendarField.HourOfDay, 0);
                         cal.Set(Java.Util.CalendarField.Minute, 0);
                         cal.Set(Java.Util.CalendarField.Second, 0);
                         cal.Set(Java.Util.CalendarField.Millisecond, 0);
                         long startTime = cal.TimeInMillis;
                         long endTime = Java.Lang.JavaSystem.CurrentTimeMillis();

                         var stats = usageStatsManager.QueryUsageStats(UsageStatsInterval.Daily, startTime, endTime);
                         if (stats != null)
                         {
                             // Sum up TotalTimeInForeground for all packages? Or just "Daily Active Use" meant general screen time?
                             // QueryUsageStats returns list per package. We assume "Device Usage" means sum of all apps? 
                             // Or commonly just "Screen On Time". UsageStats is closest we get.
                             // Summing all might double count or be weird, but let's try summing all foreground time.
                             long totalMs = 0;
                             foreach (var stat in stats)
                             {
                                 totalMs += stat.TotalTimeInForeground;
                             }
                             usage = TimeSpan.FromMilliseconds(totalMs);
                         }
                     }
                 }

                 return (temp, voltage, 0, usage, granted);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Health Info Error: {ex.Message}");
                return (0, 0, 0, null, false);
            }
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
            catch
            {
                // Navigate failed
            }
#endif
        }
    }
}
