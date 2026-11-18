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
        public string SourceDevice { get; set; } = "Unknown";
        public bool HasGranularHypnogram { get; set; } = true;
        public List<HealthTelemetry> Stages { get; set; } = new();

        private double? _deepSeconds;
        public double DeepSeconds
        {
            get => _deepSeconds ?? Stages.Where(x => x.SleepCategory == "Deep").Sum(x => x.DurationSeconds);
            set => _deepSeconds = value;
        }

        private double? _remSeconds;
        public double RemSeconds
        {
            get => _remSeconds ?? Stages.Where(x => x.SleepCategory == "REM").Sum(x => x.DurationSeconds);
            set => _remSeconds = value;
        }

        private double? _lightSeconds;
        public double LightSeconds
        {
            get => _lightSeconds ?? Stages.Where(x => x.SleepCategory == "Core" || x.SleepCategory == "Light").Sum(x => x.DurationSeconds);
            set => _lightSeconds = value;
        }

        private double? _awakeSeconds;
        public double AwakeSeconds
        {
            get => _awakeSeconds ?? Stages.Where(x => x.SleepCategory == "Awake").Sum(x => x.DurationSeconds);
            set => _awakeSeconds = value;
        }
        private double? _asleepSeconds;
        public double AsleepSeconds
        {
            get => _asleepSeconds ?? (DeepSeconds + RemSeconds + LightSeconds);
            set => _asleepSeconds = value;
        }
        public double TotalStagesSeconds => DeepSeconds + RemSeconds + LightSeconds + AwakeSeconds;

        private double? _durationSeconds;
        public double DurationSeconds
        {
            get
            {
                if (_durationSeconds.HasValue) return _durationSeconds.Value;
                var span = Math.Max(0, (EndTime - StartTime).TotalSeconds);
                if (Stages.Any())
                {
                    var sumStages = TotalStagesSeconds;
                    if (sumStages <= 0) return span;
                    var untrackedBreaks = ComputeUntrackedBreakSeconds(Stages, StartTime, EndTime);
                    var effectiveSpan = Math.Max(0, span - untrackedBreaks);
                    if (effectiveSpan > sumStages * 1.35)
                    {
                        return sumStages;
                    }
                    return Math.Max(effectiveSpan, sumStages);
                }
                return span;
            }
            set => _durationSeconds = value;
        }

        public DateTime EffectiveEndTime
        {
            get
            {
                if (Stages.Any() && DurationSeconds > 0 && (EndTime - StartTime).TotalSeconds > DurationSeconds * 1.35)
                {
                    var lastStageEnd = Stages.Max(s => s.EffectiveEndTime);
                    if ((EndTime - lastStageEnd).TotalSeconds > 1800)
                    {
                        return StartTime.AddSeconds(DurationSeconds);
                    }
                }
                return EndTime;
            }
        }

        private static double ComputeUntrackedBreakSeconds(
            List<HealthTelemetry> stages,
            DateTime sessionStart,
            DateTime sessionEnd,
            double minBreakSeconds = 45 * 60)
        {
            var sorted = stages.OrderBy(s => s.StartTime).ToList();
            if (sorted.Count == 0) return 0;

            double untracked = 0;
            var leadingGap = (sorted[0].StartTime - sessionStart).TotalSeconds;
            if (leadingGap >= minBreakSeconds)
            {
                untracked += leadingGap;
            }

            var cursorEnd = sorted[0].EffectiveEndTime;
            for (int i = 1; i < sorted.Count; i++)
            {
                var curr = sorted[i];
                var gap = (curr.StartTime - cursorEnd).TotalSeconds;
                if (gap >= minBreakSeconds)
                {
                    untracked += gap;
                }
                if (curr.EffectiveEndTime > cursorEnd)
                {
                    cursorEnd = curr.EffectiveEndTime;
                }
            }

            var trailingGap = (sessionEnd - cursorEnd).TotalSeconds;
            if (trailingGap >= minBreakSeconds)
            {
                untracked += trailingGap;
            }
            return untracked;
        }

        /// <summary>
        /// Derives explorable sleep segments (Stage 1, Stage 2, ...) on-the-fly when a nocturnal
        /// session contains 2+ sleep episodes separated either by an untracked break (>= 45m) or a
        /// sustained wake interval (>= 45m) flanked by >= 20m of real sleep on each side.
        /// Returns an empty list for standard single-segment nights.
        /// </summary>
        public List<SleepSession> GetSleepSegments()
        {
            if (IsNap || Stages == null || Stages.Count < 2) return new List<SleepSession>();
            const double minBreakSeconds = 45 * 60;
            const double minSegmentAsleepSeconds = 20 * 60;

            var sorted = Stages.OrderBy(s => s.StartTime).ToList();

            // 1. Split on untracked gaps >= 45 minutes
            var contiguousRuns = new List<List<HealthTelemetry>>();
            var currentRun = new List<HealthTelemetry> { sorted[0] };
            var runCursorEnd = sorted[0].EffectiveEndTime;

            for (int i = 1; i < sorted.Count; i++)
            {
                var st = sorted[i];
                var gap = (st.StartTime - runCursorEnd).TotalSeconds;
                if (gap >= minBreakSeconds)
                {
                    contiguousRuns.Add(currentRun);
                    currentRun = new List<HealthTelemetry> { st };
                    runCursorEnd = st.EffectiveEndTime;
                }
                else
                {
                    currentRun.Add(st);
                    if (st.EffectiveEndTime > runCursorEnd)
                    {
                        runCursorEnd = st.EffectiveEndTime;
                    }
                }
            }
            contiguousRuns.Add(currentRun);

            // 2. Within each contiguous run, split on sustained Awake blocks >= 45m flanked by >= 20m sleep
            static List<List<HealthTelemetry>> SplitOnSustainedAwake(List<HealthTelemetry> run)
            {
                int idx = 0;
                while (idx < run.Count)
                {
                    if (run[idx].SleepCategory == "Awake")
                    {
                        int endIdx = idx;
                        double awakeDur = run[idx].DurationSeconds;
                        while (endIdx + 1 < run.Count && run[endIdx + 1].SleepCategory == "Awake")
                        {
                            endIdx++;
                            awakeDur += run[endIdx].DurationSeconds;
                        }
                        if (awakeDur >= minBreakSeconds)
                        {
                            var before = run.Take(idx).ToList();
                            var after = run.Skip(endIdx + 1).ToList();
                            double beforeAsleep = before.Where(s => s.SleepCategory != "Awake").Sum(s => s.DurationSeconds);
                            double afterAsleep = after.Where(s => s.SleepCategory != "Awake").Sum(s => s.DurationSeconds);
                            if (beforeAsleep >= minSegmentAsleepSeconds && afterAsleep >= minSegmentAsleepSeconds)
                            {
                                var combined = new List<List<HealthTelemetry>> { before };
                                combined.AddRange(SplitOnSustainedAwake(after));
                                return combined;
                            }
                        }
                        idx = endIdx + 1;
                    }
                    else
                    {
                        idx++;
                    }
                }
                return new List<List<HealthTelemetry>> { run };
            }

            var candidateLists = contiguousRuns
                .SelectMany(SplitOnSustainedAwake)
                .Where(list => list.Where(s => s.SleepCategory != "Awake").Sum(s => s.DurationSeconds) >= minSegmentAsleepSeconds)
                .ToList();

            if (candidateLists.Count < 2) return new List<SleepSession>();

            var segments = new List<SleepSession>();
            foreach (var segStages in candidateLists)
            {
                var segStart = segStages.First().StartTime;
                var segEnd = segStages.Max(s => s.EffectiveEndTime);
                segments.Add(new SleepSession
                {
                    StartTime = segStart,
                    EndTime = segEnd,
                    IsNap = false,
                    Stages = segStages,
                    SourceDevice = SourceDevice,
                    HasGranularHypnogram = HasGranularHypnogram
                });
            }
            return segments;
        }

        public int AwakeCount => Stages.Count(x => x.SleepCategory == "Awake");

        public int DeepPercent => AsleepSeconds > 0 ? (int)Math.Round((DeepSeconds / AsleepSeconds) * 100.0, MidpointRounding.AwayFromZero) : 0;
        public int RemPercent => AsleepSeconds > 0 ? (int)Math.Round((RemSeconds / AsleepSeconds) * 100.0, MidpointRounding.AwayFromZero) : 0;
        public int LightPercent => AsleepSeconds > 0 ? (int)Math.Round((LightSeconds / AsleepSeconds) * 100.0, MidpointRounding.AwayFromZero) : 0;
        public int AwakePercent => DurationSeconds > 0 ? (int)Math.Round((AwakeSeconds / DurationSeconds) * 100.0, MidpointRounding.AwayFromZero) : 0;
        public int RestorativePercent => DeepPercent + RemPercent;

        public int EfficiencyPercent => DurationSeconds > 0 ? Math.Clamp((int)Math.Round((AsleepSeconds / DurationSeconds) * 100.0, MidpointRounding.AwayFromZero), 10, 100) : 90;

        private int? _sleepScore;
        public int SleepScore
        {
            get
            {
                if (_sleepScore.HasValue) return _sleepScore.Value;
                if (AsleepSeconds <= 0) return 0;

                double asleepHours = AsleepSeconds / 3600.0;
                double durationScore;
                if (asleepHours >= 7.5 && asleepHours <= 9.0)
                    durationScore = 38.0 + Math.Min(((asleepHours - 7.5) / 1.5) * 2.0, 2.0);
                else if (asleepHours > 9.0)
                    durationScore = Math.Max(34.0, 40.0 - (asleepHours - 9.0) * 2.0);
                else if (asleepHours >= 7.0)
                    durationScore = 34.0 + ((asleepHours - 7.0) / 0.5) * 4.0;
                else if (asleepHours >= 6.0)
                    durationScore = 24.0 + (asleepHours - 6.0) * 10.0;
                else if (asleepHours >= 5.0)
                    durationScore = 14.0 + (asleepHours - 5.0) * 10.0;
                else
                    durationScore = Math.Max(0.0, (asleepHours / 5.0) * 14.0);

                double eff = EfficiencyPercent;
                double effScore;
                if (eff >= 95.0) effScore = 25.0;
                else if (eff >= 90.0) effScore = 21.0 + ((eff - 90.0) / 5.0) * 4.0;
                else if (eff >= 85.0) effScore = 16.0 + ((eff - 85.0) / 5.0) * 5.0;
                else if (eff >= 80.0) effScore = 10.0 + ((eff - 80.0) / 5.0) * 6.0;
                else effScore = Math.Max(0.0, (eff / 80.0) * 10.0);

                double dp = DeepPercent;
                double deepScore = dp >= 16.0
                    ? 11.0 + Math.Min(((dp - 16.0) / 6.0) * 2.0, 2.0)
                    : (dp >= 10.0 ? 6.0 + ((dp - 10.0) / 6.0) * 5.0 : Math.Max(0.0, (dp / 10.0) * 6.0));

                double rp = RemPercent;
                double remScore = rp >= 20.0
                    ? 10.0 + Math.Min(((rp - 20.0) / 5.0) * 2.0, 2.0)
                    : (rp >= 14.0 ? 5.0 + ((rp - 14.0) / 6.0) * 5.0 : Math.Max(0.0, (rp / 14.0) * 5.0));

                double qualScore = deepScore + remScore;

                int awakeCount = AwakeCount;
                double awakeMinutes = AwakeSeconds / 60.0;
                double awakeCountPenalty = awakeCount <= 2 ? 0.0 : (awakeCount <= 4 ? 1.5 : Math.Min(1.5 + (awakeCount - 4) * 0.75, 5.0));
                double awakeDurationPenalty = awakeMinutes <= 25.0 ? 0.0 : Math.Min(((awakeMinutes - 25.0) / 10.0) * 1.0, 5.0);
                double restfulnessScore = Math.Max(1.0, 10.0 - awakeCountPenalty - awakeDurationPenalty);

                int total = (int)Math.Round(durationScore + effScore + qualScore + restfulnessScore, MidpointRounding.AwayFromZero);
                return Math.Clamp(total, 0, 100);
            }
            set => _sleepScore = value;
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
