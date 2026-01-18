using Android.Content;
using Android.App;
using AndroidX.Health.Connect.Client;
using AndroidX.Health.Connect.Client.Records;
using AndroidX.Health.Connect.Client.Request;
using AndroidX.Health.Connect.Client.Time;
using AndroidX.Health.Connect.Client.Response;
using Java.Time;
using Microsoft.Extensions.Logging;
using Microsoft.Maui.ApplicationModel;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Services.Health;
using Daily.Platforms.Android.Helpers;
using Daily.Models.Health;
using Kotlin.Jvm;
using Kotlin.Reflect;

namespace Daily.Platforms.Android
{
    // V28 RESTORED LOGIC - REFLECTION BASED
    public class HealthConnectService : INativeHealthStore
    {
        private readonly ILogger<HealthConnectService> _logger;
        private IHealthConnectClient _client; 

        public HealthConnectService(ILogger<HealthConnectService> logger)
        {
            _logger = logger;
            Initialize();
        }

        private void Initialize()
        {
            try
            {
                var context = Platform.AppContext;
                _client = HealthConnectClient.GetOrCreate(context);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthConnectService] Initialize Failed: {ex.Message}");
            }
        }

        public async Task<bool> RequestPermissionsAsync()
        {
            if (_client == null) Initialize();
            try
            {
                // V28 Logic: Use MAUI Permissions
                var status = await Microsoft.Maui.ApplicationModel.Permissions.CheckStatusAsync<Daily.Platforms.Android.Permissions.HealthConnectPermission>();
                if (status == PermissionStatus.Granted) return true;

                status = await MainThread.InvokeOnMainThreadAsync(async () => 
                {
                    return await Microsoft.Maui.ApplicationModel.Permissions.RequestAsync<Daily.Platforms.Android.Permissions.HealthConnectPermission>();
                });

                return status == PermissionStatus.Granted;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthConnectService] RequestPermissionsAsync Error: {ex}");
                return false;
            }
        }

        public async Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            var metrics = new List<VitalMetric>();
            if (_client == null || !await RequestPermissionsAsync()) return metrics;

            try
            {
                var zoneId = Java.Time.ZoneId.SystemDefault();
                // Manual Instant Conversion (Proven in V41)
                var startDateTime = date.Date;
                var endDateTime = date.Date.AddDays(1);
                var startInstant = Java.Time.Instant.OfEpochSecond(new DateTimeOffset(startDateTime).ToUnixTimeSeconds());
                var endInstant = Java.Time.Instant.OfEpochSecond(new DateTimeOffset(endDateTime).ToUnixTimeSeconds());

                var timeRangeFilter = TimeRangeFilter.Between(startInstant, endInstant);
                var dataOriginFilter = new System.Collections.Generic.HashSet<AndroidX.Health.Connect.Client.Records.Metadata.DataOrigin>();

                // REFLECTION-BASED READ (V28 pattern)
                // This bypasses the binding generic constraint issues
                async Task<Java.Lang.Object> ReadRecordsInternal<T>() 
                {
                     try
                     {
                         var request = new ReadRecordsRequest(
                             GetKClass<T>(),
                             timeRangeFilter,
                             dataOriginFilter, 
                             true, 
                             2000, 
                             null
                         );
                         
                         var tcs = new TaskCompletionSource<Java.Lang.Object>();
                         _client.ReadRecords(request, new Helpers.TaskContinuation<Java.Lang.Object>(tcs));
                         return await tcs.Task;
                     }
                     catch(Exception ex)
                     {
                         Console.WriteLine($"[HealthConnectService] Read Failed: {ex.Message}");
                         return null;
                     }
                }

                System.Collections.IList GetRecordsList(Java.Lang.Object response)
                {
                    if (response == null) return new List<object>();
                    try 
                    {
                        var prop = response.GetType().GetProperty("Records");
                        if (prop != null) return prop.GetValue(response) as System.Collections.IList;
                    } 
                    catch { }
                    return new List<object>();
                }

                // 1. Steps
                var stepsResponse = await ReadRecordsInternal<StepsRecord>();
                long totalSteps = 0;
                foreach (StepsRecord record in GetRecordsList(stepsResponse))
                {
                    totalSteps += record.Count;
                }
                if (totalSteps > 0)
                {
                    metrics.Add(new VitalMetric { TypeString = "Steps", Value = totalSteps, Unit = "count", Date = date, SourceDevice = "Health Connect" });
                }

                // 2. Heart Rate
                var hrResponse = await ReadRecordsInternal<HeartRateRecord>();
                double hrSum = 0;
                int hrCount = 0;
                foreach (HeartRateRecord record in GetRecordsList(hrResponse))
                {
                    foreach (var sample in record.Samples)
                    {
                        hrSum += sample.BeatsPerMinute;
                        hrCount++;
                    }
                }
                if (hrCount > 0)
                {
                    metrics.Add(new VitalMetric { TypeString = "HeartRate", Value = Math.Round(hrSum / hrCount), Unit = "bpm", Date = date, SourceDevice = "Health Connect" });
                }

                // 3. Sleep
                var sleepResponse = await ReadRecordsInternal<SleepSessionRecord>();
                double totalSleepSeconds = 0;
                foreach (SleepSessionRecord record in GetRecordsList(sleepResponse))
                {
                    var duration = Java.Time.Duration.Between(record.StartTime, record.EndTime);
                    totalSleepSeconds += duration.Seconds;
                }
                if (totalSleepSeconds > 0)
                {
                     // Convert to Minutes to match VitalType standard
                     var minutes = Math.Round(totalSleepSeconds / 60.0, 1);
                     metrics.Add(new VitalMetric { TypeString = VitalType.SleepDuration.ToString(), Value = minutes, Unit = "min", Date = date, SourceDevice = "Health Connect" });
                }

                // 4. Calories
                var calResponse = await ReadRecordsInternal<TotalCaloriesBurnedRecord>();
                double totalCalories = 0;
                foreach (TotalCaloriesBurnedRecord record in GetRecordsList(calResponse))
                {
                    totalCalories += record.Energy.Kilocalories; 
                }
                 if (totalCalories > 0)
                {
                     metrics.Add(new VitalMetric { TypeString = VitalType.ActiveEnergy.ToString(), Value = Math.Round(totalCalories), Unit = "kcal", Date = date, SourceDevice = "Health Connect" });
                }

                // --- V50 ADDITIONS ---

                // 5. Distance (Sum)
                try {
                    var distResponse = await ReadRecordsInternal<DistanceRecord>();
                    double totalDist = 0;
                    foreach (DistanceRecord record in GetRecordsList(distResponse))
                    {
                        totalDist += record.Distance.Meters;
                    }
                    if (totalDist > 0) metrics.Add(new VitalMetric { TypeString = VitalType.Distance.ToString(), Value = Math.Round(totalDist, 2), Unit = "m", Date = date, SourceDevice = "Health Connect" });
                } catch {}

                // 6. Weight (Latest)
                try {
                    var wResponse = await ReadRecordsInternal<WeightRecord>();
                    var wRecords = GetRecordsList(wResponse);
                    if (wRecords.Count > 0)
                    {
                        // Take the last one (Latest)
                        var last = wRecords[wRecords.Count - 1] as WeightRecord;
                        metrics.Add(new VitalMetric { TypeString = VitalType.Weight.ToString(), Value = last.Weight.Kilograms, Unit = "kg", Date = date, SourceDevice = "Health Connect" });
                    }
                } catch {}

                // 7. Hydration (Sum)
                try {
                    var hResponse = await ReadRecordsInternal<HydrationRecord>();
                    double totalHydro = 0;
                    foreach (HydrationRecord record in GetRecordsList(hResponse))
                    {
                        totalHydro += record.Volume.Liters;
                    }
                    if (totalHydro > 0) metrics.Add(new VitalMetric { TypeString = VitalType.Hydration.ToString(), Value = Math.Round(totalHydro, 1), Unit = "L", Date = date, SourceDevice = "Health Connect" });
                } catch {}

                // 8. Blood Pressure (Average)
                try {
                    var bpResponse = await ReadRecordsInternal<BloodPressureRecord>();
                    var bpList = GetRecordsList(bpResponse);
                    if (bpList.Count > 0)
                    {
                        double sysSum = 0;
                        double diaSum = 0;
                        foreach (BloodPressureRecord record in bpList)
                        {
                            sysSum += record.Systolic.MillimetersOfMercury;
                            diaSum += record.Diastolic.MillimetersOfMercury;
                        }
                        metrics.Add(new VitalMetric { TypeString = VitalType.BloodPressureSystolic.ToString(), Value = Math.Round(sysSum / bpList.Count), Unit = "mmHg", Date = date, SourceDevice = "Health Connect" });
                        metrics.Add(new VitalMetric { TypeString = VitalType.BloodPressureDiastolic.ToString(), Value = Math.Round(diaSum / bpList.Count), Unit = "mmHg", Date = date, SourceDevice = "Health Connect" });
                    }
                } catch {}

                // 9. Glucose (Average)
                try {
                    var gResponse = await ReadRecordsInternal<BloodGlucoseRecord>();
                    var gList = GetRecordsList(gResponse);
                    if (gList.Count > 0)
                    {
                        double gSum = 0;
                        foreach (BloodGlucoseRecord record in gList)
                        {
                            // MillimolesPerLiter is standard for intl, but maybe mg/dL? 
                            // Let's use MilligramsPerDeciliter as it's an integer-like friendly number (80-120), vs 5.5
                            // Properties: Level (BloodGlucose)
                            gSum += record.Level.MilligramsPerDeciliter;
                        }
                        metrics.Add(new VitalMetric { TypeString = VitalType.BloodGlucose.ToString(), Value = Math.Round(gSum / gList.Count), Unit = "mg/dL", Date = date, SourceDevice = "Health Connect" });
                    }
                } catch {}

                // 10. SpO2 (Average)
                try {
                    var oResponse = await ReadRecordsInternal<OxygenSaturationRecord>();
                    var oList = GetRecordsList(oResponse);
                    if (oList.Count > 0)
                    {
                        double oSum = 0;
                        foreach (OxygenSaturationRecord record in oList)
                        {
                            oSum += record.Percentage.Value; // 98.0
                        }
                        metrics.Add(new VitalMetric { TypeString = VitalType.OxygenSaturation.ToString(), Value = Math.Round(oSum / oList.Count, 1), Unit = "%", Date = date, SourceDevice = "Health Connect" });
                    }
                } catch {}

                // 11. Body Temperature (Average)
                try {
                    var tResponse = await ReadRecordsInternal<BodyTemperatureRecord>();
                    var tList = GetRecordsList(tResponse);
                    if (tList.Count > 0)
                    {
                        double tSum = 0;
                        foreach (BodyTemperatureRecord record in tList)
                        {
                            tSum += record.Temperature.Celsius;
                        }
                        metrics.Add(new VitalMetric { TypeString = VitalType.BodyTemperature.ToString(), Value = Math.Round(tSum / tList.Count, 1), Unit = "C", Date = date, SourceDevice = "Health Connect" });
                    }
                } catch {}

                return metrics;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthConnectService] FetchMetricsAsync Error: {ex}");
                return metrics;
            }
        }

        public bool IsSupported => _client != null;

        private static IKClass GetKClass<T>()
        {
            return JvmClassMappingKt.GetKotlinClass(Java.Lang.Class.FromType(typeof(T)));
        }
    }
}
