using System;
using System.Collections.Generic;
using System.Linq;

namespace Daily.Models.Health
{
    public class SleepSession
    {
        public DateTime StartTime { get; set; }
        public DateTime EndTime { get; set; }
        public bool IsNap { get; set; } = false;
        public List<HealthTelemetry> Stages { get; set; } = new();

        public double DeepSeconds => Stages.Where(x => x.SleepCategory == "Deep").Sum(x => x.DurationSeconds);
        public double RemSeconds => Stages.Where(x => x.SleepCategory == "REM").Sum(x => x.DurationSeconds);
        public double LightSeconds => Stages.Where(x => x.SleepCategory == "Core").Sum(x => x.DurationSeconds);
        public double AwakeSeconds => Stages.Where(x => x.SleepCategory == "Awake").Sum(x => x.DurationSeconds);
        public double AsleepSeconds => DeepSeconds + RemSeconds + LightSeconds;
        public double TotalStagesSeconds => DeepSeconds + RemSeconds + LightSeconds + AwakeSeconds;

        public double DurationSeconds
        {
            get
            {
                if (Stages.Any())
                {
                    var sumStages = TotalStagesSeconds;
                    var span = (EndTime - StartTime).TotalSeconds;
                    if (sumStages > 0 && span > sumStages * 1.35)
                    {
                        return sumStages;
                    }
                    return Math.Max(span, sumStages);
                }
                return Math.Max(0, (EndTime - StartTime).TotalSeconds);
            }
        }

        public DateTime EffectiveEndTime
        {
            get
            {
                if (Stages.Any() && DurationSeconds > 0 && (EndTime - StartTime).TotalSeconds > DurationSeconds * 1.35)
                {
                    return StartTime.AddSeconds(DurationSeconds);
                }
                return EndTime;
            }
        }

        public int AwakeCount => Stages.Count(x => x.SleepCategory == "Awake");

        public int DeepPercent => AsleepSeconds > 0 ? (int)((DeepSeconds / AsleepSeconds) * 100) : 0;
        public int RemPercent => AsleepSeconds > 0 ? (int)((RemSeconds / AsleepSeconds) * 100) : 0;
        public int LightPercent => AsleepSeconds > 0 ? (int)((LightSeconds / AsleepSeconds) * 100) : 0;
        public int AwakePercent => DurationSeconds > 0 ? (int)((AwakeSeconds / DurationSeconds) * 100) : 0;
        public int RestorativePercent => DeepPercent + RemPercent;

        public int EfficiencyPercent => DurationSeconds > 0 ? Math.Clamp((int)((AsleepSeconds / DurationSeconds) * 100), 10, 100) : 90;

        public int SleepScore
        {
            get
            {
                if (AsleepSeconds <= 0) return 0;
                double durationScore = Math.Min((AsleepSeconds / (8.0 * 3600.0)) * 50.0, 50.0);
                double efficiencyScore = (EfficiencyPercent / 100.0) * 30.0;
                double qualityScore = Math.Min((RestorativePercent / 40.0) * 20.0, 20.0);
                return Math.Clamp((int)(durationScore + efficiencyScore + qualityScore), 0, 100);
            }
        }

        public string SleepScoreQuality => SleepScore switch
        {
            >= 85 => "Optimal",
            >= 75 => "Good",
            >= 60 => "Fair",
            > 0 => "Low",
            _ => "No Data"
        };

        public string TotalAsleepFormatted => FormatSeconds(AsleepSeconds);
        public string TimeInBedFormatted => FormatSeconds(DurationSeconds);
        public string DeepFormatted => FormatSeconds(DeepSeconds);
        public string RemFormatted => FormatSeconds(RemSeconds);
        public string LightFormatted => FormatSeconds(LightSeconds);
        public string AwakeFormatted => FormatSeconds(AwakeSeconds);

        public string BedtimeFormatted => StartTime != DateTime.MinValue ? StartTime.ToString("HH:mm") : "--";
        public string WakeTimeFormatted => EffectiveEndTime != DateTime.MinValue ? EffectiveEndTime.ToString("HH:mm") : "--";

        private static string FormatSeconds(double s)
        {
            if (s <= 0) return "--";
            var ts = TimeSpan.FromSeconds(s);
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
        }
    }
}
