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
                    if (totalSteps > 10) // Filter Noise
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

                // 4. Sleep (Aggregation: End Date / Fallback to InBed)
                // Use StrictEndDate so we capture sleep that started yesterday but ended today (the session for "last night")
                var sleepType = HKCategoryType.Create(HKCategoryTypeIdentifier.SleepAnalysis);
                var sleepPredicate = HKQuery.GetPredicateForSamples(nsStart, nsEnd, HKQueryOptions.StrictEndDate);
                
                await ExecuteQuery(sleepType, sleepPredicate, 0, (query, results, err) => {
                     if (results == null) return;
                     
                     double asleepMinutes = 0;
                     double inBedMinutes = 0;

                     foreach (var sample in results)
                     {
                         if (sample is HKCategorySample catSample) {
                             var duration = (catSample.EndDate.SecondsSinceReferenceDate - catSample.StartDate.SecondsSinceReferenceDate) / 60.0;
                             
                             // Calculate Asleep
                             if (catSample.Value == (long)HKCategoryValueSleepAnalysis.Asleep || 
                                 catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepCore ||
                                 catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepDeep ||
                                 catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepREM)
                             {
                                 asleepMinutes += duration;
                             }

                             // Calculate InBed (Fallback)
                             if (catSample.Value == (long)HKCategoryValueSleepAnalysis.InBed)
                             {
                                 inBedMinutes += duration;
                             }
                         }
                     }
                     
                     // Priority: Asleep > InBed
                     var finalSleep = asleepMinutes > 0 ? asleepMinutes : inBedMinutes;

                     if (finalSleep > 10) // Filter Noise < 10 mins
                     {
                          metrics.Add(new VitalMetric
                          {
                              Type = VitalType.SleepDuration,
                              Value = Math.Round(finalSleep, 1), 
                              Unit = "min",
                              Date = start, // Midnight of the 'End Day'
                              SourceDevice = "iOS"
                          });
                     }
                 });

                 // -- EXPANDED ACTIVITY --

                 // 5. Floors Climbed (SUM)
                 var floorsType = HKQuantityType.Create(HKQuantityTypeIdentifier.FlightsClimbed);
                 var floorsStats = await FetchStatistics(floorsType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (floorsStats != null)
                 {
                      double totalFloors = floorsStats.SumQuantity()?.GetDoubleValue(HKUnit.Count) ?? 0;
                      if (totalFloors > 0) metrics.Add(NewMetric(VitalType.FloorsClimbed, Math.Round(totalFloors), "floors", start));
                 }

                 // 6. Basal Energy (SUM)
                 var basalType = HKQuantityType.Create(HKQuantityTypeIdentifier.BasalEnergyBurned);
                 var basalStats = await FetchStatistics(basalType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (basalStats != null)
                 {
                      double totalBasal = basalStats.SumQuantity()?.GetDoubleValue(HKUnit.Kilocalorie) ?? 0;
                      if (totalBasal > 10) metrics.Add(NewMetric(VitalType.BasalEnergyBurned, Math.Round(totalBasal), "kcal", start));
                 }

                 // 7. Walking Speed (AVG)
                 var speedType = HKQuantityType.Create(HKQuantityTypeIdentifier.WalkingSpeed);
                 var speedStats = await FetchStatistics(speedType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                 if (speedStats != null)
                 {
                      double avgSpeed = speedStats.AverageQuantity()?.GetDoubleValue(HKUnit.Meter.UnitDividedBy(HKUnit.Second)) ?? 0;
                      if (avgSpeed > 0) metrics.Add(NewMetric(VitalType.WalkingSpeed, Math.Round(avgSpeed, 2), "m/s", start));
                 }

                 // -- EXPANDED VITALS --

                 // 8. HRV (SDNN) (AVG)
                 var hrvType = HKQuantityType.Create(HKQuantityTypeIdentifier.HeartRateVariabilitySdnn);
                 var hrvStats = await FetchStatistics(hrvType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                 if (hrvStats != null)
                 {
                      double avgHrv = hrvStats.AverageQuantity()?.GetDoubleValue(HKUnit.FromString("ms")) ?? 0;
                      if (avgHrv > 0) metrics.Add(NewMetric(VitalType.HeartRateVariabilitySDNN, Math.Round(avgHrv, 1), "ms", start));
                 }

                 // 9. Respiratory Rate (AVG)
                 var rrType = HKQuantityType.Create(HKQuantityTypeIdentifier.RespiratoryRate);
                 var rrStats = await FetchStatistics(rrType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                 if (rrStats != null)
                 {
                      double avgRr = rrStats.AverageQuantity()?.GetDoubleValue(HKUnit.Count.UnitDividedBy(HKUnit.Minute)) ?? 0;
                      if (avgRr > 0) metrics.Add(NewMetric(VitalType.RespiratoryRate, Math.Round(avgRr, 1), "br/min", start));
                 }

                 // -- BODY --

                 // 10. Body Fat (LATEST/AVG)
                 var bfType = HKQuantityType.Create(HKQuantityTypeIdentifier.BodyFatPercentage);
                 var bfStats = await FetchStatistics(bfType, predicate, start, HKStatisticsOptions.DiscreteAverage); 
                 if (bfStats != null)
                 {
                      double avgBf = bfStats.AverageQuantity()?.GetDoubleValue(HKUnit.Percent) ?? 0;
                      if (avgBf > 0) metrics.Add(NewMetric(VitalType.BodyFatPercentage, Math.Round(avgBf * 100, 1), "%", start));
                 }

                 // 11. Lean Body Mass (LATEST/AVG)
                 var lbmType = HKQuantityType.Create(HKQuantityTypeIdentifier.LeanBodyMass);
                 var lbmStats = await FetchStatistics(lbmType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                 if (lbmStats != null)
                 {
                      double avgLbm = lbmStats.AverageQuantity()?.GetDoubleValue(HKUnit.FromString("kg")) ?? 0;
                      if (avgLbm > 0) metrics.Add(NewMetric(VitalType.LeanBodyMass, Math.Round(avgLbm, 1), "kg", start));
                 }

                 // -- NUTRITION --

                 // 12. Carbs (SUM)
                 var carbType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryCarbohydrates);
                 var carbStats = await FetchStatistics(carbType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (carbStats != null)
                 {
                      double totalCarbs = carbStats.SumQuantity()?.GetDoubleValue(HKUnit.Gram) ?? 0;
                      if (totalCarbs > 0) metrics.Add(NewMetric(VitalType.Carbs, Math.Round(totalCarbs), "g", start));
                 }

                 // 13. Fat (SUM)
                 var fatType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryFatTotal);
                 var fatStats = await FetchStatistics(fatType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (fatStats != null)
                 {
                      double totalFat = fatStats.SumQuantity()?.GetDoubleValue(HKUnit.Gram) ?? 0;
                      if (totalFat > 0) metrics.Add(NewMetric(VitalType.Fat, Math.Round(totalFat), "g", start));
                 }

                 // 14. Protein (SUM)
                 var protType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryProtein);
                 var protStats = await FetchStatistics(protType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (protStats != null)
                 {
                      double totalProt = protStats.SumQuantity()?.GetDoubleValue(HKUnit.Gram) ?? 0;
                      if (totalProt > 0) metrics.Add(NewMetric(VitalType.Protein, Math.Round(totalProt), "g", start));
                 }

                 // 15. Caffeine (SUM)
                 var caffType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryCaffeine);
                 var caffStats = await FetchStatistics(caffType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (caffStats != null)
                 {
                      double totalCaff = caffStats.SumQuantity()?.GetDoubleValue(HKUnit.FromString("mg")) ?? 0;
                      if (totalCaff > 0) metrics.Add(NewMetric(VitalType.Caffeine, Math.Round(totalCaff), "mg", start));
                 }
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

        
        private VitalMetric NewMetric(VitalType type, double value, string unit, DateTime date)
        {
            return new VitalMetric
            {
                Type = type,
                Value = value,
                Unit = unit,
                Date = date,
                SourceDevice = "iOS"
            };
        }
    }
}
