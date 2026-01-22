using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services.Health;
using Foundation;
using HealthKit;

namespace Daily.Platforms.iOS.Services.Health
{
    public class HealthKitService : INativeHealthStore
    {
        private readonly HKHealthStore _healthStore;
        public bool IsSupported => HKHealthStore.IsHealthDataAvailable;

        public HealthKitService()
        {
            Console.WriteLine("[HealthKitService] Constructor Called.");
            try
            {
                if (IsSupported)
                {
                    Console.WriteLine("[HealthKitService] Health Data IS Supported. Initializing Store.");
                    _healthStore = new HKHealthStore();
                    Console.WriteLine("[HealthKitService] Store Initialized.");
                }
                else
                {
                     Console.WriteLine("[HealthKitService] Health Data NOT Supported.");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthKitService] Constructor FAULT: {ex}");
            }
        }

        public async Task<bool> RequestPermissionsAsync()
        {
            if (!IsSupported) return false;

            var readTypes = new HashSet<HKObjectType>
            {
                HKQuantityType.Create(HKQuantityTypeIdentifier.StepCount),
                HKQuantityType.Create(HKQuantityTypeIdentifier.HeartRate),
                HKQuantityType.Create(HKQuantityTypeIdentifier.RestingHeartRate),
                HKCategoryType.Create(HKCategoryTypeIdentifier.SleepAnalysis)
            };

            var readSet = NSSet.MakeNSObjectSet(readTypes.ToArray());
            var shareSet = new NSSet();

            var (success, error) = await _healthStore.RequestAuthorizationToShareAsync(shareSet, readSet);
            
            if (error != null)
            {
                Console.WriteLine($"[HealthKit] Auth Error: {error.LocalizedDescription}");
                return false;
            }

            return success;
        }

        public async Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            if (!IsSupported) return new List<VitalMetric>();

            var metrics = new List<VitalMetric>();
            
            // Calculate Start/End for the specific Date (Midnight to Midnight)
            DateTime start = date.Date;
            DateTime end = start.AddDays(1);

            var nsStart = (NSDate)start;
            var nsEnd = (NSDate)end;
            
            // Predicate for "Between Start and End"
            var predicate = HKQuery.GetPredicateForSamples(nsStart, nsEnd, HKQueryOptions.StrictStartDate);

            try 
            {
                // 1. Steps (Aggregation: SUM)
                var stepType = HKQuantityType.Create(HKQuantityTypeIdentifier.StepCount);
                var stepStats = await FetchStatistics(stepType, predicate, start, HKStatisticsOptions.CumulativeSum);
                if (stepStats != null)
                {
                    double totalSteps = stepStats.SumQuantity()?.GetDoubleValue(HKUnit.Count) ?? 0;
                    if (totalSteps > 0)
                    {
                        metrics.Add(new VitalMetric
                        {
                            Type = VitalType.Steps,
                            Value = Math.Round(totalSteps),
                            Unit = "count",
                            Date = start, // Midnight
                            SourceDevice = "iOS"
                        });
                    }
                }

                // 2. Heart Rate (Aggregation: AVERAGE)
                var hrType = HKQuantityType.Create(HKQuantityTypeIdentifier.HeartRate);
                // Note: DiscreteAverage is for discrete data, but HR is often discrete types. 
                // For HR, DiscreteAverage is suitable to get the average BPM over the day.
                var hrStats = await FetchStatistics(hrType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                if (hrStats != null)
                {
                    double avgHr = hrStats.AverageQuantity()?.GetDoubleValue(HKUnit.Count.UnitDividedBy(HKUnit.Minute)) ?? 0;
                    if (avgHr > 0)
                    {
                         metrics.Add(new VitalMetric
                        {
                            Type = VitalType.HeartRate,
                            Value = Math.Round(avgHr),
                            Unit = "bpm",
                            Date = start, // Midnight
                            SourceDevice = "iOS"
                        });
                    }
                }

                // 3. Resting Heart Rate (Aggregation: AVERAGE or LATEST)
                // Resting HR is usually one value per day calculated by Apple, but can be multiple. Average is safe.
                var rhrType = HKQuantityType.Create(HKQuantityTypeIdentifier.RestingHeartRate);
                var rhrStats = await FetchStatistics(rhrType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                if (rhrStats != null)
                {
                     double avgRhr = rhrStats.AverageQuantity()?.GetDoubleValue(HKUnit.Count.UnitDividedBy(HKUnit.Minute)) ?? 0;
                     if (avgRhr > 0)
                     {
                          metrics.Add(new VitalMetric
                        {
                            Type = VitalType.RestingHeartRate,
                            Value = Math.Round(avgRhr),
                            Unit = "bpm",
                            Date = start, // Midnight
                            SourceDevice = "iOS"
                        });
                     }
                }

                // 4. Sleep (Aggregation: Duration Calculation via Samples)
                // StatisticsQuery doesn't work well for CategoryTypes, so we query samples and sum durations.
                var sleepType = HKCategoryType.Create(HKCategoryTypeIdentifier.SleepAnalysis);
                 await ExecuteQuery(sleepType, predicate, 0, (query, results, err) => {
                     if (results == null) return;
                     
                     double totalSleepMinutes = 0;
                     foreach (var sample in results)
                     {
                         if (sample is HKCategorySample catSample) {
                             // Consider filtering for Asleep/InBed values if needed, but for now sum all SleepAnalysis samples
                             // Apple usually provides 'InBed', 'Asleep', 'Awake'. 
                             // To be simple and match Android simplistic duration, we sum all 'Asleep' segments if possible, 
                             // but CategoryValue.SleepAnalysisAsleep is strict. 
                             // Let's sum everything in the category for now to match previous logic, 
                             // OR filter for Asleep (Value == 1) to be accurate. 
                             // Let's assume strict 'Asleep' (Value 1) is what users want.
                             
                             if (catSample.Value == (long)HKCategoryValueSleepAnalysis.Asleep || 
                                 catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepCore ||
                                 catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepDeep ||
                                 catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepREM)
                             {
                                 var duration = catSample.EndDate.SecondsSinceReferenceDate - catSample.StartDate.SecondsSinceReferenceDate;
                                 totalSleepMinutes += (duration / 60.0);
                             }
                         }
                     }
                     
                     if (totalSleepMinutes > 0)
                     {
                          metrics.Add(new VitalMetric
                          {
                              Type = VitalType.SleepDuration,
                              Value = Math.Round(totalSleepMinutes, 1), 
                              Unit = "min",
                              Date = start, // Midnight
                              SourceDevice = "iOS"
                          });
                     }
                 });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthKit] Fetch Error: {ex}");
            }

            return metrics;
        }

        // Helper for Statistics Query (Sum, Average, etc.)
        private Task<HKStatistics> FetchStatistics(HKQuantityType type, NSPredicate predicate, DateTime startDate, HKStatisticsOptions options)
        {
            var tcs = new TaskCompletionSource<HKStatistics>();
            
            // Note: HKStatisticsQuery is usually preferred for aggregation
            var statsQuery = new HKStatisticsQuery(type, predicate, options, (query, result, error) => 
            {
                if (error != null)
                {
                     Console.WriteLine($"[HealthKit] Stats Error {type.Identifier}: {error.LocalizedDescription}");
                     tcs.TrySetResult(null);
                }
                else
                {
                    tcs.TrySetResult(result);
                }
            });

            _healthStore.ExecuteQuery(statsQuery);
            return tcs.Task;
        }

        private Task FetchSamples(HKQuantityType type, NSPredicate predicate, Action<HKSample> mapper, int limit = 0)
        {
             var tcs = new TaskCompletionSource<bool>();
            
             void Handler(HKSampleQuery query, HKSample[] results, NSError error)
             {
                 if (error != null) 
                 {
                     Console.WriteLine($"[HealthKit] Error querying {type.Identifier}: {error.LocalizedDescription}");
                     tcs.TrySetResult(false);
                     return;
                 }

                 if (results != null)
                 {
                     foreach (var s in results) mapper(s);
                 }
                 tcs.TrySetResult(true);
             }

             // HKQuery.NoLimit corresponds to 0
             var sampleQuery = new HKSampleQuery(type, predicate, (nuint)limit, 
                 new NSSortDescriptor[] { new NSSortDescriptor(HKSample.SortIdentifierStartDate, false) }, 
                 Handler);

             _healthStore.ExecuteQuery(sampleQuery);
             return tcs.Task;
        }

         private Task ExecuteQuery(HKSampleType type, NSPredicate predicate, int limit, HKSampleQueryResultsHandler handler)
        {
             var tcs = new TaskCompletionSource<bool>();
             var sampleQuery = new HKSampleQuery(type, predicate, (nuint)limit, 
                 new NSSortDescriptor[] { new NSSortDescriptor(HKSample.SortIdentifierStartDate, false) }, 
                 (q, r, e) => {
                     handler(q, r, e);
                     tcs.TrySetResult(true);
                 });
             
             _healthStore.ExecuteQuery(sampleQuery);
             return tcs.Task;
        }
    }
}
