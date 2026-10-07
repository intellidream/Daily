// Types for the Canonical Health & Vitals Engine (v1.0)
// Compatible with Deno and Node.js

export interface HealthTelemetryRow {
  id: string;
  user_id: string;
  type: string;
  value: number | null;
  unit: string | null;
  start_time: string; // ISO-8601 UTC
  end_time: string | null; // ISO-8601 UTC
  source_device: string | null;
  host_device_name?: string | null;
  sensor_source_name?: string | null;
  source_device_key?: string | null;
  source_color?: string | null;
  external_id?: string | null;
  source_id?: string | null;
  semantics?: string | null;
  tz_offset_min?: number | null;
  local_date?: string | null;
  created_at?: string | null;
}

export type SleepStageType = 'Awake' | 'REM' | 'Light' | 'Deep' | 'Unknown';

export interface SleepStageRecord {
  id: string;
  stage_type: SleepStageType;
  start_time: string;
  end_time: string;
  duration_seconds: number;
  source_device: string;
}

export interface SleepSession {
  id: string;
  start_time: string;
  end_time: string;
  is_nap: boolean;
  source_device: string;
  has_granular_hypnogram: boolean;
  stages: SleepStageRecord[];
  asleep_seconds: number;
  duration_seconds: number;
  deep_seconds: number;
  rem_seconds: number;
  light_seconds: number;
  awake_seconds: number;
  deep_percent: number;
  rem_percent: number;
  light_percent: number;
  awake_percent: number;
  restorative_percent: number;
  efficiency_percent: number;
  awake_count: number;
  sleep_score: number;
  quality_rating: string;
}

export interface NapSession {
  id: string;
  start_time: string;
  end_time: string;
  duration_seconds: number;
  source_device: string;
}

export interface SleepRecoveryVerdict {
  status: 'Optimal' | 'Great' | 'Fair' | 'Deficit';
  headline: string;
  narrative: string;
  readiness_score: number;
  physical_repair_rating: string;
  cognitive_restore_rating: string;
  sleep_continuity_rating: string;
}

export interface SleepActionableTip {
  id: string;
  category: 'circadian' | 'environment' | 'nutrition' | 'windDown';
  title: string;
  advice: string;
  scientific_rationale: string;
}

export interface SleepAIContext {
  narrative_synthesis: string;
  suggested_prompts: string[];
}

export interface SleepGuidance {
  verdict: SleepRecoveryVerdict;
  tips: SleepActionableTip[];
  ai_context: SleepAIContext;
}

export interface HourlyStepBucket {
  hour: number;
  steps: number;
}

export interface ActivitySummary {
  total_steps: number;
  active_calories: number;
  source_device: string | null;
  hourly_steps: HourlyStepBucket[];
}

export type HeartRateZoneName = 'Resting' | 'Fat Burn' | 'Cardio' | 'Peak';

export interface IntradayHeartRatePoint {
  id: string;
  timestamp: string;
  bpm: number;
  zone: HeartRateZoneName;
  source_device: string | null;
}

export interface CardiovascularSummary {
  average_bpm: number | null;
  resting_bpm: number | null;
  min_bpm: number | null;
  max_bpm: number | null;
  zones: {
    resting: number;
    fat_burn: number;
    cardio: number;
    peak: number;
  };
  intraday_points: IntradayHeartRatePoint[];
}

export type StressLevelName = 'Restful' | 'Calm' | 'Moderate' | 'High';
export type MonkeyMoodName = 'Zen Monkey' | 'Curious Monkey' | 'Busy Monkey' | 'Overheated Monkey';

export interface IntradayStressPoint {
  timestamp: string;
  hour: number;
  score: number;
  level: StressLevelName;
  hrv_ms: number | null;
  heart_rate_bpm: number | null;
  is_sedentary: boolean;
}

export interface StressSummary {
  current_score: number;
  current_level: StressLevelName;
  daily_average: number;
  peak_hour: number | null;
  peak_score: number | null;
  lowest_hour: number | null;
  lowest_score: number | null;
  parasympathetic_percent: number;
  sympathetic_percent: number;
  baseline_hrv_ms: number;
  current_hrv_ms: number | null;
  hrv_delta_percent: number | null;
  resting_heart_rate_bpm: number | null;
  current_sedentary_bpm: number | null;
  heart_rate_elevation_bpm: number | null;
  monkey_mood: MonkeyMoodName;
  advice_quote: string;
  recommended_breathing: string;
  intraday_points: IntradayStressPoint[];
}

export interface VitalSummaryItem {
  type: string;
  value: number;
  unit: string;
  source_device: string | null;
  timestamp: string;
}

export interface DeviceMetricItem {
  value: number;
  source_key: string;
  source_color: string;
  timestamp?: string;
  score?: number;
}

export interface DailyHealthSummaryPayload {
  date: string;
  engine_version: string;
  computed_at: string;
  sources?: string[];
  all_devices_view?: Record<string, DeviceMetricItem>;
  sources_breakdown?: Record<string, Record<string, number>>;
  sleep: {
    primary_session: SleepSession | null;
    all_sessions: SleepSession[];
    naps: NapSession[];
    guidance: SleepGuidance | null;
  };
  activity: ActivitySummary;
  cardiovascular: CardiovascularSummary;
  stress: StressSummary | null;
  vitals: Record<string, VitalSummaryItem>;
}

export interface HealthDailySummaryRow {
  id?: string;
  user_id: string;
  local_date: string;
  computed_at: string;
  engine_version: string;
  raw_watermark: string | null;
  steps: number | null;
  active_kcal: number | null;
  sleep_asleep_s: number | null;
  sleep_score: number | null;
  stress_avg: number | null;
  rhr: number | null;
  hrv_sdnn: number | null;
  hrv_rmssd: number | null;
  weight: number | null;
  spo2: number | null;
  summary: DailyHealthSummaryPayload;
}
