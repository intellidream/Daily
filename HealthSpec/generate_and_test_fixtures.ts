// Generates comprehensive Golden Fixtures for HealthSpec and tests them against the TypeScript Canonical Engine.
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeDailyHealthSummary } from '../supabase/functions/health-engine/engine.ts';
import type { HealthTelemetryRow } from '../supabase/functions/health-engine/types.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const FIXTURES_DIR = path.join(__dirname, 'fixtures');

interface GoldenFixture {
  name: string;
  description: string;
  input: {
    user_id: string;
    target_date: string;
    tz_offset_min: number;
    telemetry: HealthTelemetryRow[];
  };
  expected: {
    steps: number | null;
    active_kcal: number | null;
    sleep_asleep_s: number | null;
    sleep_score: number | null;
    stress_avg: number | null;
    rhr: number | null;
    hrv_sdnn: number | null;
    primary_sleep_device: string | null;
    sleep_quality_rating: string | null;
    nap_count: number;
  };
}

function makeTelemetry(
  id: string,
  userId: string,
  type: string,
  value: number,
  unit: string,
  startTime: string,
  endTime?: string,
  sourceDevice?: string,
  semantics?: string
): HealthTelemetryRow {
  return {
    id,
    user_id: userId,
    type,
    value,
    unit,
    start_time: startTime,
    end_time: endTime || startTime,
    source_device: sourceDevice || 'Unknown',
    semantics
  };
}

const fixtures: GoldenFixture[] = [];
const userId = '00000000-0000-0000-0000-000000000001';

// ========================================================
// Fixture 1: Dual Tracker Night (Apple Watch + Oura Ring)
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 180; // UTC+3
  const telem: HealthTelemetryRow[] = [];

  // Oura Ring sleep stages (23:00 local to 07:00 local) -> 20:00 UTC to 04:00 UTC
  // 8 hours = 480 mins. Deep: 90m, REM: 100m, Light: 250m, Awake: 40m. Total asleep: 440m = 26400s
  telem.push(makeTelemetry('o1', userId, 'sleep_stage_awake', 15, 'min', '2026-10-04T20:00:00Z', '2026-10-04T20:15:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('o2', userId, 'sleep_stage_light', 45, 'min', '2026-10-04T20:15:00Z', '2026-10-04T21:00:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('o3', userId, 'sleep_stage_deep', 90, 'min', '2026-10-04T21:00:00Z', '2026-10-04T22:30:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('o4', userId, 'sleep_stage_light', 60, 'min', '2026-10-04T22:30:00Z', '2026-10-04T23:30:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('o5', userId, 'sleep_stage_rem', 100, 'min', '2026-10-04T23:30:00Z', '2026-10-05T01:10:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('o6', userId, 'sleep_stage_awake', 25, 'min', '2026-10-05T01:10:00Z', '2026-10-05T01:35:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('o7', userId, 'sleep_stage_light', 145, 'min', '2026-10-05T01:35:00Z', '2026-10-05T04:00:00Z', 'Oura Ring Gen3'));

  // Apple Watch overlapping sleep (lower priority 80 vs 100)
  telem.push(makeTelemetry('aw_s1', userId, 'sleep_stage_core', 300, 'min', '2026-10-04T20:30:00Z', '2026-10-05T01:30:00Z', 'Apple Watch Series 10'));

  // Daytime Steps from Apple Watch (Interval slices on 2026-10-05 local: 07:00 to 20:00 local = 04:00 to 17:00 UTC)
  telem.push(makeTelemetry('step1', userId, 'steps', 1200, 'count', '2026-10-05T05:00:00Z', '2026-10-05T05:59:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('step2', userId, 'steps', 3500, 'count', '2026-10-05T08:00:00Z', '2026-10-05T08:59:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('step3', userId, 'steps', 2800, 'count', '2026-10-05T11:00:00Z', '2026-10-05T11:59:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('step4', userId, 'steps', 3000, 'count', '2026-10-05T14:00:00Z', '2026-10-05T14:59:00Z', 'Apple Watch Series 10'));

  // Heart Rate samples & Vitals
  telem.push(makeTelemetry('hr1', userId, 'heart_rate', 54, 'bpm', '2026-10-05T02:00:00Z', '2026-10-05T02:00:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('hr2', userId, 'heart_rate', 72, 'bpm', '2026-10-05T06:00:00Z', '2026-10-05T06:00:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('hr3', userId, 'heart_rate', 135, 'bpm', '2026-10-05T14:30:00Z', '2026-10-05T14:30:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('rhr1', userId, 'resting_heart_rate', 52, 'bpm', '2026-10-05T04:30:00Z', '2026-10-05T04:30:00Z', 'Oura Ring Gen3'));
  telem.push(makeTelemetry('hrv1', userId, 'hrv_sdnn', 58, 'ms', '2026-10-05T04:30:00Z', '2026-10-05T04:30:00Z', 'Oura Ring Gen3'));

  fixtures.push({
    name: 'case_01_apple_watch_plus_oura',
    description: 'Multi-wearable nocturnal sleep: Oura Ring takes priority over Apple Watch, with micro-stage clipping and HRV stress analysis',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: 10500,
      active_kcal: 441.0,
      sleep_asleep_s: 26400,
      sleep_score: 91,
      stress_avg: 19,
      rhr: 52,
      hrv_sdnn: 58.0,
      primary_sleep_device: 'Oura Ring Gen3',
      sleep_quality_rating: 'Optimal',
      nap_count: 0
    }
  });
}

// ========================================================
// Fixture 2: Zepp OS Cumulative Steps
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 120; // UTC+2
  const telem: HealthTelemetryRow[] = [];

  // Cumulative steps increasing over the day:
  // 08:00 local (06:00 UTC): 1,500
  // 12:00 local (10:00 UTC): 4,800
  // 16:00 local (14:00 UTC): 8,200
  // 21:00 local (19:00 UTC): 12,350
  telem.push(makeTelemetry('z_step1', userId, 'steps', 1500, 'count', '2026-10-05T06:00:00Z', '2026-10-05T06:00:00Z', 'Amazfit Balance', 'cumulative_daily'));
  telem.push(makeTelemetry('z_step2', userId, 'steps', 4800, 'count', '2026-10-05T10:00:00Z', '2026-10-05T10:00:00Z', 'Amazfit Balance', 'cumulative_daily'));
  telem.push(makeTelemetry('z_step3', userId, 'steps', 8200, 'count', '2026-10-05T14:00:00Z', '2026-10-05T14:00:00Z', 'Amazfit Balance', 'cumulative_daily'));
  telem.push(makeTelemetry('z_step4', userId, 'steps', 12350, 'count', '2026-10-05T19:00:00Z', '2026-10-05T19:00:00Z', 'Amazfit Balance', 'cumulative_daily'));

  // Active calories cumulative
  telem.push(makeTelemetry('z_cal', userId, 'active_energy', 580, 'kcal', '2026-10-05T19:00:00Z', '2026-10-05T19:00:00Z', 'Amazfit Balance', 'cumulative_daily'));

  // Heart rate samples
  telem.push(makeTelemetry('z_hr1', userId, 'heart_rate', 65, 'bpm', '2026-10-05T08:00:00Z', '2026-10-05T08:00:00Z', 'Amazfit Balance'));
  telem.push(makeTelemetry('z_hr2', userId, 'heart_rate', 85, 'bpm', '2026-10-05T12:00:00Z', '2026-10-05T12:00:00Z', 'Amazfit Balance'));
  telem.push(makeTelemetry('z_rhr', userId, 'resting_heart_rate', 59, 'bpm', '2026-10-05T04:00:00Z', '2026-10-05T04:00:00Z', 'Amazfit Balance'));

  fixtures.push({
    name: 'case_02_zepp_cumulative_steps',
    description: 'Zepp OS / Amazfit cumulative daily step ingestion with hourly deltas',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: 12350,
      active_kcal: 580.0,
      sleep_asleep_s: null,
      sleep_score: null,
      stress_avg: 48,
      rhr: 59,
      hrv_sdnn: null,
      primary_sleep_device: null,
      sleep_quality_rating: null,
      nap_count: 0
    }
  });
}

// ========================================================
// Fixture 3: Android Health Connect (Samsung Health)
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 0; // UTC
  const telem: HealthTelemetryRow[] = [];

  // Sleep stages (00:00 to 07:00 UTC)
  // Deep: 60m (3600s), REM: 90m (5400s), Light: 240m (14400s), Awake: 30m (1800s). Asleep: 390m = 23400s
  telem.push(makeTelemetry('sh_s1', userId, 'sleep_stage_deep', 3600, 'sec', '2026-10-05T00:00:00Z', '2026-10-05T01:00:00Z', 'Samsung Health'));
  telem.push(makeTelemetry('sh_s2', userId, 'sleep_stage_light', 7200, 'sec', '2026-10-05T01:00:00Z', '2026-10-05T03:00:00Z', 'Samsung Health'));
  telem.push(makeTelemetry('sh_s3', userId, 'sleep_stage_rem', 5400, 'sec', '2026-10-05T03:00:00Z', '2026-10-05T04:30:00Z', 'Samsung Health'));
  telem.push(makeTelemetry('sh_s4', userId, 'sleep_stage_awake', 1800, 'sec', '2026-10-05T04:30:00Z', '2026-10-05T05:00:00Z', 'Samsung Health'));
  telem.push(makeTelemetry('sh_s5', userId, 'sleep_stage_light', 7200, 'sec', '2026-10-05T05:00:00Z', '2026-10-05T07:00:00Z', 'Samsung Health'));

  // Steps (explicit interval slices)
  telem.push(makeTelemetry('sh_step1', userId, 'steps', 4200, 'count', '2026-10-05T08:00:00Z', '2026-10-05T09:00:00Z', 'Samsung Health', 'interval_delta'));
  telem.push(makeTelemetry('sh_step2', userId, 'steps', 4600, 'count', '2026-10-05T13:00:00Z', '2026-10-05T14:00:00Z', 'Samsung Health', 'interval_delta'));

  // SpO2 and Weight
  telem.push(makeTelemetry('sh_spo2', userId, 'oxygen_saturation', 98.2, '%', '2026-10-05T06:00:00Z', '2026-10-05T06:00:00Z', 'Samsung Health'));
  telem.push(makeTelemetry('sh_w', userId, 'weight', 77.5, 'kg', '2026-10-05T07:30:00Z', '2026-10-05T07:30:00Z', 'Samsung Health'));

  fixtures.push({
    name: 'case_03_health_connect_samsung',
    description: 'Android Health Connect Samsung Health data ingestion with sleep architecture and biometrics',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: 8800,
      active_kcal: 369.6,
      sleep_asleep_s: 23400,
      sleep_score: 83,
      stress_avg: null,
      rhr: null,
      hrv_sdnn: null,
      primary_sleep_device: 'Samsung Health',
      sleep_quality_rating: 'Good',
      nap_count: 0
    }
  });
}

// ========================================================
// Fixture 4: Nocturnal Sleep + Daytime Nap
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 180; // UTC+3
  const telem: HealthTelemetryRow[] = [];

  // Nocturnal sleep (23:30 local to 07:00 local) -> 20:30 UTC to 04:00 UTC
  // Deep: 75m, REM: 80m, Light: 270m, Awake: 25m. Asleep: 425m = 25500s
  telem.push(makeTelemetry('ns1', userId, 'sleep_stage_deep', 75, 'min', '2026-10-04T20:30:00Z', '2026-10-04T21:45:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('ns2', userId, 'sleep_stage_light', 150, 'min', '2026-10-04T21:45:00Z', '2026-10-05T00:15:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('ns3', userId, 'sleep_stage_rem', 80, 'min', '2026-10-05T00:15:00Z', '2026-10-05T01:35:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('ns4', userId, 'sleep_stage_awake', 25, 'min', '2026-10-05T01:35:00Z', '2026-10-05T02:00:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('ns5', userId, 'sleep_stage_light', 120, 'min', '2026-10-05T02:00:00Z', '2026-10-05T04:00:00Z', 'Apple Watch Series 10'));

  // Daytime Nap: 14:15 local to 14:55 local (40 mins = 2400s) -> 11:15 UTC to 11:55 UTC
  telem.push(makeTelemetry('nap1', userId, 'sleep_nap', 40, 'min', '2026-10-05T11:15:00Z', '2026-10-05T11:55:00Z', 'Apple Watch Series 10'));

  // Steps
  telem.push(makeTelemetry('nap_step', userId, 'steps', 6500, 'count', '2026-10-05T08:00:00Z', '2026-10-05T09:00:00Z', 'Apple Watch Series 10'));

  fixtures.push({
    name: 'case_04_nocturnal_with_daytime_nap',
    description: 'Full nocturnal sleep session paired with a segregated daytime nap',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: 6500,
      active_kcal: 273.0,
      sleep_asleep_s: 25500,
      sleep_score: 90,
      stress_avg: null,
      rhr: null,
      hrv_sdnn: null,
      primary_sleep_device: 'Apple Watch Series 10',
      sleep_quality_rating: 'Optimal',
      nap_count: 1
    }
  });
}

// ========================================================
// Fixture 5: Fragmented Sleep with Multiple Awakenings
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 180; // UTC+3
  const telem: HealthTelemetryRow[] = [];

  // Fragmented sleep: 6 awakenings, total 55m awake
  telem.push(makeTelemetry('f1', userId, 'sleep_stage_awake', 10, 'min', '2026-10-04T21:00:00Z', '2026-10-04T21:10:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f2', userId, 'sleep_stage_light', 40, 'min', '2026-10-04T21:10:00Z', '2026-10-04T21:50:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f3', userId, 'sleep_stage_awake', 10, 'min', '2026-10-04T21:50:00Z', '2026-10-04T22:00:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f4', userId, 'sleep_stage_deep', 35, 'min', '2026-10-04T22:00:00Z', '2026-10-04T22:35:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f5', userId, 'sleep_stage_awake', 8, 'min', '2026-10-04T22:35:00Z', '2026-10-04T22:43:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f6', userId, 'sleep_stage_light', 50, 'min', '2026-10-04T22:43:00Z', '2026-10-04T23:33:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f7', userId, 'sleep_stage_awake', 12, 'min', '2026-10-04T23:33:00Z', '2026-10-04T23:45:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f8', userId, 'sleep_stage_rem', 40, 'min', '2026-10-04T23:45:00Z', '2026-10-05T00:25:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f9', userId, 'sleep_stage_awake', 5, 'min', '2026-10-05T00:25:00Z', '2026-10-05T00:30:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f10', userId, 'sleep_stage_light', 60, 'min', '2026-10-05T00:30:00Z', '2026-10-05T01:30:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f11', userId, 'sleep_stage_awake', 10, 'min', '2026-10-05T01:30:00Z', '2026-10-05T01:40:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('f12', userId, 'sleep_stage_light', 50, 'min', '2026-10-05T01:40:00Z', '2026-10-05T02:30:00Z', 'Apple Watch Series 10'));

  fixtures.push({
    name: 'case_05_fragmented_sleep',
    description: 'Fragmented sleep with 6 awakenings applying restfulness continuity penalties',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: null,
      active_kcal: null,
      sleep_asleep_s: 16500, // 275 mins = 4.58h
      sleep_score: 45,
      stress_avg: null,
      rhr: null,
      hrv_sdnn: null,
      primary_sleep_device: 'Apple Watch Series 10',
      sleep_quality_rating: 'Restless',
      nap_count: 0
    }
  });
}

// ========================================================
// Fixture 6: Empty Day (Honest Zero Data)
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 180;
  fixtures.push({
    name: 'case_06_empty_day_zero_data',
    description: 'Empty day with no telemetry records; verifies honest missing data representation with no synthetic fallbacks',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: [] },
    expected: {
      steps: null,
      active_kcal: null,
      sleep_asleep_s: null,
      sleep_score: null,
      stress_avg: null,
      rhr: null,
      hrv_sdnn: null,
      primary_sleep_device: null,
      sleep_quality_rating: null,
      nap_count: 0
    }
  });
}

// ========================================================
// Fixture 7: High Stress Sedentary Day
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 180; // UTC+3
  const telem: HealthTelemetryRow[] = [];

  // Low steps (< 300 steps per hour)
  telem.push(makeTelemetry('s_st1', userId, 'steps', 120, 'count', '2026-10-05T07:00:00Z', '2026-10-05T07:30:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('s_st2', userId, 'steps', 95, 'count', '2026-10-05T10:00:00Z', '2026-10-05T10:30:00Z', 'Apple Watch Series 10'));

  // Elevated sedentary heart rate (92 bpm, baseline RHR = 60 bpm)
  telem.push(makeTelemetry('s_hr1', userId, 'heart_rate', 92, 'bpm', '2026-10-05T07:00:00Z', '2026-10-05T07:00:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('s_hr2', userId, 'heart_rate', 94, 'bpm', '2026-10-05T10:00:00Z', '2026-10-05T10:00:00Z', 'Apple Watch Series 10'));
  telem.push(makeTelemetry('s_rhr', userId, 'resting_heart_rate', 60, 'bpm', '2026-10-05T04:00:00Z', '2026-10-05T04:00:00Z', 'Apple Watch Series 10'));

  // Severely depressed HRV (20 ms vs baseline 45 ms)
  telem.push(makeTelemetry('s_hrv', userId, 'hrv_sdnn', 20, 'ms', '2026-10-05T04:00:00Z', '2026-10-05T04:00:00Z', 'Apple Watch Series 10'));

  fixtures.push({
    name: 'case_07_high_stress_sedentary_day',
    description: 'Depressed HRV with elevated sedentary heart rate triggering acute sympathetic dominance (High Stress / Overheated Monkey)',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: 215,
      active_kcal: 9.0,
      sleep_asleep_s: null,
      sleep_score: null,
      stress_avg: 80,
      rhr: 60,
      hrv_sdnn: 20.0,
      primary_sleep_device: null,
      sleep_quality_rating: null,
      nap_count: 0
    }
  });
}

// ========================================================
// Fixture 8: Multi-Device Watch on Charger
// ========================================================
{
  const targetDate = '2026-10-05';
  const tzOffsetMin = 180;
  const telem: HealthTelemetryRow[] = [];

  // Morning: Apple Watch worn (3,800 steps)
  telem.push(makeTelemetry('md_w1', userId, 'steps', 3800, 'count', '2026-10-05T06:00:00Z', '2026-10-05T07:00:00Z', 'Apple Watch Series 10'));

  // Afternoon: Watch on charger, Phone carried (iPhone HealthKit: 4,600 steps)
  telem.push(makeTelemetry('md_p1', userId, 'steps', 4600, 'count', '2026-10-05T12:00:00Z', '2026-10-05T13:00:00Z', 'iPhone HealthKit'));

  fixtures.push({
    name: 'case_08_multi_device_watch_on_charger',
    description: 'Multi-device step aggregation avoiding duplicate summing between phone and watch',
    input: { user_id: userId, target_date: targetDate, tz_offset_min: tzOffsetMin, telemetry: telem },
    expected: {
      steps: 3800, // Wearable prioritized over phone
      active_kcal: 159.6,
      sleep_asleep_s: null,
      sleep_score: null,
      stress_avg: null,
      rhr: null,
      hrv_sdnn: null,
      primary_sleep_device: null,
      sleep_quality_rating: null,
      nap_count: 0
    }
  });
}

// Ensure directory exists
if (!fs.existsSync(FIXTURES_DIR)) {
  fs.mkdirSync(FIXTURES_DIR, { recursive: true });
}

// Write fixtures and run verification against TypeScript canonical engine
console.log(`Writing and testing ${fixtures.length} Golden Fixtures...`);
let allPassed = true;

for (const fix of fixtures) {
  const filePath = path.join(FIXTURES_DIR, `${fix.name}.json`);
  fs.writeFileSync(filePath, JSON.stringify(fix, null, 2), 'utf8');

  // Run TS Canonical Engine
  const summary = computeDailyHealthSummary({
    userId: fix.input.user_id,
    targetDate: fix.input.target_date,
    telemetry: fix.input.telemetry,
    tzOffsetMin: fix.input.tz_offset_min
  });

  const actualSteps = summary.steps;
  const actualKcal = summary.active_kcal;
  const actualSleepS = summary.sleep_asleep_s;
  const actualScore = summary.sleep_score;
  const actualStress = summary.stress_avg;
  const actualRhr = summary.rhr;
  const actualHrv = summary.hrv_sdnn;
  const actualDevice = summary.summary.sleep.primary_session?.source_device || null;
  const actualQuality = summary.summary.sleep.primary_session?.quality_rating || null;
  const actualNaps = summary.summary.sleep.naps.length;

  const matchSteps = actualSteps === fix.expected.steps;
  const matchKcal = actualKcal === fix.expected.active_kcal;
  const matchSleepS = actualSleepS === fix.expected.sleep_asleep_s;
  const matchScore = actualScore === fix.expected.sleep_score;
  const matchStress = actualStress === fix.expected.stress_avg;
  const matchRhr = actualRhr === fix.expected.rhr;
  const matchHrv = actualHrv === fix.expected.hrv_sdnn;
  const matchDevice = actualDevice === fix.expected.primary_sleep_device;
  const matchQuality = actualQuality === fix.expected.sleep_quality_rating;
  const matchNaps = actualNaps === fix.expected.nap_count;

  const passed =
    matchSteps &&
    matchKcal &&
    matchSleepS &&
    matchScore &&
    matchStress &&
    matchRhr &&
    matchHrv &&
    matchDevice &&
    matchQuality &&
    matchNaps;

  if (passed) {
    console.log(`  ✅ [PASS] ${fix.name}`);
  } else {
    allPassed = false;
    console.error(`  ❌ [FAIL] ${fix.name}:`);
    if (!matchSteps) console.error(`     steps: expected ${fix.expected.steps}, got ${actualSteps}`);
    if (!matchKcal) console.error(`     active_kcal: expected ${fix.expected.active_kcal}, got ${actualKcal}`);
    if (!matchSleepS) console.error(`     sleep_asleep_s: expected ${fix.expected.sleep_asleep_s}, got ${actualSleepS}`);
    if (!matchScore) console.error(`     sleep_score: expected ${fix.expected.sleep_score}, got ${actualScore}`);
    if (!matchStress) console.error(`     stress_avg: expected ${fix.expected.stress_avg}, got ${actualStress}`);
    if (!matchRhr) console.error(`     rhr: expected ${fix.expected.rhr}, got ${actualRhr}`);
    if (!matchHrv) console.error(`     hrv_sdnn: expected ${fix.expected.hrv_sdnn}, got ${actualHrv}`);
    if (!matchDevice) console.error(`     device: expected ${fix.expected.primary_sleep_device}, got ${actualDevice}`);
    if (!matchQuality) console.error(`     quality: expected ${fix.expected.sleep_quality_rating}, got ${actualQuality}`);
    if (!matchNaps) console.error(`     naps: expected ${fix.expected.nap_count}, got ${actualNaps}`);
  }
}

if (!allPassed) {
  process.exit(1);
} else {
  console.log(`\n🎉 All ${fixtures.length} Golden Fixtures verified successfully with 0 errors!`);
}
