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
            
            // Calculate Start/End for the specific Date
            DateTime start = date.Date;
            DateTime end = date.Date.AddDays(1);

            var nsStart = (NSDate)start;
            var nsEnd = (NSDate)end;
            var predicate = HKQuery.GetPredicateForSamples(nsStart, nsEnd, HKQueryOptions.StrictStartDate);

            try 
            {
                // Steps
                var stepType = HKQuantityType.Create(HKQuantityTypeIdentifier.StepCount);
                await FetchSamples(stepType, predicate, (sample) => 
                {
                     if (sample is HKQuantitySample qty)
                     {
                         metrics.Add(new VitalMetric
                         {
                             Type = VitalType.Steps,
                             Value = qty.Quantity.GetDoubleValue(HKUnit.Count),
                             Unit = "steps",
                             Date = (DateTime)qty.StartDate,
                             SourceDevice = "iOS"
                         });
                     }
                });

                // Heart Rate
                var hrType = HKQuantityType.Create(HKQuantityTypeIdentifier.HeartRate);
                await FetchSamples(hrType, predicate, (sample) => 
                {
                     if (sample is HKQuantitySample qty)
                     {
                         metrics.Add(new VitalMetric
                         {
                             Type = VitalType.HeartRate,
                             Value = qty.Quantity.GetDoubleValue(HKUnit.Count.UnitDividedBy(HKUnit.Minute)),
                             Unit = "bpm",
                             Date = (DateTime)qty.StartDate,
                             SourceDevice = "iOS"
                         });
                     }
                }, limit: 500);

                // Resting HR
                var rhrType = HKQuantityType.Create(HKQuantityTypeIdentifier.RestingHeartRate);
                 await FetchSamples(rhrType, predicate, (sample) => 
                {
                     if (sample is HKQuantitySample qty)
                     {
                         metrics.Add(new VitalMetric
                         {
                             Type = VitalType.RestingHeartRate,
                             Value = qty.Quantity.GetDoubleValue(HKUnit.Count.UnitDividedBy(HKUnit.Minute)),
                             Unit = "bpm",
                             Date = (DateTime)qty.StartDate,
                             SourceDevice = "iOS"
                         });
                     }
                });

                // Sleep
                var sleepType = HKCategoryType.Create(HKCategoryTypeIdentifier.SleepAnalysis);
                 await ExecuteQuery(sleepType, predicate, 0, (query, results, err) => {
                     if (results == null) return;
                     foreach (var sample in results)
                     {
                         if (sample is HKCategorySample catSample) {
                             var duration = catSample.EndDate.SecondsSinceReferenceDate - catSample.StartDate.SecondsSinceReferenceDate;
                             if (duration > 0)
                             {
                                 metrics.Add(new VitalMetric
                                 {
                                     Type = VitalType.SleepDuration,
                                     Value = duration / 60.0, 
                                     Unit = "min",
                                     Date = (DateTime)catSample.StartDate,
                                     SourceDevice = "iOS"
                                 });
                             }
                         }
                     }
                 });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthKit] Fetch Error: {ex}");
            }

            return metrics;
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
