using Android.Content;
using AndroidX.Health.Connect.Client;
using AndroidX.Health.Connect.Client.Records;
using AndroidX.Health.Connect.Client.Request;
using AndroidX.Health.Connect.Client.Response; // Added
using AndroidX.Health.Connect.Client.Time; // Added
using Daily.Models.Health;
using Daily.Services.Health;
// using Java.Time; (Explicitly used mostly)
using Microsoft.Extensions.Logging;
using System;
using Permission = AndroidX.Health.Connect.Client.Permission.HealthPermission;

// Kotlin Reflection Helper
using Kotlin.Jvm;

namespace Daily.Platforms.Android
{
    public class HealthConnectService : INativeHealthStore
    {
        private IHealthConnectClient _client;
        private readonly ILogger<HealthConnectService> _logger;

        public HealthConnectService(ILogger<HealthConnectService> logger)
        {
            _logger = logger;
            Initialize();
        }

        private void Initialize()
        {
            try
            {
                var context = global::Android.App.Application.Context;
                // Check availability first if possible, but GetOrCreate is robust.
                _client = HealthConnectClient.GetOrCreate(context);
                _logger.LogInformation($"HealthConnectClient Initialized. IsSupported: {(_client != null)}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error initializing HealthConnectClient");
                _client = null;
            }
        }

        private Kotlin.Reflect.IKClass GetKClass<T>()
        {
            return JvmClassMappingKt.GetKotlinClass(Java.Lang.Class.FromType(typeof(T)));
        }

        public async Task<bool> RequestPermissionsAsync()
        {
            _logger.LogInformation("RequestPermissionsAsync: Called (MAUI Based).");

            // Ensure Client Init (Soft Logic)
            if (_client == null) Initialize();

            try
            {
                var status = await Microsoft.Maui.ApplicationModel.Permissions.CheckStatusAsync<Daily.Platforms.Android.Permissions.HealthConnectPermission>();
                _logger.LogInformation($"RequestPermissionsAsync: Current Status: {status}");

                if (status == PermissionStatus.Granted)
                {
                    _logger.LogInformation("RequestPermissionsAsync: Permissions already granted (MAUI Check).");
                    return true;
                }

                _logger.LogInformation("RequestPermissionsAsync: Requesting via MAUI Permissions API...");
                
                // Force UI Thread for the request
                status = await MainThread.InvokeOnMainThreadAsync(async () => 
                {
                    return await Microsoft.Maui.ApplicationModel.Permissions.RequestAsync<Daily.Platforms.Android.Permissions.HealthConnectPermission>();
                });

                _logger.LogInformation($"RequestPermissionsAsync: Result Status: {status}");
                
                return status == PermissionStatus.Granted;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "RequestPermissionsAsync: Exception encountered via MAUI API.");
                return false;
            }
        }

        public async Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            var metrics = new List<VitalMetric>();
            if (_client == null) return metrics; // We can't fetch if client is null, that's fine.

            try
            {
                var zoneId = Java.Time.ZoneId.SystemDefault();
                var start = date.Date.ToInstant(zoneId.Rules.GetOffset(Java.Time.Instant.Now()));
                var end = date.Date.AddDays(1).ToInstant(zoneId.Rules.GetOffset(Java.Time.Instant.Now()));
                var timeRangeFilter = TimeRangeFilter.Between(start, end);

                // Use Java.Lang.Object to bypass compile-time type check failure
                // We will log the actual type at runtime.
                async Task<Java.Lang.Object> ReadRecords<T>() 
                {
                     // Explicit 6-argument constructor for ReadRecordsRequest
                     var request = new ReadRecordsRequest(
                         GetKClass<T>(),
                         timeRangeFilter,
                         new System.Collections.Generic.HashSet<AndroidX.Health.Connect.Client.Records.Metadata.DataOrigin>(), // Empty Set
                         true, // Ascending
                         1000,  // PageSize
                         null  // PageToken
                     );
                     
                     var tcs = new TaskCompletionSource<Java.Lang.Object>();
                     // Passing TaskContinuation<Java.Lang.Object> works because binding usually expects IContinuation which we implement
                     _client.ReadRecords(request, new Helpers.TaskContinuation<Java.Lang.Object>(tcs));
                     return await tcs.Task;
                }

                // Helper to get Records list via reflection
                System.Collections.IList GetRecordsList(Java.Lang.Object response)
                {
                    if (response == null) return new List<object>();
                    _logger.LogInformation($"ReadRecords Response Type: {response.GetType().FullName}");
                    
                    try 
                    {
                        var prop = response.GetType().GetProperty("Records");
                        if (prop != null) return prop.GetValue(response) as System.Collections.IList;
                    } 
                    catch (Exception ex) 
                    { 
                        _logger.LogError(ex, "Reflection failed"); 
                    }
                    return new List<object>();
                }

                // 1. Steps
                var stepsResponse = await ReadRecords<StepsRecord>();
                long totalSteps = 0;
                foreach (StepsRecord record in GetRecordsList(stepsResponse))
                {
                    totalSteps += record.Count;
                }
                if (totalSteps > 0)
                {
                    metrics.Add(new VitalMetric
                    {
                        TypeString = "Steps",
                        Value = totalSteps,
                        Unit = "count",
                        Date = date,
                        SourceDevice = "Android Health Connect"
                    });
                }

                // 2. Heart Rate
                var hrResponse = await ReadRecords<HeartRateRecord>();
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
                    metrics.Add(new VitalMetric
                    {
                        TypeString = "HeartRate",
                        Value = Math.Round(hrSum / hrCount),
                        Unit = "bpm",
                        Date = date,
                        SourceDevice = "Android Health Connect"
                    });
                }

                // 3. Sleep
                var sleepResponse = await ReadRecords<SleepSessionRecord>();
                double totalSleepSeconds = 0;
                foreach (SleepSessionRecord record in GetRecordsList(sleepResponse))
                {
                    var duration = Java.Time.Duration.Between(record.StartTime, record.EndTime);
                    totalSleepSeconds += duration.Seconds;
                }
                if (totalSleepSeconds > 0)
                {
                     metrics.Add(new VitalMetric
                    {
                        TypeString = "Sleep",
                        Value = Math.Round(totalSleepSeconds / 3600.0, 1), 
                    //    Unit = "hours", // Fixed typo in previous version if any
                        Unit = "hours",
                        Date = date,
                        SourceDevice = "Android Health Connect"
                    });
                }

                // 4. Calories
                var calResponse = await ReadRecords<TotalCaloriesBurnedRecord>();
                double totalCalories = 0;
                foreach (TotalCaloriesBurnedRecord record in GetRecordsList(calResponse))
                {
                     // Energy.Kilocalories
                    totalCalories += record.Energy.Kilocalories; 
                }
                 if (totalCalories > 0)
                {
                     metrics.Add(new VitalMetric
                    {
                        TypeString = "Calories",
                        Value = Math.Round(totalCalories), 
                        Unit = "kcal",
                        Date = date,
                        SourceDevice = "Android Health Connect"
                    });
                }

                return metrics;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching metrics");
                return metrics;
            }
        }

        public bool IsSupported => _client != null;
    }
}


// Extension helper for DateTime -> Instant if Java.Time is tricky
public static class DateExtensions 
{
    public static Java.Time.Instant ToInstant(this DateTime dt, Java.Time.ZoneOffset offset)
    {
        // Simple conversion if needed, but Java.Time is preferred on Android
        long epochSeconds = new DateTimeOffset(dt).ToUnixTimeSeconds();
        return Java.Time.Instant.OfEpochSecond(epochSeconds);
    }
}
