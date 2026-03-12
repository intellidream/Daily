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
                // Activity
                HKQuantityType.Create(HKQuantityTypeIdentifier.StepCount),
                HKQuantityType.Create(HKQuantityTypeIdentifier.ActiveEnergyBurned),
                HKQuantityType.Create(HKQuantityTypeIdentifier.BasalEnergyBurned),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DistanceWalkingRunning),
                HKQuantityType.Create(HKQuantityTypeIdentifier.FlightsClimbed),
                HKQuantityType.Create(HKQuantityTypeIdentifier.WalkingSpeed),
                // Heart & Vitals
                HKQuantityType.Create(HKQuantityTypeIdentifier.HeartRate),
                HKQuantityType.Create(HKQuantityTypeIdentifier.RestingHeartRate),
                HKQuantityType.Create(HKQuantityTypeIdentifier.HeartRateVariabilitySdnn),
                HKQuantityType.Create(HKQuantityTypeIdentifier.RespiratoryRate),
                HKQuantityType.Create(HKQuantityTypeIdentifier.OxygenSaturation),
                HKQuantityType.Create(HKQuantityTypeIdentifier.BodyTemperature),
                HKQuantityType.Create(HKQuantityTypeIdentifier.BloodPressureSystolic),
                HKQuantityType.Create(HKQuantityTypeIdentifier.BloodPressureDiastolic),
                HKQuantityType.Create(HKQuantityTypeIdentifier.BloodGlucose),
                // Body
                HKQuantityType.Create(HKQuantityTypeIdentifier.BodyMass),
                HKQuantityType.Create(HKQuantityTypeIdentifier.BodyFatPercentage),
                HKQuantityType.Create(HKQuantityTypeIdentifier.LeanBodyMass),
                HKQuantityType.Create(HKQuantityTypeIdentifier.Height),
                // Nutrition
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryCarbohydrates),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryFatTotal),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryProtein),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryCaffeine),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietarySugar),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryVitaminC),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryIron),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryMagnesium),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryZinc),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryCalcium),
                HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryWater),
                // Sleep & Mindfulness
                HKCategoryType.Create(HKCategoryTypeIdentifier.SleepAnalysis),
                HKCategoryType.Create(HKCategoryTypeIdentifier.MindfulSession),
                // Cycle Tracking
                HKCategoryType.Create(HKCategoryTypeIdentifier.MenstrualFlow),
            };

            // CyclingPower requires iOS 17+
            try { readTypes.Add(HKQuantityType.Create(HKQuantityTypeIdentifier.CyclingPower)); } catch { }

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
                     double deepMinutes = 0;
                     double lightMinutes = 0;  // Core = Light in HealthKit
                     double remMinutes = 0;
                     double awakeMinutes = 0;

                     foreach (var sample in results)
                     {
                         if (sample is HKCategorySample catSample) {
                             var duration = (catSample.EndDate.SecondsSinceReferenceDate - catSample.StartDate.SecondsSinceReferenceDate) / 60.0;
                             
                             if (catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepDeep)
                             {
                                 asleepMinutes += duration;
                                 deepMinutes += duration;
                             }
                             else if (catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepCore)
                             {
                                 asleepMinutes += duration;
                                 lightMinutes += duration;
                             }
                             else if (catSample.Value == (long)HKCategoryValueSleepAnalysis.AsleepREM)
                             {
                                 asleepMinutes += duration;
                                 remMinutes += duration;
                             }
                             else if (catSample.Value == (long)HKCategoryValueSleepAnalysis.Asleep)
                             {
                                 asleepMinutes += duration; // Generic asleep (older iOS)
                             }
                             else if (catSample.Value == (long)HKCategoryValueSleepAnalysis.Awake)
                             {
                                 awakeMinutes += duration;
                             }
                             else if (catSample.Value == (long)HKCategoryValueSleepAnalysis.InBed)
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
                              Date = start,
                              SourceDevice = "iOS"
                          });
                     }

                     // Individual Sleep Stages
                     if (deepMinutes > 0) metrics.Add(NewMetric(VitalType.SleepDeep, Math.Round(deepMinutes, 1), "min", start));
                     if (lightMinutes > 0) metrics.Add(NewMetric(VitalType.SleepLight, Math.Round(lightMinutes, 1), "min", start));
                     if (remMinutes > 0) metrics.Add(NewMetric(VitalType.SleepREM, Math.Round(remMinutes, 1), "min", start));
                     if (awakeMinutes > 0) metrics.Add(NewMetric(VitalType.SleepAwake, Math.Round(awakeMinutes, 1), "min", start));
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

                 // -- MISSING METRICS (iOS Parity with Android) --

                 // Active Energy / Calories (SUM)
                 var calType = HKQuantityType.Create(HKQuantityTypeIdentifier.ActiveEnergyBurned);
                 var calStats = await FetchStatistics(calType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (calStats != null)
                 {
                     double totalCal = calStats.SumQuantity()?.GetDoubleValue(HKUnit.Kilocalorie) ?? 0;
                     if (totalCal > 10) metrics.Add(NewMetric(VitalType.ActiveEnergy, Math.Round(totalCal), "kcal", start));
                 }

                 // Weight (Latest via Sample Query)
                 var weightType = HKQuantityType.Create(HKQuantityTypeIdentifier.BodyMass);
                 var weightStats = await FetchStatistics(weightType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                 if (weightStats != null)
                 {
                     double wVal = weightStats.AverageQuantity()?.GetDoubleValue(HKUnit.FromString("kg")) ?? 0;
                     if (wVal > 0) metrics.Add(NewMetric(VitalType.Weight, Math.Round(wVal, 1), "kg", start));
                 }

                 // Distance (SUM)
                 var distType = HKQuantityType.Create(HKQuantityTypeIdentifier.DistanceWalkingRunning);
                 var distStats = await FetchStatistics(distType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (distStats != null)
                 {
                     double totalDist = distStats.SumQuantity()?.GetDoubleValue(HKUnit.Meter) ?? 0;
                     if (totalDist > 10) metrics.Add(NewMetric(VitalType.Distance, Math.Round(totalDist, 2), "m", start));
                 }

                 // Blood Pressure (Correlation Type - requires Sample Query)
                 try {
                     var bpType = HKCorrelationType.Create(HKCorrelationTypeIdentifier.BloodPressure);
                     await ExecuteQuery(bpType, predicate, 0, (q, r, e) => {
                         if (r == null) return;
                         double sysSum = 0, diaSum = 0; int bpCount = 0;
                         foreach (var s in r) {
                             if (s is HKCorrelation corr) {
                                 foreach (var obj in corr.Objects) {
                                     if (obj is HKQuantitySample qs) {
                                         if (qs.QuantityType.Identifier == HKQuantityTypeIdentifier.BloodPressureSystolic.ToString())
                                             sysSum += qs.Quantity.GetDoubleValue(HKUnit.MillimeterOfMercury);
                                         else if (qs.QuantityType.Identifier == HKQuantityTypeIdentifier.BloodPressureDiastolic.ToString())
                                             diaSum += qs.Quantity.GetDoubleValue(HKUnit.MillimeterOfMercury);
                                     }
                                 }
                                 bpCount++;
                             }
                         }
                         if (bpCount > 0) {
                             metrics.Add(NewMetric(VitalType.BloodPressureSystolic, Math.Round(sysSum / bpCount), "mmHg", start));
                             metrics.Add(NewMetric(VitalType.BloodPressureDiastolic, Math.Round(diaSum / bpCount), "mmHg", start));
                         }
                     });
                 } catch {}

                 // Blood Glucose (AVG)
                 try {
                     var bgType = HKQuantityType.Create(HKQuantityTypeIdentifier.BloodGlucose);
                     var bgStats = await FetchStatistics(bgType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                     if (bgStats != null) {
                         double val = bgStats.AverageQuantity()?.GetDoubleValue(HKUnit.FromString("mg/dL")) ?? 0;
                         if (val > 0) metrics.Add(NewMetric(VitalType.BloodGlucose, Math.Round(val), "mg/dL", start));
                     }
                 } catch {}

                 // SpO2 (AVG)
                 try {
                     var o2Type = HKQuantityType.Create(HKQuantityTypeIdentifier.OxygenSaturation);
                     var o2Stats = await FetchStatistics(o2Type, predicate, start, HKStatisticsOptions.DiscreteAverage);
                     if (o2Stats != null) {
                         double val = o2Stats.AverageQuantity()?.GetDoubleValue(HKUnit.Percent) ?? 0;
                         if (val > 0) metrics.Add(NewMetric(VitalType.OxygenSaturation, Math.Round(val * 100, 1), "%", start));
                     }
                 } catch {}

                 // Body Temperature (AVG)
                 try {
                     var btType = HKQuantityType.Create(HKQuantityTypeIdentifier.BodyTemperature);
                     var btStats = await FetchStatistics(btType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                     if (btStats != null) {
                         double val = btStats.AverageQuantity()?.GetDoubleValue(HKUnit.DegreeCelsius) ?? 0;
                         if (val > 0) metrics.Add(NewMetric(VitalType.BodyTemperature, Math.Round(val, 1), "C", start));
                     }
                 } catch {}

                 // Hydration / Water (SUM)
                 try {
                     var h2oType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryWater);
                     var h2oStats = await FetchStatistics(h2oType, predicate, start, HKStatisticsOptions.CumulativeSum);
                     if (h2oStats != null) {
                         double val = h2oStats.SumQuantity()?.GetDoubleValue(HKUnit.Liter) ?? 0;
                         if (val > 0) metrics.Add(NewMetric(VitalType.Hydration, Math.Round(val, 2), "L", start));
                     }
                 } catch {}

                 // -- NUTRITION V50 METRICS --

                 // Sugar (SUM)
                 var sugarType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietarySugar);
                 var sugarStats = await FetchStatistics(sugarType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (sugarStats != null) {
                     double val = sugarStats.SumQuantity()?.GetDoubleValue(HKUnit.Gram) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.Sugar, Math.Round(val), "g", start));
                 }
                 
                 // Vitamin C (SUM)
                 var vitCType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryVitaminC);
                 var vitCStats = await FetchStatistics(vitCType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (vitCStats != null) {
                     double val = vitCStats.SumQuantity()?.GetDoubleValue(HKUnit.FromString("mg")) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.VitaminC, Math.Round(val), "mg", start));
                 }

                 // Iron (SUM)
                 var ironType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryIron);
                 var ironStats = await FetchStatistics(ironType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (ironStats != null) {
                     double val = ironStats.SumQuantity()?.GetDoubleValue(HKUnit.FromString("mg")) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.Iron, Math.Round(val), "mg", start));
                 }

                 // Magnesium (SUM)
                 var magType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryMagnesium);
                 var magStats = await FetchStatistics(magType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (magStats != null) {
                     double val = magStats.SumQuantity()?.GetDoubleValue(HKUnit.FromString("mg")) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.Magnesium, Math.Round(val), "mg", start));
                 }

                 // Zinc (SUM)
                 var zincType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryZinc);
                 var zincStats = await FetchStatistics(zincType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (zincStats != null) {
                     double val = zincStats.SumQuantity()?.GetDoubleValue(HKUnit.FromString("mg")) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.Zinc, Math.Round(val), "mg", start));
                 }

                 // Calcium (SUM)
                 var calcType = HKQuantityType.Create(HKQuantityTypeIdentifier.DietaryCalcium);
                 var calcStats = await FetchStatistics(calcType, predicate, start, HKStatisticsOptions.CumulativeSum);
                 if (calcStats != null) {
                     double val = calcStats.SumQuantity()?.GetDoubleValue(HKUnit.FromString("mg")) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.Calcium, Math.Round(val), "mg", start));
                 }

                 // 19. Cycle Tracking (Sample Query)
                 var mensType = HKCategoryType.Create(HKCategoryTypeIdentifier.MenstrualFlow);
                 await ExecuteQuery(mensType, predicate, 1, (q, r, e) => {
                     if (r != null && r.Length > 0) metrics.Add(NewMetric(VitalType.MenstruationFlow, 1, "bool", start));
                 });

                 // 20. Mindfulness (SUM Duration)
                 var mindType = HKCategoryType.Create(HKCategoryTypeIdentifier.MindfulSession);
                 await ExecuteQuery(mindType, predicate, 0, (q, r, e) => {
                     if (r != null) {
                        double totalMind = 0;
                        foreach(var s in r) totalMind += (s.EndDate.SecondsSinceReferenceDate - s.StartDate.SecondsSinceReferenceDate) / 60.0;
                        if (totalMind > 0) metrics.Add(NewMetric(VitalType.MindfulSession, Math.Round(totalMind), "min", start));
                     }
                 });

                 // 21. Height (Latest)
                 var heightType = HKQuantityType.Create(HKQuantityTypeIdentifier.Height);
                 var heightStats = await FetchStatistics(heightType, predicate, start, HKStatisticsOptions.DiscreteAverage); // or latest sample
                 if (heightStats != null) {
                     double val = heightStats.AverageQuantity()?.GetDoubleValue(HKUnit.Meter) ?? 0;
                     if (val > 0) metrics.Add(NewMetric(VitalType.Height, Math.Round(val, 2), "m", start));
                 }
                 
                 // 22. Cycling Power (Avg)
                 if (HKHealthStore.IsHealthDataAvailable) { // Check specific version/device support implicitly via Type Create
                      try {
                          var powerType = HKQuantityType.Create(HKQuantityTypeIdentifier.CyclingPower);
                          var powerStats = await FetchStatistics(powerType, predicate, start, HKStatisticsOptions.DiscreteAverage);
                          if (powerStats != null) {
                              double val = powerStats.AverageQuantity()?.GetDoubleValue(HKUnit.Watt) ?? 0;
                              if (val > 0) metrics.Add(NewMetric(VitalType.CyclingPower, Math.Round(val), "W", start));
                          }
                      } catch {}
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
