// Canonical Health & Vitals Engine v1.0
// Pure deterministic math matching Swift DailyCore & Android core-health
// Compatible with Node.js and Deno

import type {
  HealthTelemetryRow,
  SleepStageType,
  SleepStageRecord,
  SleepSession,
  NapSession,
  SleepRecoveryVerdict,
  SleepActionableTip,
  SleepAIContext,
  SleepGuidance,
  HourlyStepBucket,
  ActivitySummary,
  HeartRateZoneName,
  IntradayHeartRatePoint,
  CardiovascularSummary,
  StressLevelName,
  MonkeyMoodName,
  IntradayStressPoint,
  StressSummary,
  VitalSummaryItem,
  DailyHealthSummaryPayload,
  HealthDailySummaryRow,
  LeanDailyVitalsRow,
  LeanSleepSessionRow,
  LeanIntradayHrRow,
  LeanHealthSourceRow
} from './types.ts';

export interface EngineInput {
  userId: string;
  targetDate: string; // YYYY-MM-DD
  telemetry: HealthTelemetryRow[];
  tzOffsetMin?: number;
  preferredDevice?: string;
  baselineHrvMs?: number;
  baselineRhrBpm?: number;
}

// ==========================================
// 1. Time & Timezone Helper Utilities
// ==========================================

export function parseUtcDate(isoString: string): Date {
  return new Date(isoString);
}

export function toEpochMs(d: Date | string): number {
  return typeof d === 'string' ? new Date(d).getTime() : d.getTime();
}

export function getLocalComponents(date: Date, tzOffsetMin: number): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  dateString: string;
} {
  // Shift UTC time by tzOffsetMin to get local time representation in UTC coordinates
  const shiftedMs = date.getTime() + tzOffsetMin * 60 * 1000;
  const shifted = new Date(shiftedMs);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const day = shifted.getUTCDate();
  const hour = shifted.getUTCHours();
  const minute = shifted.getUTCMinutes();
  const second = shifted.getUTCSeconds();
  const dateString = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return { year, month, day, hour, minute, second, dateString };
}

export function isSameLocalDate(date: Date, targetDateStr: string, tzOffsetMin: number): boolean {
  return getLocalComponents(date, tzOffsetMin).dateString === targetDateStr;
}

export function getLocalHour(date: Date, tzOffsetMin: number): number {
  return getLocalComponents(date, tzOffsetMin).hour;
}

export function getLocalMidnightUtc(targetDateStr: string, tzOffsetMin: number): Date {
  const [y, m, d] = targetDateStr.split('-').map(Number);
  const utcMidnightMs = Date.UTC(y, m - 1, d, 0, 0, 0, 0);
  return new Date(utcMidnightMs - tzOffsetMin * 60 * 1000);
}

// ==========================================
// 2. Sleep Clustering & Scoring Engine
// ==========================================

export function normalizeMetricType(type: string): string {
  return type
    .trim()
    .toLowerCase()
    .replace(/[_\s-]/g, '');
}

export function isSleepRecord(row: HealthTelemetryRow): boolean {
  const norm = normalizeMetricType(row.type);
  return (
    norm.startsWith('sleep') ||
    norm === 'nap' ||
    norm === 'napduration' ||
    norm === 'sleepnap'
  );
}

export function isSleepStageRecord(row: HealthTelemetryRow): boolean {
  const norm = normalizeMetricType(row.type);
  return (
    norm.includes('deep') ||
    norm.includes('rem') ||
    norm.includes('light') ||
    norm.includes('core') ||
    norm.includes('awake')
  );
}

export function isNapRecord(row: HealthTelemetryRow): boolean {
  const norm = normalizeMetricType(row.type);
  return norm === 'sleepnap' || norm === 'napduration' || norm === 'nap';
}

export function mapSleepStageType(type: string): SleepStageType {
  const norm = normalizeMetricType(type);
  if (norm.includes('deep')) return 'Deep';
  if (norm.includes('rem')) return 'REM';
  if (norm.includes('light') || norm.includes('core')) return 'Light';
  if (norm.includes('awake')) return 'Awake';
  return 'Unknown';
}

export function getDeviceSleepPriority(deviceName: string | null): number {
  if (!deviceName) return 10;
  const lower = deviceName.toLowerCase();
  if (lower.includes('oura')) return 100;
  if (lower.includes('apple') || lower.includes('watch')) return 80;
  if (lower.includes('amazfit') || lower.includes('zepp') || lower.includes('balance')) return 70;
  if (lower.includes('oneplus') || lower.includes('wearos')) return 60;
  if (lower.includes('huawei') || lower.includes('harmony') || lower.includes('gt5')) return 50;
  if (lower.includes('healthkit') || lower.includes('health')) return 40;
  return 10;
}

export function clusterSleepTelemetry(
  records: HealthTelemetryRow[],
  targetDateStr: string,
  tzOffsetMin: number,
  preferredDevice?: string
): {
  primarySession: SleepSession | null;
  allSessions: SleepSession[];
  naps: NapSession[];
} {
  const targetMidnight = getLocalMidnightUtc(targetDateStr, tzOffsetMin);
  // Nocturnal window: D-1 18:00 to D 18:00 (i.e. -6h to +18h from D 00:00)
  const windowStartMs = targetMidnight.getTime() - 6 * 3600 * 1000;
  const windowEndMs = targetMidnight.getTime() + 18 * 3600 * 1000;

  const sleepRecords = records.filter(r => {
    if (!isSleepRecord(r)) return false;
    const s = toEpochMs(r.start_time);
    return s >= windowStartMs && s <= windowEndMs;
  });

  const allNocturnalSessions: SleepSession[] = [];
  const allNaps: NapSession[] = [];

  // Group by device
  const byDevice = new Map<string, HealthTelemetryRow[]>();
  for (const r of sleepRecords) {
    const dev = (r.source_device || 'Unknown').trim();
    if (!byDevice.has(dev)) byDevice.set(dev, []);
    byDevice.get(dev)!.push(r);
  }

  for (const [device, devRecords] of byDevice.entries()) {
    // 1. Explicit naps
    const explicitNaps = devRecords.filter(r => {
      if (!isNapRecord(r)) return false;
      const s = parseUtcDate(r.start_time);
      const e = r.end_time ? parseUtcDate(r.end_time) : s;
      const durSec = (e.getTime() - s.getTime()) / 1000;
      const startHour = getLocalHour(s, tzOffsetMin);
      const endHour = getLocalHour(e, tzOffsetMin);
      const isTargetDay = isSameLocalDate(s, targetDateStr, tzOffsetMin);
      return isTargetDay && startHour >= 9 && endHour <= 21 && durSec < 3.5 * 3600;
    });

    for (const n of explicitNaps) {
      const s = parseUtcDate(n.start_time);
      const e = n.end_time ? parseUtcDate(n.end_time) : s;
      const durSec = Math.max(0, (e.getTime() - s.getTime()) / 1000);
      allNaps.push({
        id: n.id,
        start_time: n.start_time,
        end_time: n.end_time || n.start_time,
        duration_seconds: durSec,
        source_device: device
      });
    }

    // 2. Non-nap sleep records
    const nonNap = devRecords.filter(r => !isNapRecord(r));
    const stageRecs = nonNap.filter(isSleepStageRecord);
    const aggRecs = nonNap.filter(r => !isSleepStageRecord(r));

    if (stageRecs.length > 0) {
      const clustered = clusterStages(stageRecs, targetDateStr, device, tzOffsetMin);
      for (const s of clustered) {
        if (s.is_nap) {
          allNaps.push({
            id: s.id,
            start_time: s.start_time,
            end_time: s.end_time,
            duration_seconds: s.duration_seconds,
            source_device: s.source_device
          });
        } else {
          allNocturnalSessions.push(s);
        }
      }
    } else if (aggRecs.length > 0) {
      const clusteredAgg = clusterAggregates(aggRecs, targetDateStr, device, tzOffsetMin);
      for (const s of clusteredAgg) {
        if (s.is_nap) {
          allNaps.push({
            id: s.id,
            start_time: s.start_time,
            end_time: s.end_time,
            duration_seconds: s.duration_seconds,
            source_device: s.source_device
          });
        } else {
          allNocturnalSessions.push(s);
        }
      }
    }
  }

  // 3. Select primary nocturnal session
  let eligible = allNocturnalSessions;
  if (preferredDevice && preferredDevice.trim().length > 0) {
    const prefLower = preferredDevice.toLowerCase();
    const filtered = allNocturnalSessions.filter(s => s.source_device.toLowerCase().includes(prefLower));
    if (filtered.length > 0) eligible = filtered;
  }

  eligible.sort((a, b) => {
    if (a.has_granular_hypnogram !== b.has_granular_hypnogram) {
      return a.has_granular_hypnogram ? -1 : 1;
    }
    const rankA = getDeviceSleepPriority(a.source_device);
    const rankB = getDeviceSleepPriority(b.source_device);
    if (rankA !== rankB) return rankB - rankA;
    return b.asleep_seconds - a.asleep_seconds;
  });

  const primarySession = eligible.length > 0 ? eligible[0] : null;

  // 4. Deduplicate and merge naps
  allNaps.sort((a, b) => toEpochMs(a.start_time) - toEpochMs(b.start_time));
  const uniqueNaps: NapSession[] = [];
  for (const nap of allNaps) {
    if (uniqueNaps.length > 0) {
      const last = uniqueNaps[uniqueNaps.length - 1];
      const lastStart = toEpochMs(last.start_time);
      const lastEnd = toEpochMs(last.end_time);
      const currStart = toEpochMs(nap.start_time);
      const currEnd = toEpochMs(nap.end_time);

      const overlapStart = Math.max(lastStart, currStart);
      const overlapEnd = Math.min(lastEnd, currEnd);
      const overlapSec = Math.max(0, (overlapEnd - overlapStart) / 1000);
      const minDurSec = Math.min(last.duration_seconds, nap.duration_seconds);

      const isSameDevice = last.source_device === nap.source_device;
      const isNearDuplicate =
        Math.abs(currStart - lastStart) < 15 * 60 * 1000 &&
        Math.abs(currEnd - lastEnd) < 15 * 60 * 1000;

      if (isNearDuplicate || (isSameDevice && (overlapSec > 0.4 * minDurSec || overlapSec > 600))) {
        const mergedStart = Math.min(lastStart, currStart);
        const mergedEnd = Math.max(lastEnd, currEnd);
        const mergedDur = Math.max(last.duration_seconds, nap.duration_seconds, (mergedEnd - mergedStart) / 1000);
        uniqueNaps[uniqueNaps.length - 1] = {
          id: last.id,
          start_time: new Date(mergedStart).toISOString(),
          end_time: new Date(mergedEnd).toISOString(),
          duration_seconds: mergedDur,
          source_device: last.source_device
        };
        continue;
      }
    }
    uniqueNaps.push(nap);
  }

  return {
    primarySession,
    allSessions: allNocturnalSessions,
    naps: uniqueNaps
  };
}

function clusterStages(
  stages: HealthTelemetryRow[],
  targetDateStr: string,
  sourceDevice: string,
  tzOffsetMin: number
): SleepSession[] {
  stages.sort((a, b) => toEpochMs(a.start_time) - toEpochMs(b.start_time));
  if (stages.length === 0) return [];

  const sessions: SleepSession[] = [];
  let currentCluster: HealthTelemetryRow[] = [stages[0]];

  for (let i = 1; i < stages.length; i++) {
    const prev = currentCluster[currentCluster.length - 1];
    const curr = stages[i];

    const prevEnd = prev.end_time ? toEpochMs(prev.end_time) : toEpochMs(prev.start_time);
    const currStart = toEpochMs(curr.start_time);
    const gapMinutes = (currStart - prevEnd) / (60 * 1000);

    if (gapMinutes < 45) {
      currentCluster.push(curr);
    } else {
      const s = buildSessionFromCluster(currentCluster, targetDateStr, sourceDevice, tzOffsetMin);
      if (s) sessions.push(s);
      currentCluster = [curr];
    }
  }

  const lastS = buildSessionFromCluster(currentCluster, targetDateStr, sourceDevice, tzOffsetMin);
  if (lastS) sessions.push(lastS);

  return sessions;
}

function buildSessionFromCluster(
  cluster: HealthTelemetryRow[],
  targetDateStr: string,
  sourceDevice: string,
  tzOffsetMin: number
): SleepSession | null {
  const starts = cluster.map(r => toEpochMs(r.start_time));
  const ends = cluster.map(r => (r.end_time ? toEpochMs(r.end_time) : toEpochMs(r.start_time)));
  const minStartMs = Math.min(...starts);
  const maxEndMs = Math.max(...ends);

  const spanSec = Math.max(0, (maxEndMs - minStartMs) / 1000);
  if (spanSec < 600) return null; // Ignore < 10 mins noise

  const normalizedStages = normalizeAndClipStages(cluster, sourceDevice);
  if (normalizedStages.length === 0) return null;

  const startDate = new Date(minStartMs);
  const endDate = new Date(maxEndMs);

  const startHour = getLocalHour(startDate, tzOffsetMin);
  const endHour = getLocalHour(endDate, tzOffsetMin);
  const isSameDay = isSameLocalDate(startDate, targetDateStr, tzOffsetMin);
  const isNap = spanSec < 3.5 * 3600 && isSameDay && startHour >= 9 && endHour <= 20;

  return createSleepSessionObject({
    id: cluster[0].id,
    startTime: startDate.toISOString(),
    endTime: endDate.toISOString(),
    isNap,
    sourceDevice,
    hasGranularHypnogram: true,
    stages: normalizedStages
  });
}

function clusterAggregates(
  records: HealthTelemetryRow[],
  targetDateStr: string,
  sourceDevice: string,
  tzOffsetMin: number
): SleepSession[] {
  records.sort((a, b) => toEpochMs(a.start_time) - toEpochMs(b.start_time));
  if (records.length === 0) return [];

  const sessions: SleepSession[] = [];
  let currentCluster: HealthTelemetryRow[] = [records[0]];

  for (let i = 1; i < records.length; i++) {
    const prev = currentCluster[currentCluster.length - 1];
    const curr = records[i];

    const prevEnd = prev.end_time ? toEpochMs(prev.end_time) : toEpochMs(prev.start_time);
    const currStart = toEpochMs(curr.start_time);
    const gapMinutes = (currStart - prevEnd) / (60 * 1000);

    if (gapMinutes < 45) {
      currentCluster.push(curr);
    } else {
      const s = buildAggregateSession(currentCluster, targetDateStr, sourceDevice, tzOffsetMin);
      if (s) sessions.push(s);
      currentCluster = [curr];
    }
  }

  const lastS = buildAggregateSession(currentCluster, targetDateStr, sourceDevice, tzOffsetMin);
  if (lastS) sessions.push(lastS);

  return sessions;
}

function buildAggregateSession(
  cluster: HealthTelemetryRow[],
  targetDateStr: string,
  sourceDevice: string,
  tzOffsetMin: number
): SleepSession | null {
  const starts = cluster.map(r => toEpochMs(r.start_time));
  const ends = cluster.map(r => (r.end_time ? toEpochMs(r.end_time) : toEpochMs(r.start_time)));
  const minStartMs = Math.min(...starts);
  const maxEndMs = Math.max(...ends);

  const spanSec = Math.max(0, (maxEndMs - minStartMs) / 1000);
  if (spanSec < 600) return null;

  const startDate = new Date(minStartMs);
  const endDate = new Date(maxEndMs);

  const startHour = getLocalHour(startDate, tzOffsetMin);
  const endHour = getLocalHour(endDate, tzOffsetMin);
  const isSameDay = isSameLocalDate(startDate, targetDateStr, tzOffsetMin);
  const isNap = spanSec < 3.5 * 3600 && isSameDay && startHour >= 9 && endHour <= 20;

  return createSleepSessionObject({
    id: cluster[0].id,
    startTime: startDate.toISOString(),
    endTime: endDate.toISOString(),
    isNap,
    sourceDevice,
    hasGranularHypnogram: false,
    stages: []
  });
}

function normalizeAndClipStages(
  rawRecords: HealthTelemetryRow[],
  sourceDevice: string
): SleepStageRecord[] {
  const sorted = [...rawRecords].sort((a, b) => {
    const sa = toEpochMs(a.start_time);
    const sb = toEpochMs(b.start_time);
    if (sa !== sb) return sa - sb;
    const ea = a.end_time ? toEpochMs(a.end_time) : sa;
    const eb = b.end_time ? toEpochMs(b.end_time) : sb;
    return ea - eb;
  });

  const normalized: SleepStageRecord[] = [];
  let lastEndMs: number | null = null;

  for (const r of sorted) {
    let startMs = toEpochMs(r.start_time);
    const endMs = r.end_time ? toEpochMs(r.end_time) : startMs;
    if (endMs <= startMs) continue;

    if (lastEndMs !== null) {
      if (startMs < lastEndMs) {
        if (endMs <= lastEndMs) {
          // Completely subsumed
          continue;
        } else {
          // Partially overlapping: clip start to lastEndMs
          startMs = lastEndMs;
        }
      }
    }

    const durSec = Math.max(0, (endMs - startMs) / 1000);
    if (durSec < 10) continue; // Ignore sub-10s artifacts

    normalized.push({
      id: r.id,
      stage_type: mapSleepStageType(r.type),
      start_time: new Date(startMs).toISOString(),
      end_time: new Date(endMs).toISOString(),
      duration_seconds: durSec,
      source_device: sourceDevice
    });

    lastEndMs = endMs;
  }

  return normalized;
}

export function createSleepSessionObject(params: {
  id: string;
  startTime: string;
  endTime: string;
  isNap: boolean;
  sourceDevice: string;
  hasGranularHypnogram: boolean;
  stages: SleepStageRecord[];
}): SleepSession {
  const { id, startTime, endTime, isNap, sourceDevice, hasGranularHypnogram, stages } = params;

  let deepSec = 0;
  let remSec = 0;
  let lightSec = 0;
  let awakeSec = 0;

  for (const st of stages) {
    if (st.stage_type === 'Deep') deepSec += st.duration_seconds;
    else if (st.stage_type === 'REM') remSec += st.duration_seconds;
    else if (st.stage_type === 'Light') lightSec += st.duration_seconds;
    else if (st.stage_type === 'Awake') awakeSec += st.duration_seconds;
  }

  const spanSec = Math.max(0, (toEpochMs(endTime) - toEpochMs(startTime)) / 1000);
  const totalStagesSec = deepSec + remSec + lightSec + awakeSec;

  const durationSec =
    totalStagesSec > 0 && spanSec > totalStagesSec * 1.35
      ? totalStagesSec
      : Math.max(spanSec, totalStagesSec);

  const asleepStagesSec = deepSec + remSec + lightSec;
  const asleepSec = asleepStagesSec > 0 ? asleepStagesSec : Math.max(0, durationSec - awakeSec);

  const awakeCount = stages.filter(st => st.stage_type === 'Awake').length;

  const deepPct = asleepSec > 0 ? Math.round((deepSec / asleepSec) * 100) : 0;
  const remPct = asleepSec > 0 ? Math.round((remSec / asleepSec) * 100) : 0;
  const lightPct = asleepSec > 0 ? Math.round((lightSec / asleepSec) * 100) : 0;
  const awakePct = durationSec > 0 ? Math.round((awakeSec / durationSec) * 100) : 0;
  const restorativePct = deepPct + remPct;

  const efficiencyPct =
    durationSec > 0 ? Math.min(100, Math.max(10, Math.round((asleepSec / durationSec) * 100))) : 85;

  // Calibrated 4-pillar score
  const score = calculateClinicalSleepScore({
    asleepSeconds: asleepSec,
    durationSeconds: durationSec,
    efficiencyPercent: efficiencyPct,
    deepPercent: deepPct,
    remPercent: remPct,
    awakeCount,
    awakeSeconds: awakeSec
  });

  const qualityRating = getSleepQualityRating(score);

  return {
    id,
    start_time: startTime,
    end_time: endTime,
    is_nap: isNap,
    source_device: sourceDevice,
    has_granular_hypnogram: hasGranularHypnogram,
    stages,
    asleep_seconds: Math.round(asleepSec),
    duration_seconds: Math.round(durationSec),
    deep_seconds: Math.round(deepSec),
    rem_seconds: Math.round(remSec),
    light_seconds: Math.round(lightSec),
    awake_seconds: Math.round(awakeSec),
    deep_percent: deepPct,
    rem_percent: remPct,
    light_percent: lightPct,
    awake_percent: awakePct,
    restorative_percent: restorativePct,
    efficiency_percent: efficiencyPct,
    awake_count: awakeCount,
    sleep_score: score,
    quality_rating: qualityRating
  };
}

export function calculateClinicalSleepScore(params: {
  asleepSeconds: number;
  durationSeconds: number;
  efficiencyPercent: number;
  deepPercent: number;
  remPercent: number;
  awakeCount: number;
  awakeSeconds: number;
}): number {
  const {
    asleepSeconds,
    efficiencyPercent,
    deepPercent,
    remPercent,
    awakeCount,
    awakeSeconds
  } = params;

  if (asleepSeconds <= 0) return 0;

  const asleepHours = asleepSeconds / 3600.0;

  // 1. Duration score (max 40 pts, benchmark 7.5h - 9.0h)
  let durationScore: number;
  if (asleepHours >= 7.5 && asleepHours <= 9.0) {
    durationScore = 38.0 + Math.min(((asleepHours - 7.5) / 1.5) * 2.0, 2.0);
  } else if (asleepHours > 9.0) {
    durationScore = Math.max(34.0, 40.0 - (asleepHours - 9.0) * 2.0);
  } else if (asleepHours >= 7.0) {
    durationScore = 34.0 + ((asleepHours - 7.0) / 0.5) * 4.0;
  } else if (asleepHours >= 6.0) {
    durationScore = 24.0 + (asleepHours - 6.0) * 10.0;
  } else if (asleepHours >= 5.0) {
    durationScore = 14.0 + (asleepHours - 5.0) * 10.0;
  } else {
    durationScore = Math.max(0.0, (asleepHours / 5.0) * 14.0);
  }

  // 2. Efficiency score (max 25 pts, clinical baseline >= 88%)
  const eff = efficiencyPercent;
  let effScore: number;
  if (eff >= 95.0) {
    effScore = 25.0;
  } else if (eff >= 90.0) {
    effScore = 21.0 + ((eff - 90.0) / 5.0) * 4.0;
  } else if (eff >= 85.0) {
    effScore = 16.0 + ((eff - 85.0) / 5.0) * 5.0;
  } else if (eff >= 80.0) {
    effScore = 10.0 + ((eff - 80.0) / 5.0) * 6.0;
  } else {
    effScore = Math.max(0.0, (eff / 80.0) * 10.0);
  }

  // 3. Restorative Architecture (max 25 pts: Deep up to 13, REM up to 12)
  let deepScore: number;
  const dp = deepPercent;
  if (dp >= 16.0) {
    deepScore = 11.0 + Math.min(((dp - 16.0) / 6.0) * 2.0, 2.0);
  } else if (dp >= 10.0) {
    deepScore = 6.0 + ((dp - 10.0) / 6.0) * 5.0;
  } else {
    deepScore = Math.max(0.0, (dp / 10.0) * 6.0);
  }

  let remScore: number;
  const rp = remPercent;
  if (rp >= 20.0) {
    remScore = 10.0 + Math.min(((rp - 20.0) / 5.0) * 2.0, 2.0);
  } else if (rp >= 14.0) {
    remScore = 5.0 + ((rp - 14.0) / 6.0) * 5.0;
  } else {
    remScore = Math.max(0.0, (rp / 14.0) * 5.0);
  }
  const qualScore = deepScore + remScore;

  // 4. Restfulness & Sleep Continuity (max 10 pts)
  let awakeCountPenalty: number;
  if (awakeCount <= 2) {
    awakeCountPenalty = 0.0;
  } else if (awakeCount <= 4) {
    awakeCountPenalty = 1.5;
  } else {
    awakeCountPenalty = Math.min(1.5 + (awakeCount - 4) * 0.75, 5.0);
  }

  const awakeMinutes = awakeSeconds / 60.0;
  let awakeDurationPenalty: number;
  if (awakeMinutes <= 25.0) {
    awakeDurationPenalty = 0.0;
  } else {
    awakeDurationPenalty = Math.min(((awakeMinutes - 25.0) / 10.0) * 1.0, 5.0);
  }

  const restfulnessScore = Math.max(1.0, 10.0 - awakeCountPenalty - awakeDurationPenalty);

  const total = Math.round(durationScore + effScore + qualScore + restfulnessScore);
  return Math.min(100, Math.max(0, total));
}

export function getSleepQualityRating(score: number): string {
  if (score >= 85) return 'Optimal';
  if (score >= 75) return 'Good';
  if (score >= 60) return 'Fair';
  if (score >= 1) return 'Restless';
  return 'No Data';
}

export function generateSleepGuidance(session: SleepSession | null, targetDateStr?: string): SleepGuidance | null {
  if (!session || session.asleep_seconds <= 0) return null;

  const score = session.sleep_score;
  const deepPct = session.deep_percent;
  const remPct = session.rem_percent;
  const effPct = session.efficiency_percent;
  const asleepHours = session.asleep_seconds / 3600.0;
  const awakeCount = session.awake_count;

  let status: 'Optimal' | 'Great' | 'Fair' | 'Deficit';
  let headline: string;
  let narrative: string;

  if (score >= 85 && effPct >= 88 && deepPct >= 15) {
    status = 'Optimal';
    headline = 'Fully Restored & Prime for High Performance';
    narrative = `Outstanding sleep architecture with ${deepPct}% deep sleep and ${remPct}% REM sleep. Cellular rejuvenation and cognitive recovery are fully primed.`;
  } else if (score >= 75 || (asleepHours >= 7.0 && effPct >= 85)) {
    status = 'Great';
    headline = 'Strong Recharging with Balanced Sleep Stages';
    narrative = `Solid overall rest of ${asleepHours.toFixed(1)} hours. Autonomic tone and muscular recovery are in healthy parameters.`;
  } else if (score >= 60 || asleepHours >= 6.0) {
    status = 'Fair';
    headline = 'Moderate Sleep Quality with Rejuvenation Potential';
    narrative = `Adequate rest was achieved, though efficiency (${effPct}%) or restorative stage proportions have room for optimization.`;
  } else {
    status = 'Deficit';
    headline = 'Significant Sleep Deficit Detected';
    narrative = `Rest fell below physiological baseline (${asleepHours.toFixed(1)}h). Prioritize early wind-down tonight to clear accumulated sleep debt.`;
  }

  const readinessScore = Math.min(100, Math.max(10, score + (effPct >= 90 ? 3 : -2)));
  const physicalRepair = deepPct >= 16 ? 'High' : deepPct >= 10 ? 'Adequate' : 'Low';
  const cognitiveRestore = remPct >= 20 ? 'High' : remPct >= 14 ? 'Adequate' : 'Low';
  const continuity = awakeCount <= 3 ? 'Continuous' : 'Fragmented';

  const verdictId = targetDateStr ? `sleep_verdict_${targetDateStr}` : `sleep_verdict_${session.id}`;

  const verdict: SleepRecoveryVerdict = {
    id: verdictId,
    status,
    headline,
    narrative,
    readiness_score: readinessScore,
    physical_repair_rating: physicalRepair,
    cognitive_restore_rating: cognitiveRestore,
    sleep_continuity_rating: continuity
  };

  const tips: SleepActionableTip[] = [
    {
      id: 'circadian_sunlight',
      category: 'circadian',
      title: 'Morning Photonic Reset',
      advice: 'View 10-15 minutes of direct sunlight within 60 minutes of waking.',
      scientific_rationale: 'Suppresses remaining melatonin and sets the circadian timer for nighttime sleep pressure.'
    },
    {
      id: 'bedroom_climate',
      category: 'environment',
      title: 'Thermoregulatory Drop',
      advice: 'Maintain bedroom ambient temperature between 18°C and 20°C (65-68°F).',
      scientific_rationale: 'Core body temperature must drop 1-2°F to initiate and sustain deep non-REM restorative sleep.'
    },
    {
      id: 'evening_nutrition',
      category: 'nutrition',
      title: 'Digestive Buffer Zone',
      advice: 'Finish last caloric intake at least 2.5 to 3 hours before sleep.',
      scientific_rationale: 'Late gastric motility keeps nocturnal resting heart rate elevated and suppresses growth hormone release.'
    },
    {
      id: 'wind_down_breath',
      category: 'windDown',
      title: 'Vagal Downregulation',
      advice: 'Practice 4-7-8 breathing or physiological sighs for 4 minutes before lights out.',
      scientific_rationale: 'Engages the parasympathetic vagus nerve, reducing autonomic arousal and sleep latency.'
    }
  ];

  const aiContext: SleepAIContext = {
    narrative_synthesis: `User logged ${asleepHours.toFixed(1)}h of total asleep time with sleep score ${score}/100. Deep: ${deepPct}%, REM: ${remPct}%, Efficiency: ${effPct}%. Physical repair is rated ${physicalRepair}, cognitive restore is ${cognitiveRestore}.`,
    suggested_prompts: [
      'How can I increase my deep sleep percentage tonight?',
      'Why did I wake up feeling sluggish despite 7 hours in bed?',
      'What evening routine best supports higher HRV during sleep?'
    ]
  };

  return { verdict, tips, ai_context: aiContext };
}

// ==========================================
// 3. Activity & Steps Engine
// ==========================================

export function isCumulativeDevice(device: string, records: HealthTelemetryRow[]): boolean {
  if (records.some(r => r.semantics === 'cumulative_daily')) return true;
  if (records.some(r => r.semantics === 'interval_delta')) return false;

  const lower = device.toLowerCase();
  if (
    lower.includes('zepp') ||
    lower.includes('amazfit') ||
    lower.includes('balance') ||
    lower.includes('huawei') ||
    lower.includes('harmony') ||
    lower.includes('gt5')
  ) {
    return true;
  }

  const nonZero = records.map(r => r.value ?? 0).filter(v => v > 0);
  if (nonZero.length >= 2) {
    let isIncreasing = true;
    for (let i = 1; i < nonZero.length; i++) {
      if (nonZero[i] < nonZero[i - 1]) {
        isIncreasing = false;
        break;
      }
    }
    const hasLarge = nonZero.some(v => v >= 500);
    // If records explicitly represent short hourly slices, they are intervals
    const hasShortIntervals = records.some(r => {
      if (!r.start_time || !r.end_time) return false;
      const dur = (toEpochMs(r.end_time) - toEpochMs(r.start_time)) / 1000;
      return dur > 0 && dur <= 3600;
    });
    if (isIncreasing && hasLarge && !hasShortIntervals) return true;
  }

  return false;
}

export function computeDailySteps(
  records: HealthTelemetryRow[],
  targetDateStr: string,
  tzOffsetMin: number,
  preferredDevice?: string
): ActivitySummary {
  const stepRecords = records.filter(r => {
    const norm = normalizeMetricType(r.type);
    if (norm !== 'steps' && norm !== 'stepcount') return false;
    const s = parseUtcDate(r.start_time);
    return isSameLocalDate(s, targetDateStr, tzOffsetMin);
  });

  // Group by device
  const byDevice = new Map<string, HealthTelemetryRow[]>();
  for (const r of stepRecords) {
    const dev = (r.source_device || 'Unknown').trim();
    if (!byDevice.has(dev)) byDevice.set(dev, []);
    byDevice.get(dev)!.push(r);
  }

  interface DeviceStepResult {
    device: string;
    total: number;
    hourly: Map<number, number>;
    isWearable: boolean;
  }

  const deviceResults: DeviceStepResult[] = [];

  for (const [device, devRecords] of byDevice.entries()) {
    const isWearable = isWearableDevice(device);

    const cumulative = isCumulativeDevice(device, devRecords);
    const hourly = new Map<number, number>();
    let total = 0;

    if (cumulative) {
      // Zepp OS / Amazfit: Cumulative daily total
      devRecords.sort((a, b) => toEpochMs(a.start_time) - toEpochMs(b.start_time));
      const maxVal = Math.max(0, ...devRecords.map(r => r.value ?? 0));
      total = Math.round(maxVal);

      let prevVal = 0;
      for (const r of devRecords) {
        const val = r.value ?? 0;
        if (val <= 0) continue;
        const delta = val >= prevVal ? val - prevVal : val;
        const s = parseUtcDate(r.start_time);
        const hour = getLocalHour(s, tzOffsetMin);
        hourly.set(hour, (hourly.get(hour) ?? 0) + Math.round(delta));
        prevVal = val;
      }
    } else {
      // HealthKit / Health Connect: Interval step slices
      devRecords.sort((a, b) => toEpochMs(a.start_time) - toEpochMs(b.start_time));
      const uniqueSlices: HealthTelemetryRow[] = [];
      for (const r of devRecords) {
        if (uniqueSlices.length > 0) {
          const last = uniqueSlices[uniqueSlices.length - 1];
          const lastStart = toEpochMs(last.start_time);
          const lastEnd = last.end_time ? toEpochMs(last.end_time) : lastStart;
          const currStart = toEpochMs(r.start_time);
          const currEnd = r.end_time ? toEpochMs(r.end_time) : currStart;

          if (Math.abs(currStart - lastStart) < 5000 && Math.abs(currEnd - lastEnd) < 5000) {
            continue; // Deduplicate overlapping interval slice
          }
        }
        uniqueSlices.push(r);
      }

      for (const r of uniqueSlices) {
        const val = Math.round(r.value ?? 0);
        const s = parseUtcDate(r.start_time);
        const hour = getLocalHour(s, tzOffsetMin);
        hourly.set(hour, (hourly.get(hour) ?? 0) + val);
      }
      total = Array.from(hourly.values()).reduce((a, b) => a + b, 0);
    }

    deviceResults.push({ device, total, hourly, isWearable });
  }

  // Choose primary device
  let chosen: DeviceStepResult | null = null;
  if (preferredDevice && preferredDevice.trim().length > 0) {
    const pref = preferredDevice.toLowerCase();
    chosen = deviceResults.find(d => d.device.toLowerCase().includes(pref)) || null;
  }

  if (!chosen) {
    const wearables = deviceResults.filter(d => d.isWearable && d.total > 0);
    if (wearables.length > 0) {
      wearables.sort((a, b) => b.total - a.total);
      chosen = wearables[0];
    } else if (deviceResults.length > 0) {
      deviceResults.sort((a, b) => b.total - a.total);
      chosen = deviceResults[0];
    }
  }

  const finalTotal = chosen ? chosen.total : 0;
  const chosenHourly = chosen ? chosen.hourly : new Map<number, number>();
  const chosenDevice = chosen ? chosen.device : null;

  const buckets: HourlyStepBucket[] = [];
  for (let h = 0; h < 24; h++) {
    buckets.push({ hour: h, steps: chosenHourly.get(h) ?? 0 });
  }

  // Active calories: check active_energy telemetry for chosen device or estimate 0.042 * steps
  let activeCal = 0;
  const energyRecs = records.filter(r => {
    const norm = normalizeMetricType(r.type);
    if (norm !== 'activeenergy' && norm !== 'activecalories' && norm !== 'calories') return false;
    const s = parseUtcDate(r.start_time);
    return isSameLocalDate(s, targetDateStr, tzOffsetMin);
  });

  if (chosenDevice) {
    const devEnergy = energyRecs.filter(r => (r.source_device || '').trim() === chosenDevice);
    if (devEnergy.length > 0) {
      if (isCumulativeDevice(chosenDevice, devEnergy)) {
        activeCal = Math.max(0, ...devEnergy.map(r => r.value ?? 0));
      } else {
        activeCal = devEnergy.map(r => r.value ?? 0).reduce((a, b) => a + b, 0);
      }
    }
  }
  if (activeCal <= 0) {
    activeCal = Math.round(finalTotal * 0.042 * 10) / 10;
  }

  return {
    total_steps: finalTotal,
    active_calories: Math.round(activeCal * 10) / 10,
    source_device: chosenDevice,
    hourly_steps: buckets
  };
}

// ==========================================
// 4. Cardiovascular & Heart Rate Zones Engine
// ==========================================

export function mapHeartRateZone(bpm: number): HeartRateZoneName {
  if (bpm < 100) return 'Resting';
  if (bpm < 120) return 'Fat Burn';
  if (bpm < 150) return 'Cardio';
  return 'Peak';
}

export function computeCardiovascular(
  records: HealthTelemetryRow[],
  targetDateStr: string,
  tzOffsetMin: number,
  measuredRhrBpm?: number | null
): CardiovascularSummary {
  const hrRecords = records.filter(r => {
    const norm = normalizeMetricType(r.type);
    if (norm !== 'heartrate' && norm !== 'hr' && norm !== 'pulse') return false;
    const s = parseUtcDate(r.start_time);
    return isSameLocalDate(s, targetDateStr, tzOffsetMin);
  });

  const validPoints: IntradayHeartRatePoint[] = [];
  for (const r of hrRecords) {
    const val = r.value ?? 0;
    if (val > 30 && val < 240) {
      validPoints.push({
        id: r.id,
        timestamp: r.start_time,
        bpm: Math.round(val * 10) / 10,
        zone: mapHeartRateZone(val),
        source_device: r.source_device
      });
    }
  }

  validPoints.sort((a, b) => toEpochMs(a.timestamp) - toEpochMs(b.timestamp));

  if (validPoints.length === 0) {
    return {
      average_bpm: null,
      resting_bpm: measuredRhrBpm ?? null,
      min_bpm: null,
      max_bpm: null,
      zones: { resting: 0, fat_burn: 0, cardio: 0, peak: 0 },
      intraday_points: []
    };
  }

  const bpms = validPoints.map(p => p.bpm);
  const sum = bpms.reduce((a, b) => a + b, 0);
  const avg = Math.round((sum / bpms.length) * 10) / 10;
  const min = Math.min(...bpms);
  const max = Math.max(...bpms);

  const resting =
    measuredRhrBpm !== undefined && measuredRhrBpm !== null && measuredRhrBpm > 0
      ? measuredRhrBpm
      : min > 0
      ? min + 4
      : null;

  const zones = { resting: 0, fat_burn: 0, cardio: 0, peak: 0 };
  for (const p of validPoints) {
    if (p.zone === 'Resting') zones.resting++;
    else if (p.zone === 'Fat Burn') zones.fat_burn++;
    else if (p.zone === 'Cardio') zones.cardio++;
    else if (p.zone === 'Peak') zones.peak++;
  }

  // Downsample to 5-minute buckets for intraday_points output if dense (> 300 points)
  let outputPoints = validPoints;
  if (validPoints.length > 300) {
    const FIVE_MIN_MS = 5 * 60 * 1000;
    const buckets = new Map<string, { sum: number; count: number; timestamp: string; device?: string }>();
    for (const pt of validPoints) {
      const epoch = toEpochMs(pt.timestamp);
      const bucketEpoch = Math.floor(epoch / FIVE_MIN_MS) * FIVE_MIN_MS;
      const key = `${bucketEpoch}_${pt.source_device || ''}`;
      const existing = buckets.get(key);
      if (existing) {
        existing.sum += pt.bpm;
        existing.count += 1;
      } else {
        buckets.set(key, {
          sum: pt.bpm,
          count: 1,
          timestamp: new Date(bucketEpoch).toISOString(),
          device: pt.source_device
        });
      }
    }
    outputPoints = Array.from(buckets.values()).map(b => {
      const bAvg = Math.round((b.sum / b.count) * 10) / 10;
      return {
        timestamp: b.timestamp,
        bpm: bAvg,
        zone: mapHeartRateZone(bAvg),
        source_device: b.device
      };
    }).sort((a, b) => toEpochMs(a.timestamp) - toEpochMs(b.timestamp));
  }

  return {
    average_bpm: avg,
    resting_bpm: resting ? Math.round(resting) : null,
    min_bpm: Math.round(min),
    max_bpm: Math.round(max),
    zones,
    intraday_points: outputPoints
  };
}

// ==========================================
// 5. Autonomic Nervous System & Stress Engine v2.0
// ==========================================

export const DEFAULT_BASELINE_HRV_SDNN = 45.0; // ms (Apple Watch / clinical short-term SDNN)
export const DEFAULT_BASELINE_HRV_RMSSD = 62.0; // ms (Wear OS / Fitbit / Oura nocturnal RMSSD)
export const DEFAULT_BASELINE_RHR = 60.0; // bpm

export function scoreFromHrv(hrv: number, baseline: number): number {
  if (baseline <= 0) return 50.0;
  const scale = Math.max(14.0, baseline * 0.35);
  const z = (hrv - baseline) / scale;
  // Smooth sigmoid/tanh transfer around personal/metric-calibrated baseline:
  // High HRV -> low stress (< 25), baseline HRV -> 50, suppressed HRV -> high stress (> 75)
  const normalized = 50.0 - Math.tanh(z) * 45.0;
  return Math.min(100.0, Math.max(0.0, normalized));
}

/**
 * Calibrated sedentary waking HR arousal curve relative to sleeping/resting RHR.
 * Accounts for natural upright waking orthostatic + metabolic offset (+10..20 bpm above sleeping RHR)
 * without saturating at 100/100 during normal desk work or conversation.
 */
export function scoreFromSedentaryHr(avgHr: number, baselineRhr: number): number {
  const delta = avgHr - baselineRhr;
  const z = (delta - 22.0) / 16.0;
  const score = 46.0 + Math.tanh(z) * 44.0;
  return Math.min(95.0, Math.max(6.0, score));
}

/**
 * Derives an authentic sleeping/resting HR baseline from nocturnal 5-min HR buckets
 * when a wearable (e.g. Oura Ring via Apple HealthKit) does not export a standalone RHR metric.
 */
export function deriveNocturnalRhrFromHrPoints(
  hrPoints: IntradayHeartRatePoint[],
  targetDateStr: string,
  tzOffsetMin: number
): number | null {
  const nocturnalBpms: number[] = [];
  const daytimeBpms: number[] = [];

  for (const pt of hrPoints) {
    if (pt.bpm <= 35 || pt.bpm >= 220) continue;
    const s = parseUtcDate(pt.timestamp);
    if (!isSameLocalDate(s, targetDateStr, tzOffsetMin)) continue;
    const h = getLocalHour(s, tzOffsetMin);
    if (h < 8 && pt.bpm <= 95) {
      nocturnalBpms.push(pt.bpm);
    } else if (h >= 8) {
      daytimeBpms.push(pt.bpm);
    }
  }

  if (nocturnalBpms.length >= 3) {
    nocturnalBpms.sort((a, b) => a - b);
    const mid = Math.floor(nocturnalBpms.length / 2);
    const nocturnalMedian =
      nocturnalBpms.length % 2 === 1
        ? nocturnalBpms[mid]
        : (nocturnalBpms[mid - 1] + nocturnalBpms[mid]) / 2;
    // Clinical RHR (Fitbit / Apple Health standard) reflects quiet waking resting HR,
    // which sits ~5.5 bpm above nocturnal sleep HR median (rather than 4 AM sleep nadir).
    const clinicalRhr = nocturnalMedian + 5.5;
    return Math.round(Math.min(85, Math.max(45, clinicalRhr)));
  }

  if (daytimeBpms.length >= 3) {
    const minDay = Math.min(...daytimeBpms);
    return Math.round(Math.min(72, Math.max(48, minDay - 2)));
  }

  return null;
}

export function mapStressLevel(score: number): StressLevelName {
  if (score <= 25) return 'Restful';
  if (score <= 50) return 'Calm';
  if (score <= 75) return 'Moderate';
  return 'High';
}

export function computeStress(params: {
  targetDateStr: string;
  tzOffsetMin: number;
  hrvMs: number | null;
  isRmssd?: boolean;
  hrPoints: IntradayHeartRatePoint[];
  hourlySteps: HourlyStepBucket[];
  restingBpm: number | null;
  priorSleepScore: number | null;
  personalBaselineHrv?: number;
  personalBaselineRhr?: number;
  perDeviceRhrMap?: Record<string, number>;
  sourceDevice?: string | null;
}): StressSummary | null {
  const {
    targetDateStr,
    tzOffsetMin,
    hrvMs,
    isRmssd = false,
    hrPoints,
    hourlySteps,
    restingBpm,
    priorSleepScore,
    personalBaselineHrv,
    personalBaselineRhr,
    perDeviceRhrMap,
    sourceDevice
  } = params;

  const hasHrv = hrvMs !== null && hrvMs !== undefined && hrvMs > 0;

  // Valid stress calculation requires genuine physiological signal (HRV or heart rate samples)
  if (!hasHrv && hrPoints.length === 0) {
    return null;
  }

  const defaultHrvBaseline = isRmssd ? DEFAULT_BASELINE_HRV_RMSSD : DEFAULT_BASELINE_HRV_SDNN;
  const baselineHrv =
    personalBaselineHrv !== undefined && personalBaselineHrv > 0
      ? Math.round(personalBaselineHrv * 10) / 10
      : defaultHrvBaseline;

  const derivedRhr = deriveNocturnalRhrFromHrPoints(hrPoints, targetDateStr, tzOffsetMin);
  const baselineRhr =
    restingBpm !== null && restingBpm !== undefined && restingBpm > 0
      ? restingBpm
      : derivedRhr ??
        (personalBaselineRhr !== undefined && personalBaselineRhr > 0
          ? personalBaselineRhr
          : DEFAULT_BASELINE_RHR);

  const sleepScore = priorSleepScore !== null && priorSleepScore > 0 ? priorSleepScore : 80;

  // Build map of steps by hour
  const stepsByHour = new Map<number, number>();
  for (const b of hourlySteps) {
    stepsByHour.set(b.hour, b.steps);
  }

  // Group HR telemetry by local hour (preserving source_device for sensor-matched RHR anchoring)
  const hrByHour = new Map<number, Array<{ bpm: number; source: string | null }>>();
  for (const pt of hrPoints) {
    const s = parseUtcDate(pt.timestamp);
    if (isSameLocalDate(s, targetDateStr, tzOffsetMin)) {
      const h = getLocalHour(s, tzOffsetMin);
      if (!hrByHour.has(h)) hrByHour.set(h, []);
      hrByHour.get(h)!.push({ bpm: pt.bpm, source: pt.source_device ?? null });
    }
  }

  const resolveSensorBaselineRhr = (sensorName: string | null | undefined): number => {
    if (sensorName && perDeviceRhrMap) {
      const candidate = perDeviceRhrMap[sensorName];
      if (candidate !== undefined && candidate >= 40 && candidate <= 98) {
        return candidate;
      }
    }
    return baselineRhr;
  };

  const intradayPoints: IntradayStressPoint[] = [];
  const sleepPenalty = Math.max(0.0, Math.min(100.0, 100.0 - sleepScore));
  const dayHrvScore = hasHrv ? scoreFromHrv(hrvMs!, baselineHrv) : null;
  let lastSedentaryHrScore: number | null = null;
  let latestSedentaryHrBpm: number | null = null;
  let latestSedentarySensor: string | null = null;

  for (let hour = 0; hour < 24; hour++) {
    const steps = stepsByHour.get(hour) ?? 0;
    const isSedentary = steps < 300;

    const hrSamples = hrByHour.get(hour) ?? [];
    if (hrSamples.length === 0 && (!hasHrv || steps === 0)) {
      continue;
    }

    const avgHr =
      hrSamples.length > 0
        ? hrSamples.reduce((a, b) => a + b.bpm, 0) / hrSamples.length
        : null;

    // Dominant sensor in this hour (last sample's sensor wins ties so mid-hour watch swap tracks new watch)
    let hourSensor: string | null = null;
    if (hrSamples.length > 0) {
      const counts = new Map<string, number>();
      for (const s of hrSamples) {
        if (s.source) counts.set(s.source, (counts.get(s.source) ?? 0) + 1);
      }
      let bestCnt = 0;
      for (const s of hrSamples) {
        if (s.source) {
          const cnt = counts.get(s.source) ?? 0;
          if (cnt >= bestCnt) {
            bestCnt = cnt;
            hourSensor = s.source;
          }
        }
      }
    }
    const hourRhrAnchor = resolveSensorBaselineRhr(hourSensor);

    // B. Calibrated Sedentary HR Arousal Component (with inertia carry-forward during movement hours)
    let hrScore: number;
    if (avgHr !== null && isSedentary) {
      hrScore = scoreFromSedentaryHr(avgHr, hourRhrAnchor);
      lastSedentaryHrScore = hrScore;
      latestSedentaryHrBpm = avgHr;
      latestSedentarySensor = hourSensor;
    } else if (lastSedentaryHrScore !== null) {
      hrScore = 0.85 * lastSedentaryHrScore + 0.15 * 32.0;
    } else if (dayHrvScore !== null) {
      hrScore = 0.70 * dayHrvScore + 0.30 * 32.0;
    } else {
      hrScore = 32.0;
    }

    // C. Blended hourly stress (honest re-normalization when device has no HRV, e.g. Oura via HealthKit)
    const rawHourly =
      dayHrvScore !== null
        ? 0.45 * dayHrvScore + 0.35 * hrScore + 0.20 * sleepPenalty
        : 0.70 * hrScore + 0.30 * sleepPenalty;

    const finalScore = Math.round(Math.min(98.0, Math.max(5.0, rawHourly)));
    const level = mapStressLevel(finalScore);

    const hourMidnight = getLocalMidnightUtc(targetDateStr, tzOffsetMin);
    const hourTimestamp = new Date(hourMidnight.getTime() + hour * 3600 * 1000).toISOString();

    intradayPoints.push({
      timestamp: hourTimestamp,
      hour,
      score: finalScore,
      level,
      hrv_ms: hasHrv ? hrvMs : null,
      heart_rate_bpm: avgHr !== null ? Math.round(avgHr * 10) / 10 : null,
      is_sedentary: isSedentary
    });
  }

  // Resolve current / master stress score from genuine sedentary tone (immune to active-hour step collapse)
  const lastHrPt = hrPoints.length > 0 ? hrPoints[hrPoints.length - 1] : null;
  const lastHr = lastHrPt ? lastHrPt.bpm : null;
  const activeStressSensor =
    sourceDevice ??
    (latestSedentaryHrBpm !== null ? latestSedentarySensor : (lastHrPt?.source_device ?? null));
  const activeSensorRhr = resolveSensorBaselineRhr(activeStressSensor);
  const effectiveSedentaryBpm = latestSedentaryHrBpm ?? lastHr;
  const currentElevation =
    effectiveSedentaryBpm !== null ? Math.max(0.0, effectiveSedentaryBpm - activeSensorRhr) : null;

  let currentScore: number;
  const sedentaryPoints = intradayPoints.filter(p => p.is_sedentary && p.heart_rate_bpm !== null);
  if (sedentaryPoints.length >= 2) {
    const lastSed = sedentaryPoints[sedentaryPoints.length - 1].score;
    const prevSed = sedentaryPoints[sedentaryPoints.length - 2].score;
    currentScore = Math.round(0.70 * lastSed + 0.30 * prevSed);
  } else if (sedentaryPoints.length === 1) {
    currentScore = sedentaryPoints[0].score;
  } else if (intradayPoints.length > 0) {
    currentScore = intradayPoints[intradayPoints.length - 1].score;
  } else {
    const fallbackHrScore =
      effectiveSedentaryBpm !== null
        ? scoreFromSedentaryHr(effectiveSedentaryBpm, baselineRhr)
        : dayHrvScore !== null
          ? 0.70 * dayHrvScore + 0.30 * 32.0
          : 32.0;
    const blended =
      dayHrvScore !== null
        ? 0.45 * dayHrvScore + 0.35 * fallbackHrScore + 0.20 * sleepPenalty
        : 0.70 * fallbackHrScore + 0.30 * sleepPenalty;
    currentScore = Math.round(Math.min(95.0, Math.max(8.0, blended)));
  }

  const currentLevel = mapStressLevel(currentScore);

  // Daily average
  let dailyAverage: number;
  if (intradayPoints.length > 0) {
    const sum = intradayPoints.map(p => p.score).reduce((a, b) => a + b, 0);
    dailyAverage = Math.round(sum / intradayPoints.length);
  } else {
    dailyAverage = currentScore;
  }

  let peakHour: number | null = null;
  let peakScore: number | null = null;
  let lowestHour: number | null = null;
  let lowestScore: number | null = null;

  if (intradayPoints.length > 0) {
    let pPt = intradayPoints[0];
    let lPt = intradayPoints[0];
    for (const pt of intradayPoints) {
      if (pt.score > pPt.score) pPt = pt;
      if (pt.score < lPt.score) lPt = pt;
    }
    peakHour = pPt.hour;
    peakScore = pPt.score;
    lowestHour = lPt.hour;
    lowestScore = lPt.score;
  }

  // Autonomic balance
  const parasympathetic = Math.min(90, Math.max(10, 100 - currentScore));
  const sympathetic = 100 - parasympathetic;

  const hrvDelta =
    hrvMs !== null ? Math.round(((hrvMs - baselineHrv) / baselineHrv) * 1000) / 10 : null;

  let monkeyMood: MonkeyMoodName;
  let adviceQuote: string;
  let recommendedBreathing: string;

  switch (currentLevel) {
    case 'Restful':
      monkeyMood = 'Zen Monkey';
      adviceQuote =
        "You're in peak recovery mode! Perfect balance of mind and body — ideal for creative breakthroughs.";
      recommendedBreathing = 'Resonance Flow (5.5s)';
      break;
    case 'Calm':
      monkeyMood = 'Curious Monkey';
      adviceQuote =
        'Autonomic tone is nice and steady. Keep up this calm rhythm with a fresh sip of water!';
      recommendedBreathing = 'Relaxing 4-7-8';
      break;
    case 'Moderate':
      monkeyMood = 'Busy Monkey';
      adviceQuote =
        'Tension is gently creeping up. Step back for 3 minutes and try Box Breathing (4s In, 4s Hold, 4s Out, 4s Hold).';
      recommendedBreathing = 'Box Breathing (4-4-4-4)';
      break;
    case 'High':
      monkeyMood = 'Overheated Monkey';
      adviceQuote =
        'High sympathetic arousal detected! Do 3 Physiological Sighs right now: two quick nose inhales, one long slow exhale.';
      recommendedBreathing = 'Physiological Sigh';
      break;
  }

  return {
    current_score: currentScore,
    current_level: currentLevel,
    daily_average: dailyAverage,
    peak_hour: peakHour,
    peak_score: peakScore,
    lowest_hour: lowestHour,
    lowest_score: lowestScore,
    parasympathetic_percent: parasympathetic,
    sympathetic_percent: sympathetic,
    baseline_hrv_ms: baselineHrv,
    current_hrv_ms: hrvMs,
    hrv_delta_percent: hrvDelta,
    resting_heart_rate_bpm: Math.round(activeSensorRhr),
    current_sedentary_bpm: effectiveSedentaryBpm !== null ? Math.round(effectiveSedentaryBpm) : null,
    heart_rate_elevation_bpm: currentElevation !== null ? Math.round(currentElevation * 10) / 10 : null,
    monkey_mood: monkeyMood,
    advice_quote: adviceQuote,
    recommended_breathing: recommendedBreathing,
    source_device: activeStressSensor,
    intraday_points: intradayPoints
  };
}

// ==========================================
// 6. Unified Daily Health Summary Orchestrator
// ==========================================

export function computeDailyHealthSummary(input: EngineInput): HealthDailySummaryRow {
  const {
    userId,
    targetDate,
    telemetry,
    tzOffsetMin = 0,
    preferredDevice,
    baselineHrvMs,
    baselineRhrBpm
  } = input;

  // 1. Process Sleep
  const sleepResult = clusterSleepTelemetry(telemetry, targetDate, tzOffsetMin, preferredDevice);
  const sleepGuidance = generateSleepGuidance(sleepResult.primarySession, targetDate);

  // 2. Process Activity & Steps
  const activitySummary = computeDailySteps(telemetry, targetDate, tzOffsetMin, preferredDevice);

  // 3. Process Other Vitals from raw telemetry
  const vitalsMap: Record<string, VitalSummaryItem> = {};
  for (const r of telemetry) {
    const norm = normalizeMetricType(r.type);
    // Ignore sleep stages & steps in scalar vitals table
    if (isSleepStageRecord(r) || norm === 'steps' || norm === 'stepcount') continue;

    const val = r.value;
    if (val === null || val === undefined) continue;

    const s = parseUtcDate(r.start_time);
    if (!isSameLocalDate(s, targetDate, tzOffsetMin)) continue;

    // Keep freshest sample
    const existing = vitalsMap[norm];
    if (!existing || toEpochMs(r.start_time) >= toEpochMs(existing.timestamp)) {
      vitalsMap[norm] = {
        type: r.type,
        value: Math.round(val * 100) / 100,
        unit: r.unit || '',
        source_device: r.source_device,
        timestamp: r.start_time
      };
    }
  }

  // 4. Process Cardiovascular
  const measuredRhr = vitalsMap['restingheartrate']?.value ?? vitalsMap['rhr']?.value ?? null;
  const cardioSummary = computeCardiovascular(telemetry, targetDate, tzOffsetMin, measuredRhr);

  // 5. Process Stress
  const hrvVal =
    vitalsMap['hrvsdnn']?.value ??
    vitalsMap['hrv']?.value ??
    vitalsMap['hrvrmssd']?.value ??
    null;

  const stressSummary = computeStress({
    targetDateStr: targetDate,
    tzOffsetMin,
    hrvMs: hrvVal,
    hrPoints: cardioSummary.intraday_points,
    hourlySteps: activitySummary.hourly_steps,
    restingBpm: cardioSummary.resting_bpm,
    priorSleepScore: sleepResult.primarySession ? sleepResult.primarySession.sleep_score : null,
    personalBaselineHrv: baselineHrvMs,
    personalBaselineRhr: baselineRhrBpm
  });

  // Calculate raw_watermark (maximum created_at or start_time across telemetry)
  let watermarkMs = 0;
  const sourceKeys = new Set<string>();
  for (const r of telemetry) {
    const tMs = toEpochMs(r.created_at || r.start_time);
    if (tMs > watermarkMs) watermarkMs = tMs;
    const key = (r.source_device_key || r.source_device || '').trim();
    if (key.length > 0 && key !== 'Unknown') {
      sourceKeys.add(key);
    }
  }
  const rawWatermark = watermarkMs > 0 ? new Date(watermarkMs).toISOString() : null;

  // Build All Devices View (freshest / primary value per metric)
  const allDevicesView: Record<string, any> = {};
  if (activitySummary.total_steps > 0) {
    allDevicesView['steps'] = {
      value: activitySummary.total_steps,
      source_key: activitySummary.source_device || 'Smartwatch',
      source_color: '#3897F0'
    };
  }
  if (sleepResult.primarySession && sleepResult.primarySession.asleep_seconds > 0) {
    allDevicesView['sleep_duration_seconds'] = {
      value: sleepResult.primarySession.asleep_seconds,
      source_key: sleepResult.primarySession.source_device || 'Oura Ring',
      source_color: '#00D09C',
      score: sleepResult.primarySession.sleep_score
    };
  }
  if (cardioSummary.resting_bpm && cardioSummary.resting_bpm > 0) {
    allDevicesView['resting_heart_rate'] = {
      value: cardioSummary.resting_bpm,
      source_key: vitalsMap['restingheartrate']?.source_device || sleepResult.primarySession?.source_device || 'Wearable',
      source_color: '#00D09C'
    };
  }
  if (activitySummary.active_calories > 0) {
    allDevicesView['active_calories'] = {
      value: activitySummary.active_calories,
      source_key: activitySummary.source_device || 'Smartwatch',
      source_color: '#FF6B4A'
    };
  }
  if (stressSummary) {
    allDevicesView['stress'] = {
      value: stressSummary.current_score,
      source_key: 'Biometric Engine',
      source_color: '#AF52DE',
      score: stressSummary.current_score
    };
  }

  const computedAt = new Date().toISOString();

  const payload: DailyHealthSummaryPayload = {
    date: targetDate,
    engine_version: 'v1.0',
    computed_at: computedAt,
    sources: Array.from(sourceKeys).sort(),
    all_devices_view: allDevicesView,
    sleep: {
      primary_session: sleepResult.primarySession,
      all_sessions: sleepResult.allSessions,
      naps: sleepResult.naps,
      guidance: sleepGuidance
    },
    activity: activitySummary,
    cardiovascular: cardioSummary,
    stress: stressSummary,
    vitals: vitalsMap
  };

  return {
    user_id: userId,
    local_date: targetDate,
    computed_at: computedAt,
    engine_version: 'v1.0',
    raw_watermark: rawWatermark,
    steps: activitySummary.total_steps > 0 ? activitySummary.total_steps : null,
    active_kcal: activitySummary.active_calories > 0 ? activitySummary.active_calories : null,
    sleep_asleep_s: sleepResult.primarySession
      ? sleepResult.primarySession.asleep_seconds
      : (sleepResult.allSessions.length > 0
          ? sleepResult.allSessions.reduce((max, s) => Math.max(max, s.asleep_seconds), 0)
          : (sleepResult.naps.length > 0 ? sleepResult.naps.reduce((sum, n) => sum + n.duration_seconds, 0) : null)),
    sleep_score: sleepResult.primarySession
      ? sleepResult.primarySession.sleep_score
      : (sleepResult.allSessions.length > 0 ? sleepResult.allSessions[0].sleep_score : null),
    stress_avg: stressSummary ? stressSummary.daily_average : null,
    rhr: cardioSummary.resting_bpm,
    hrv_sdnn: vitalsMap['hrvsdnn']?.value ?? vitalsMap['hrv']?.value ?? null,
    hrv_rmssd: vitalsMap['hrvrmssd']?.value ?? null,
    weight: vitalsMap['weight']?.value ?? null,
    spo2: vitalsMap['oxygensaturation']?.value ?? vitalsMap['spo2']?.value ?? null,
    summary: payload
  };
}

// ==========================================
// 7. Lean Architecture Canonical Synthesizer (v2.0)
// ==========================================

export function canonicalizeDeviceName(raw?: string | null, hostName?: string | null): string {
  const k = (raw || '').trim().toLowerCase();
  const h = (hostName || '').trim().toLowerCase();

  if (!k || k === 'unknown') {
    if (h.includes('radar') || h.includes('fold')) return 'Radar (Galaxy Z Fold 8)';
    if (h.includes('trapper') || h.includes('pixel')) return 'Trapper (Pixel 9 Pro)';
    if (h.includes('schmitz') || h.includes('iphone')) return 'Schmitz (iPhone)';
    return 'Unknown';
  }

  if (k.includes('oura')) return 'Oura Ring';
  if (
    k.includes('pixel watch') ||
    k.includes('fitbit') ||
    k.includes('google health') ||
    k.includes('wear.companion') ||
    k.includes('google.android.wearable') ||
    k === 'trapper_pw5'
  ) {
    return 'Pixel Watch 5';
  }
  if (
    k.includes('oneplus') ||
    k.includes('heytap') ||
    k.includes('international') ||
    k.includes('ohealth') ||
    k.includes('oplus')
  ) {
    return 'OnePlus Watch 3';
  }
  if (
    k.includes('apple watch') ||
    k.includes('watchos') ||
    k.includes('ultra 2') ||
    k === 'schmitz_ultra2'
  ) {
    return 'Apple Watch Ultra 2';
  }
  if (k.includes('amazfit') || k.includes('zepp') || k.includes('huami') || k.includes('balance')) {
    return 'Amazfit Balance';
  }
  if (k.includes('huawei') || k.includes('harmony') || k.includes('gt 5') || k.includes('gt5')) {
    return 'Huawei Watch GT 5 Pro';
  }
  if (k.includes('garmin')) return 'Garmin';
  if (k.includes('whoop')) return 'Whoop';
  if (k.includes('withings')) return 'Withings';
  if (k.includes('polar')) return 'Polar';
  if (k.includes('galaxy watch')) return 'Galaxy Watch';

  if (k.includes('radar') || k.includes('fold') || k.includes('sm-f9') || k.includes('shealth') || k.includes('samsung')) {
    return 'Radar (Galaxy Z Fold 8)';
  }
  if (k.includes('trapper') || k.includes('pixel 9') || k.includes('j97428') || k.includes('healthconnect') || k.includes('health connect') || k.includes('google fit') || k.includes('apps.fitness')) {
    return h.includes('radar') ? 'Radar (Galaxy Z Fold 8)' : 'Trapper (Pixel 9 Pro)';
  }
  if (k.includes('schmitz') || k.includes('iphone') || k.includes('apple health') || k.includes('healthkit') || k.includes('canonical')) {
    return 'Schmitz (iPhone)';
  }

  return (raw || '').trim();
}

export function isWearableDevice(device: string): boolean {
  const lower = canonicalizeDeviceName(device).toLowerCase();
  if (
    lower.includes('oura') ||
    lower.includes('ring') ||
    lower.includes('watch') ||
    lower.includes('ultra') ||
    lower.includes('fitbit') ||
    lower.includes('oneplus') ||
    lower.includes('amazfit') ||
    lower.includes('zepp') ||
    lower.includes('balance') ||
    lower.includes('huawei') ||
    lower.includes('gt 5') ||
    lower.includes('gt5') ||
    lower.includes('garmin') ||
    lower.includes('whoop') ||
    lower.includes('polar') ||
    lower.includes('withings')
  ) {
    return true;
  }
  return false;
}

export function getCanonicalSleepPriority(device: string, isNap = false): number {
  if (isNap) return 99;
  const canon = canonicalizeDeviceName(device);
  if (canon === 'Oura Ring') return 1;
  if (canon === 'Apple Watch Ultra 2') return 2;
  if (canon === 'Pixel Watch 5') return 3;
  if (canon === 'OnePlus Watch 3') return 4;
  if (isWearableDevice(canon)) return 5;
  return 10;
}

export function getCanonicalVitalsPriority(device: string): number {
  const canon = canonicalizeDeviceName(device);
  if (canon === 'Oura Ring') return 1;
  if (canon === 'Apple Watch Ultra 2') return 2;
  if (canon === 'Pixel Watch 5') return 3;
  if (canon === 'OnePlus Watch 3') return 4;
  if (isWearableDevice(canon)) return 5;
  return 10;
}

export function getCanonicalDeviceColor(device: string): string {
  const canon = canonicalizeDeviceName(device);
  switch (canon) {
    case 'Oura Ring': return '#00D09C';
    case 'Apple Watch Ultra 2': return '#34C759';
    case 'Pixel Watch 5': return '#3897F0';
    case 'OnePlus Watch 3': return '#FF6B4A';
    case 'Schmitz (iPhone)': return '#AF52DE';
    case 'Trapper (Pixel 9 Pro)': return '#5856D6';
    case 'Radar (Galaxy Z Fold 8)': return '#00C7BE';
    default: return '#3897F0';
  }
}

export interface LeanEngineInput {
  userId: string;
  targetDate: string;
  vitalsRows: LeanDailyVitalsRow[];
  sleepRows: LeanSleepSessionRow[];
  hrRows: LeanIntradayHrRow[];
  historyVitalsRows?: LeanDailyVitalsRow[];
  sourceRows?: LeanHealthSourceRow[];
  tzOffsetMin?: number;
  preferredDevice?: string;
  baselineHrvMs?: number;
  baselineRhrBpm?: number;
  archivedCardiovascular?: CardiovascularSummary | null;
}

function computeRollingMedianOrMean(values: number[]): number | undefined {
  const valid = values.filter(v => Number.isFinite(v) && v > 0);
  if (valid.length < 2) return undefined;
  const sorted = [...valid].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  const median =
    sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  return Math.round(median * 10) / 10;
}

function vitalsRowHasSignal(v: LeanDailyVitalsRow): boolean {
  return (
    (v.steps ?? 0) > 0 ||
    (v.active_kcal ?? 0) > 0 ||
    (v.latest_heart_rate ?? 0) > 0 ||
    (v.resting_heart_rate ?? 0) > 0 ||
    (v.spo2 ?? 0) > 0 ||
    (v.respiratory_rate ?? 0) > 0 ||
    v.skin_temp_celsius !== null && v.skin_temp_celsius !== undefined ||
    (v.weight_kg ?? 0) > 0 ||
    (v.hrv_sdnn_nightly ?? 0) > 0 ||
    (v.hrv_rmssd_nightly ?? 0) > 0
  );
}

export function synthesizeDailyHealthSummaryFromLean(input: LeanEngineInput): HealthDailySummaryRow {
  const {
    userId,
    targetDate,
    vitalsRows,
    sleepRows,
    hrRows,
    historyVitalsRows = [],
    sourceRows = [],
    tzOffsetMin = 120,
    preferredDevice,
    baselineHrvMs,
    baselineRhrBpm,
    archivedCardiovascular = null
  } = input;

  // Build unified single-list priority map from public.health_sources (1 = highest priority)
  const userPriorityMap = new Map<string, number>();
  for (const sr of sourceRows) {
    const canon = canonicalizeDeviceName(sr.display_name, null);
    const p = sr.priority_sleep ?? sr.priority_activity;
    if (canon && canon !== 'Unknown' && typeof p === 'number' && p > 0) {
      userPriorityMap.set(canon, p);
    }
  }
  const getEffectivePriority = (device: string, isNap = false): number => {
    if (isNap) return 99;
    const canon = canonicalizeDeviceName(device);
    return userPriorityMap.get(canon) ?? getCanonicalVitalsPriority(canon);
  };

  const prefCanon = preferredDevice && preferredDevice.trim().length > 0
    ? canonicalizeDeviceName(preferredDevice)
    : undefined;

  // Collect strictly canonical devices that actually emitted signal on targetDate
  const activeSourceSet = new Set<string>();
  for (const s of sleepRows) {
    if ((s.duration_seconds ?? 0) > 0) {
      const c = canonicalizeDeviceName(s.source_device_key, s.host_device_name);
      if (c && c !== 'Unknown') activeSourceSet.add(c);
    }
  }
  for (const v of vitalsRows) {
    if (vitalsRowHasSignal(v)) {
      const c = canonicalizeDeviceName(v.source_device_key, v.host_device_name);
      if (c && c !== 'Unknown') activeSourceSet.add(c);
    }
  }
  for (const h of hrRows) {
    if ((h.bpm_avg ?? 0) > 30) {
      const c = canonicalizeDeviceName(h.source_device_key, null);
      if (c && c !== 'Unknown') activeSourceSet.add(c);
    }
  }
  if (hrRows.length === 0 && archivedCardiovascular && Array.isArray(archivedCardiovascular.intraday_points)) {
    for (const pt of archivedCardiovascular.intraday_points) {
      if ((pt.bpm ?? 0) > 30 && pt.source_device) {
        const c = canonicalizeDeviceName(pt.source_device, null);
        if (c && c !== 'Unknown') activeSourceSet.add(c);
      }
    }
  }

  const orderedSources = Array.from(activeSourceSet).sort((a, b) => {
    const pa = getEffectivePriority(a, false);
    const pb = getEffectivePriority(b, false);
    if (pa !== pb) return pa - pb;
    return a.localeCompare(b);
  });

  // 1. Build Sleep Sessions & Naps
  const allSessions: SleepSession[] = [];
  const naps: NapSession[] = [];
  let userSelectedDevice: string | null = null;

  for (const row of sleepRows) {
    const canonDevice = canonicalizeDeviceName(row.source_device_key, row.host_device_name);
    const isNap = row.session_type === 'nap';
    if (isNap) {
      naps.push({
        id: row.id,
        start_time: row.start_time,
        end_time: row.end_time,
        duration_seconds: Math.max(0, Math.round(row.duration_seconds || 0)),
        source_device: canonDevice
      });
      continue;
    }

    if (row.is_user_selected) {
      userSelectedDevice = canonDevice;
    }

    const rawStages = Array.isArray(row.stages) ? row.stages : [];
    const mappedStages: SleepStageRecord[] = rawStages
      .map((st: any, idx: number) => {
        const rawType = String(st.stage_type ?? st.stageType ?? st.stage ?? 'Light');
        const stStart = String(st.start_time ?? st.startTime ?? row.start_time);
        const stEnd = String(st.end_time ?? st.endTime ?? stStart);
        let dur = Number(st.duration_seconds ?? st.durationSeconds ?? 0);
        if (dur <= 0) {
          dur = Math.max(0, Math.round((toEpochMs(stEnd) - toEpochMs(stStart)) / 1000));
        }
        return {
          id: String(st.id ?? `${row.id}_st_${idx}`),
          stage_type: mapSleepStageType(rawType),
          start_time: stStart,
          end_time: stEnd,
          duration_seconds: Math.round(dur),
          source_device: canonDevice
        };
      })
      .filter(st => st.duration_seconds > 0);

    const deepSec = Math.round(row.deep_seconds ?? mappedStages.filter(s => s.stage_type === 'Deep').reduce((a, b) => a + b.duration_seconds, 0));
    const remSec = Math.round(row.rem_seconds ?? mappedStages.filter(s => s.stage_type === 'REM').reduce((a, b) => a + b.duration_seconds, 0));
    const lightSec = Math.round(row.light_seconds ?? mappedStages.filter(s => s.stage_type === 'Light').reduce((a, b) => a + b.duration_seconds, 0));
    const awakeSec = Math.round(row.awake_seconds ?? mappedStages.filter(s => s.stage_type === 'Awake').reduce((a, b) => a + b.duration_seconds, 0));

    const asleepStages = deepSec + remSec + lightSec;
    const asleepSec = Math.max(asleepStages, Math.round(row.duration_seconds || 0));
    const totalBedSec = Math.max(asleepSec + awakeSec, Math.round(row.time_in_bed_seconds || 0));

    const deepPct = asleepSec > 0 ? Math.round((deepSec / asleepSec) * 100) : 0;
    const remPct = asleepSec > 0 ? Math.round((remSec / asleepSec) * 100) : 0;
    const lightPct = asleepSec > 0 ? Math.round((lightSec / asleepSec) * 100) : 0;
    const awakePct = totalBedSec > 0 ? Math.round((awakeSec / totalBedSec) * 100) : 0;
    const restorativePct = deepPct + remPct;
    const effPct = row.efficiency_percent && row.efficiency_percent > 0
      ? Math.min(100, Math.round(row.efficiency_percent))
      : (totalBedSec > 0 ? Math.min(100, Math.max(10, Math.round((asleepSec / totalBedSec) * 100))) : 85);
    const awakeCount = mappedStages.filter(s => s.stage_type === 'Awake').length;

    const computedScore = row.sleep_score && row.sleep_score > 0
      ? Math.min(100, Math.round(row.sleep_score))
      : calculateClinicalSleepScore({
          asleepSeconds: asleepSec,
          durationSeconds: totalBedSec,
          efficiencyPercent: effPct,
          deepPercent: deepPct,
          remPercent: remPct,
          awakeCount,
          awakeSeconds: awakeSec
        });

    allSessions.push({
      id: row.id,
      start_time: row.start_time,
      end_time: row.end_time,
      is_nap: false,
      source_device: canonDevice,
      has_granular_hypnogram: mappedStages.length > 0,
      stages: mappedStages,
      asleep_seconds: asleepSec,
      duration_seconds: totalBedSec,
      deep_seconds: deepSec,
      rem_seconds: remSec,
      light_seconds: lightSec,
      awake_seconds: awakeSec,
      deep_percent: deepPct,
      rem_percent: remPct,
      light_percent: lightPct,
      awake_percent: awakePct,
      restorative_percent: restorativePct,
      efficiency_percent: effPct,
      awake_count: awakeCount,
      sleep_score: computedScore,
      quality_rating: row.quality_rating || getSleepQualityRating(computedScore)
    });
  }

  allSessions.sort((a, b) => {
    if (prefCanon) {
      const aPref = a.source_device === prefCanon;
      const bPref = b.source_device === prefCanon;
      if (aPref !== bPref) return aPref ? -1 : 1;
    } else if (userSelectedDevice) {
      const aSel = a.source_device === userSelectedDevice;
      const bSel = b.source_device === userSelectedDevice;
      if (aSel !== bSel) return aSel ? -1 : 1;
    }
    if (a.has_granular_hypnogram !== b.has_granular_hypnogram) {
      return a.has_granular_hypnogram ? -1 : 1;
    }
    const pa = getEffectivePriority(a.source_device, false);
    const pb = getEffectivePriority(b.source_device, false);
    if (pa !== pb) return pa - pb;
    return b.asleep_seconds - a.asleep_seconds;
  });

  const primarySession = prefCanon
    ? (allSessions.find(s => s.source_device === prefCanon) ?? null)
    : (allSessions[0] ?? null);
  const sleepGuidance = generateSleepGuidance(primarySession, targetDate);

  // 2. Build Activity Summary (Class B: Hourly Active-Wearer Envelope 0..23 across wearables)
  const normalizedVitals = vitalsRows.map(v => ({
    ...v,
    canonDevice: canonicalizeDeviceName(v.source_device_key, v.host_device_name)
  }));

  const candidateActivityRows = prefCanon
    ? normalizedVitals.filter(v => v.canonDevice === prefCanon)
    : normalizedVitals;

  const extractHourlyMap = (row: (typeof normalizedVitals)[number]): Map<number, number> => {
    const m = new Map<number, number>();
    const rawH = Array.isArray(row.hourly_steps) ? row.hourly_steps : [];
    for (const hb of rawH) {
      const hr = Number((hb as any).hour);
      const st = Math.round(Number((hb as any).steps ?? 0));
      if (hr >= 0 && hr < 24 && st > 0) {
        m.set(hr, Math.max(m.get(hr) ?? 0, st));
      }
    }
    return m;
  };

  const wearableStepRows = candidateActivityRows.filter(
    v => isWearableDevice(v.canonDevice) && (v.steps ?? 0) > 0
  );
  const activeStepPool =
    wearableStepRows.length > 0
      ? wearableStepRows
      : candidateActivityRows.filter(v => (v.steps ?? 0) > 0);

  let totalSteps = 0;
  let activeCal = 0;
  let activitySourceDevice: string | null = null;
  const hourlyBuckets: HourlyStepBucket[] = [];

  if (prefCanon || activeStepPool.length <= 1) {
    const chosenActivityRow =
      activeStepPool[0] ?? candidateActivityRows[0] ?? null;
    totalSteps = Math.max(0, Math.round(chosenActivityRow?.steps ?? 0));
    const hMap = chosenActivityRow ? extractHourlyMap(chosenActivityRow) : new Map<number, number>();
    for (let h = 0; h < 24; h++) {
      hourlyBuckets.push({ hour: h, steps: hMap.get(h) ?? 0 });
    }
    activeCal = Number(chosenActivityRow?.active_kcal ?? 0);
    if (activeCal <= 0 && totalSteps > 0) {
      activeCal = Math.round(totalSteps * 0.042 * 10) / 10;
    }
    activitySourceDevice = chosenActivityRow?.canonDevice ?? null;
  } else {
    // Multi-device Hourly Active-Wearer Envelope (0..23):
    // When switching watches mid-day (e.g. PW5/Oura morning -> OnePlus Watch 3 afternoon),
    // each hour picks the active wearable (breaking simultaneous-wear ties by user priority),
    // summing disjoint wear periods without double-counting simultaneous wear!
    const rowHourlyMaps = activeStepPool.map(row => ({
      row,
      hMap: extractHourlyMap(row),
      prio: getEffectivePriority(row.canonDevice)
    }));

    const winningStepsByDevice = new Map<string, number>();
    let latestActiveHourDevice: string | null = null;
    let mergedHourlySum = 0;

    for (let h = 0; h < 24; h++) {
      const activeInHour = rowHourlyMaps
        .map(item => ({ ...item, hSteps: item.hMap.get(h) ?? 0 }))
        .filter(item => item.hSteps > 0);

      if (activeInHour.length === 0) {
        hourlyBuckets.push({ hour: h, steps: 0 });
      } else {
        activeInHour.sort((a, b) => {
          if (a.prio !== b.prio) return a.prio - b.prio;
          return b.hSteps - a.hSteps;
        });
        const winner = activeInHour[0];
        hourlyBuckets.push({ hour: h, steps: winner.hSteps });
        mergedHourlySum += winner.hSteps;
        winningStepsByDevice.set(
          winner.row.canonDevice,
          (winningStepsByDevice.get(winner.row.canonDevice) ?? 0) + winner.hSteps
        );
        latestActiveHourDevice = winner.row.canonDevice;
      }
    }

    const maxSingleSteps = Math.max(...activeStepPool.map(r => Math.round(r.steps ?? 0)), 0);
    totalSteps = Math.max(mergedHourlySum, maxSingleSteps);

    let mergedKcal = 0;
    let maxSingleKcal = 0;
    for (const item of rowHourlyMaps) {
      const rk = Number(item.row.active_kcal ?? 0);
      if (rk > maxSingleKcal) maxSingleKcal = rk;
      const wonSteps = winningStepsByDevice.get(item.row.canonDevice) ?? 0;
      let rawSum = 0;
      for (const st of item.hMap.values()) rawSum += st;
      const denom = Math.max(rawSum, Math.round(item.row.steps ?? 0), 1);
      if (rk > 0 && wonSteps > 0) {
        mergedKcal += rk * Math.min(1.0, wonSteps / denom);
      }
    }
    activeCal = Math.max(mergedKcal, maxSingleKcal);
    if (activeCal <= 0 && totalSteps > 0) {
      activeCal = Math.round(totalSteps * 0.042 * 10) / 10;
    }

    const topSingleRow = [...activeStepPool].sort((a, b) => (b.steps ?? 0) - (a.steps ?? 0))[0];
    if (
      latestActiveHourDevice &&
      (winningStepsByDevice.get(latestActiveHourDevice) ?? 0) >= 50
    ) {
      activitySourceDevice = latestActiveHourDevice;
    } else {
      activitySourceDevice = topSingleRow?.canonDevice ?? null;
    }
  }

  const activitySummary: ActivitySummary = {
    total_steps: totalSteps,
    active_calories: Math.round(activeCal * 10) / 10,
    source_device: activitySourceDevice,
    hourly_steps: hourlyBuckets
  };

  // 3. Merge Scalar Vitals Across Devices:
  //    - Class C (Baseline/Nocturnal: RHR, HRV, Resp Rate, Skin Temp) -> User Priority first
  //    - Class A (Spot/Live: SpO2, Weight) -> Recency-First (30m simultaneous tie-break window)
  const sortedForBaselineVitals = [...candidateActivityRows].sort((a, b) => {
    const pa = getEffectivePriority(a.canonDevice);
    const pb = getEffectivePriority(b.canonDevice);
    if (pa !== pb) return pa - pb;
    return (b.steps ?? 0) - (a.steps ?? 0);
  });

  const getVitalTsStr = (
    v: (typeof normalizedVitals)[number],
    tsKey: string
  ): string | null => {
    const rawMap = v.vitals_timestamps;
    if (rawMap && typeof rawMap === 'object' && typeof rawMap[tsKey] === 'string' && rawMap[tsKey].length > 0) {
      return rawMap[tsKey];
    }
    return v.updated_at ?? null;
  };

  const vitalsMap: Record<string, VitalSummaryItem> = {};
  const defaultTs = new Date().toISOString();
  const putVitalIfMissing = (
    key: string,
    type: string,
    val: number | null | undefined,
    unit: string,
    device: string,
    ts?: string | null,
    allowZero = false
  ) => {
    if (vitalsMap[key]) return;
    if (val === null || val === undefined) return;
    if (!allowZero && val <= 0) return;
    vitalsMap[key] = {
      type,
      value: Math.round(val * 100) / 100,
      unit,
      source_device: device,
      timestamp: ts || defaultTs
    };
  };

  for (const v of sortedForBaselineVitals) {
    putVitalIfMissing('restingheartrate', 'resting_heart_rate', v.resting_heart_rate, 'bpm', v.canonDevice, getVitalTsStr(v, 'rhr'));
    putVitalIfMissing('hrvsdnn', 'hrv_sdnn', v.hrv_sdnn_nightly, 'ms', v.canonDevice, getVitalTsStr(v, 'hrv'));
    putVitalIfMissing('hrvrmssd', 'hrv_rmssd', v.hrv_rmssd_nightly, 'ms', v.canonDevice, getVitalTsStr(v, 'hrv'));
    putVitalIfMissing('respiratoryrate', 'respiratory_rate', v.respiratory_rate, 'brpm', v.canonDevice, getVitalTsStr(v, 'resp'));
    putVitalIfMissing('bodytemperature', 'body_temperature', v.skin_temp_celsius, '°C', v.canonDevice, getVitalTsStr(v, 'temp'), true);
    putVitalIfMissing('activeenergy', 'active_energy', v.active_kcal, 'kcal', v.canonDevice, v.updated_at);
  }

  const SPOT_TIE_WINDOW_MS = 30 * 60 * 1000;
  const pickSpotVital = (
    mapKey: string,
    type: string,
    unit: string,
    tsKey: string,
    extractor: (v: (typeof normalizedVitals)[number]) => number | null | undefined
  ) => {
    const valid = candidateActivityRows
      .map(v => {
        const val = extractor(v);
        const tsStr = getVitalTsStr(v, tsKey);
        const tsMs = tsStr ? toEpochMs(tsStr) : 0;
        return { v, val, tsStr, tsMs };
      })
      .filter(x => x.val !== null && x.val !== undefined && (x.val as number) > 0);
    if (valid.length === 0) return;
    const newestMs = Math.max(...valid.map(x => x.tsMs));
    const freshPool =
      newestMs > 0
        ? valid.filter(x => newestMs - x.tsMs <= SPOT_TIE_WINDOW_MS)
        : valid;
    freshPool.sort((a, b) => {
      const pa = getEffectivePriority(a.v.canonDevice);
      const pb = getEffectivePriority(b.v.canonDevice);
      if (pa !== pb) return pa - pb;
      return b.tsMs - a.tsMs;
    });
    const win = freshPool[0];
    putVitalIfMissing(mapKey, type, win.val, unit, win.v.canonDevice, win.tsStr);
  };

  pickSpotVital('oxygensaturation', 'oxygen_saturation', '%', 'spo2', v => v.spo2);
  pickSpotVital('weight', 'weight', 'kg', 'weight', v => v.weight_kg);

  // 4. Build Cardiovascular Summary (Class A Recency-First Latest BPM + Active-Wearer Curve)
  const localMidnightMs = getLocalMidnightUtc(targetDate, tzOffsetMin).getTime();
  const rawFilteredHrRows = hrRows
    .map(r => ({
      ...r,
      canonDevice: canonicalizeDeviceName(r.source_device_key, null)
    }))
    .filter(r => r.bpm_avg > 30 && r.bpm_avg < 240 && (!prefCanon || r.canonDevice === prefCanon))
    .sort((a, b) => a.bucket_minute - b.bucket_minute);

  interface DeviceLatestHrCandidate {
    device: string;
    bpm: number;
    tsMs: number;
    tsIso: string;
    maxBucket: number;
  }
  const latestHrByDevice = new Map<string, DeviceLatestHrCandidate>();

  for (const r of rawFilteredHrRows) {
    const bucketWallMs = localMidnightMs + r.bucket_minute * 60 * 1000;
    const prev = latestHrByDevice.get(r.canonDevice);
    if (!prev || r.bucket_minute >= prev.maxBucket) {
      latestHrByDevice.set(r.canonDevice, {
        device: r.canonDevice,
        bpm: r.bpm_avg,
        tsMs: bucketWallMs,
        tsIso: new Date(bucketWallMs).toISOString(),
        maxBucket: r.bucket_minute
      });
    }
  }

  for (const v of candidateActivityRows) {
    const lhr = v.latest_heart_rate ?? 0;
    if (lhr > 30 && lhr < 240 && v.latest_hr_at) {
      const exactMs = toEpochMs(v.latest_hr_at);
      if (exactMs > 0) {
        const prev = latestHrByDevice.get(v.canonDevice);
        if (!prev || exactMs >= prev.tsMs - 5 * 60 * 1000) {
          const approxBucket = Math.max(
            0,
            Math.min(1435, Math.floor((exactMs - localMidnightMs) / (60 * 1000) / 5) * 5)
          );
          latestHrByDevice.set(v.canonDevice, {
            device: v.canonDevice,
            bpm: Math.round(lhr),
            tsMs: exactMs,
            tsIso: new Date(exactMs).toISOString(),
            maxBucket: Math.max(prev?.maxBucket ?? 0, approxBucket)
          });
        }
      }
    }
  }

  const HR_SIMULTANEOUS_WINDOW_MS = 15 * 60 * 1000;
  let winningLatestHr: DeviceLatestHrCandidate | null = null;
  const hrCandidates = Array.from(latestHrByDevice.values());
  if (hrCandidates.length > 0) {
    const newestHrMs = Math.max(...hrCandidates.map(c => c.tsMs));
    const recentHrPool = hrCandidates.filter(c => newestHrMs - c.tsMs <= HR_SIMULTANEOUS_WINDOW_MS);
    recentHrPool.sort((a, b) => {
      const pa = getEffectivePriority(a.device);
      const pb = getEffectivePriority(b.device);
      if (pa !== pb) return pa - pb;
      return b.tsMs - a.tsMs;
    });
    winningLatestHr = recentHrPool[0];
  }

  if (winningLatestHr) {
    putVitalIfMissing(
      'heartrate',
      'heart_rate',
      winningLatestHr.bpm,
      'bpm',
      winningLatestHr.device,
      winningLatestHr.tsIso
    );
  }

  const filteredHrRows: Array<LeanIntradayHrRow & { canonDevice: string }> = (() => {
    if (prefCanon || rawFilteredHrRows.length <= 1) return rawFilteredHrRows;
    const maxBucketPerDevice = new Map<string, number>();
    for (const r of rawFilteredHrRows) {
      const prevMax = maxBucketPerDevice.get(r.canonDevice) ?? -1;
      if (r.bucket_minute > prevMax) maxBucketPerDevice.set(r.canonDevice, r.bucket_minute);
    }

    const byBucket = new Map<number, Array<LeanIntradayHrRow & { canonDevice: string }>>();
    for (const r of rawFilteredHrRows) {
      if (!byBucket.has(r.bucket_minute)) byBucket.set(r.bucket_minute, []);
      byBucket.get(r.bucket_minute)!.push(r);
    }
    const merged: Array<LeanIntradayHrRow & { canonDevice: string }> = [];
    const sortedMinutes = Array.from(byBucket.keys()).sort((a, b) => a - b);
    for (const bm of sortedMinutes) {
      let group = byBucket.get(bm)!;
      if (group.length > 1) {
        const continuing = group.filter(g => (maxBucketPerDevice.get(g.canonDevice) ?? bm) > bm);
        if (continuing.length > 0 && continuing.length < group.length) {
          group = continuing;
        } else if (winningLatestHr && bm === sortedMinutes[sortedMinutes.length - 1]) {
          const winnerInTail = group.filter(g => g.canonDevice === winningLatestHr!.device);
          if (winnerInTail.length > 0) {
            group = winnerInTail;
          }
        }
      }

      if (group.length === 1) {
        merged.push(group[0]);
      } else {
        group.sort((a, b) => getEffectivePriority(a.canonDevice) - getEffectivePriority(b.canonDevice));
        const primary = group[0];
        let wSum = 0;
        let wCnt = 0;
        let minV = 999;
        let maxV = 0;
        for (const g of group) {
          const c = Math.max(1, g.sample_count ?? 1);
          wSum += g.bpm_avg * c;
          wCnt += c;
          const gMin = g.bpm_min > 30 ? g.bpm_min : g.bpm_avg;
          const gMax = g.bpm_max > 30 ? g.bpm_max : g.bpm_avg;
          if (gMin < minV) minV = gMin;
          if (gMax > maxV) maxV = gMax;
        }
        merged.push({
          ...primary,
          bpm_avg: Math.round(wSum / Math.max(1, wCnt)),
          bpm_min: minV < 999 ? minV : primary.bpm_avg,
          bpm_max: maxV > 0 ? maxV : primary.bpm_avg,
          sample_count: wCnt
        });
      }
    }
    return merged;
  })();

  const archivedPts =
    filteredHrRows.length === 0 &&
    !prefCanon &&
    archivedCardiovascular &&
    Array.isArray(archivedCardiovascular.intraday_points) &&
    archivedCardiovascular.intraday_points.length > 0
      ? archivedCardiovascular.intraday_points.filter(p => p && p.bpm > 30 && p.bpm < 240)
      : [];

  const intradayHrPoints: IntradayHeartRatePoint[] =
    filteredHrRows.length > 0
      ? filteredHrRows.map(r => {
          const tsIso = new Date(localMidnightMs + r.bucket_minute * 60 * 1000).toISOString();
          return {
            id: r.id,
            timestamp: tsIso,
            bpm: r.bpm_avg,
            zone: mapHeartRateZone(r.bpm_avg),
            source_device: r.canonDevice
          };
        })
      : archivedPts.map(p => ({
          id: p.id,
          timestamp: p.timestamp,
          bpm: p.bpm,
          zone: p.zone || mapHeartRateZone(p.bpm),
          source_device: p.source_device ? canonicalizeDeviceName(p.source_device, null) : null
        }));

  if (!winningLatestHr && archivedPts.length > 0 && archivedCardiovascular) {
    const tailPt = archivedPts[archivedPts.length - 1];
    const archBpm = archivedCardiovascular.latest_bpm ?? tailPt.bpm;
    const archIso = archivedCardiovascular.latest_bpm_at ?? tailPt.timestamp;
    const archDev = archivedCardiovascular.latest_source_device ?? tailPt.source_device ?? 'Wearable';
    if (archBpm > 30 && archIso) {
      putVitalIfMissing(
        'heartrate',
        'heart_rate',
        archBpm,
        'bpm',
        canonicalizeDeviceName(archDev, null),
        archIso
      );
    }
  }

  if (winningLatestHr) {
    const lastPt = intradayHrPoints.length > 0 ? intradayHrPoints[intradayHrPoints.length - 1] : null;
    const lastPtMs = lastPt ? toEpochMs(lastPt.timestamp) : 0;
    if (!lastPt || winningLatestHr.tsMs > lastPtMs + 60 * 1000) {
      intradayHrPoints.push({
        id: `hr_live_${userId}_${targetDate}`,
        timestamp: winningLatestHr.tsIso,
        bpm: winningLatestHr.bpm,
        zone: mapHeartRateZone(winningLatestHr.bpm),
        source_device: winningLatestHr.device
      });
    } else if (lastPt && lastPt.source_device === winningLatestHr.device) {
      lastPt.bpm = winningLatestHr.bpm;
      lastPt.zone = mapHeartRateZone(winningLatestHr.bpm);
      lastPt.timestamp = winningLatestHr.tsIso;
    }
  }

  const measuredRhr = vitalsMap['restingheartrate']?.value ?? null;
  const derivedAllRhr = deriveNocturnalRhrFromHrPoints(intradayHrPoints, targetDate, tzOffsetMin);
  let cardioSummary: CardiovascularSummary;
  if (filteredHrRows.length === 0 && archivedPts.length > 0 && archivedCardiovascular) {
    const fallbackTail = intradayHrPoints[intradayHrPoints.length - 1];
    const effectiveRhr = measuredRhr !== null && measuredRhr > 0
      ? Math.round(measuredRhr)
      : (archivedCardiovascular.resting_bpm ?? (derivedAllRhr !== null ? Math.round(derivedAllRhr) : null));
    cardioSummary = {
      latest_bpm: winningLatestHr?.bpm ?? archivedCardiovascular.latest_bpm ?? fallbackTail?.bpm ?? null,
      latest_bpm_at: winningLatestHr?.tsIso ?? archivedCardiovascular.latest_bpm_at ?? fallbackTail?.timestamp ?? null,
      latest_source_device: winningLatestHr?.device ?? archivedCardiovascular.latest_source_device ?? fallbackTail?.source_device ?? null,
      average_bpm: archivedCardiovascular.average_bpm,
      resting_bpm: effectiveRhr,
      min_bpm: archivedCardiovascular.min_bpm,
      max_bpm: archivedCardiovascular.max_bpm,
      zones: archivedCardiovascular.zones ?? { resting: 0, fat_burn: 0, cardio: 0, peak: 0 },
      intraday_points: intradayHrPoints
    };
  } else if (filteredHrRows.length === 0 && intradayHrPoints.length === 0) {
    cardioSummary = {
      latest_bpm: winningLatestHr?.bpm ?? null,
      latest_bpm_at: winningLatestHr?.tsIso ?? null,
      latest_source_device: winningLatestHr?.device ?? null,
      average_bpm: winningLatestHr?.bpm ?? null,
      resting_bpm: measuredRhr !== null ? Math.round(measuredRhr) : null,
      min_bpm: winningLatestHr?.bpm ?? null,
      max_bpm: winningLatestHr?.bpm ?? null,
      zones: { resting: 0, fat_burn: 0, cardio: 0, peak: 0 },
      intraday_points: []
    };
  } else {
    let weightedSum = 0;
    let totalSamples = 0;
    let minBpm = 999;
    let maxBpm = 0;
    const zones = { resting: 0, fat_burn: 0, cardio: 0, peak: 0 };

    const rowsForStats =
      filteredHrRows.length > 0
        ? filteredHrRows
        : intradayHrPoints.map(p => ({
            bpm_avg: p.bpm,
            bpm_min: p.bpm,
            bpm_max: p.bpm,
            sample_count: 1
          }));

    for (const r of rowsForStats) {
      const cnt = Math.max(1, r.sample_count ?? 1);
      weightedSum += r.bpm_avg * cnt;
      totalSamples += cnt;
      const bMin = r.bpm_min > 30 ? r.bpm_min : r.bpm_avg;
      const bMax = r.bpm_max > 30 ? r.bpm_max : r.bpm_avg;
      if (bMin < minBpm) minBpm = bMin;
      if (bMax > maxBpm) maxBpm = bMax;

      const z = mapHeartRateZone(r.bpm_avg);
      if (z === 'Resting') zones.resting++;
      else if (z === 'Fat Burn') zones.fat_burn++;
      else if (z === 'Cardio') zones.cardio++;
      else if (z === 'Peak') zones.peak++;
    }

    if (winningLatestHr) {
      if (winningLatestHr.bpm < minBpm) minBpm = winningLatestHr.bpm;
      if (winningLatestHr.bpm > maxBpm) maxBpm = winningLatestHr.bpm;
    }

    const avgBpm = Math.round((weightedSum / Math.max(1, totalSamples)) * 10) / 10;
    const effectiveRhr = measuredRhr !== null && measuredRhr > 0
      ? Math.round(measuredRhr)
      : derivedAllRhr !== null
        ? Math.round(derivedAllRhr)
        : (minBpm < 999 ? minBpm + 4 : null);

    const fallbackTail = intradayHrPoints.length > 0 ? intradayHrPoints[intradayHrPoints.length - 1] : null;

    cardioSummary = {
      latest_bpm: winningLatestHr?.bpm ?? fallbackTail?.bpm ?? null,
      latest_bpm_at: winningLatestHr?.tsIso ?? fallbackTail?.timestamp ?? null,
      latest_source_device: winningLatestHr?.device ?? fallbackTail?.source_device ?? null,
      average_bpm: avgBpm,
      resting_bpm: effectiveRhr,
      min_bpm: minBpm < 999 ? Math.round(minBpm) : null,
      max_bpm: maxBpm > 0 ? Math.round(maxBpm) : null,
      zones,
      intraday_points: intradayHrPoints
    };
  }

  // 5. Compute Rolling Personal Baselines & Per-Sensor RHR Map for Autonomic Stress
  const rollingSdnn = computeRollingMedianOrMean(
    historyVitalsRows.map(h => h.hrv_sdnn_nightly ?? 0).filter(v => v > 0 && v <= 120)
  );
  const rmssdSourceDevice = vitalsMap['hrvrmssd']?.source_device;
  const sameDeviceRmssdHistory = rmssdSourceDevice
    ? historyVitalsRows
        .filter(h => canonicalizeDeviceName(h.source_device_key, h.host_device_name) === rmssdSourceDevice)
        .map(h => h.hrv_rmssd_nightly ?? 0)
        .filter(v => v >= 35)
    : [];
  const rollingRmssd =
    computeRollingMedianOrMean(sameDeviceRmssdHistory) ??
    computeRollingMedianOrMean(
      historyVitalsRows.map(h => h.hrv_rmssd_nightly ?? 0).filter(v => v >= 35)
    );
  const rollingRhr = computeRollingMedianOrMean(
    historyVitalsRows.map(h => h.resting_heart_rate ?? 0).filter(v => v >= 40 && v <= 95)
  );

  const perDeviceRhrMap: Record<string, number> = {};
  for (const src of orderedSources) {
    const dv = normalizedVitals.find(v => v.canonDevice === src && (v.resting_heart_rate ?? 0) >= 40 && (v.resting_heart_rate ?? 0) <= 98);
    if (dv && dv.resting_heart_rate) {
      perDeviceRhrMap[src] = dv.resting_heart_rate;
    } else {
      const devHistRhr = computeRollingMedianOrMean(
        historyVitalsRows
          .filter(h => canonicalizeDeviceName(h.source_device_key, h.host_device_name) === src)
          .map(h => h.resting_heart_rate ?? 0)
          .filter(v => v >= 40 && v <= 95)
      );
      if (devHistRhr) {
        perDeviceRhrMap[src] = devHistRhr;
      }
    }
  }

  const hasSdnnToday = (vitalsMap['hrvsdnn']?.value ?? 0) > 0;
  const hasRmssdToday = !hasSdnnToday && (vitalsMap['hrvrmssd']?.value ?? 0) > 0;
  const hrvVal = hasSdnnToday
    ? vitalsMap['hrvsdnn']!.value
    : hasRmssdToday
      ? vitalsMap['hrvrmssd']!.value
      : null;
  const effectiveBaselineHrv =
    baselineHrvMs ?? (hasRmssdToday ? rollingRmssd : rollingSdnn);
  const effectiveBaselineRhr = baselineRhrBpm ?? rollingRhr;

  const stressSummary = computeStress({
    targetDateStr: targetDate,
    tzOffsetMin,
    hrvMs: hrvVal,
    isRmssd: hasRmssdToday,
    hrPoints: cardioSummary.intraday_points,
    hourlySteps: activitySummary.hourly_steps,
    restingBpm: cardioSummary.resting_bpm,
    priorSleepScore: primarySession ? primarySession.sleep_score : null,
    personalBaselineHrv: effectiveBaselineHrv,
    personalBaselineRhr: effectiveBaselineRhr,
    perDeviceRhrMap,
    sourceDevice: cardioSummary.latest_source_device ?? vitalsMap['hrvsdnn']?.source_device ?? vitalsMap['hrvrmssd']?.source_device ?? primarySession?.source_device ?? null
  });

  // 6. Build Rich Per-Device Breakdown (including coherent per-device Stress v2.0!) & All-Devices View
  const sourcesBreakdown: Record<string, Record<string, number>> = {};
  for (const src of orderedSources) {
    sourcesBreakdown[src] = {};
  }
  for (const v of normalizedVitals) {
    if (!vitalsRowHasSignal(v)) continue;
    if (!sourcesBreakdown[v.canonDevice]) sourcesBreakdown[v.canonDevice] = {};
    const b = sourcesBreakdown[v.canonDevice];
    if ((v.steps ?? 0) > 0) b['steps'] = v.steps!;
    if ((v.active_kcal ?? 0) > 0) b['active_calories'] = Math.round(v.active_kcal! * 10) / 10;
    if ((v.latest_heart_rate ?? 0) > 0) b['latest_heart_rate'] = v.latest_heart_rate!;
    if ((v.resting_heart_rate ?? 0) > 0) b['resting_heart_rate'] = v.resting_heart_rate!;
    if ((v.hrv_sdnn_nightly ?? 0) > 0) b['hrv_sdnn'] = v.hrv_sdnn_nightly!;
    if ((v.hrv_rmssd_nightly ?? 0) > 0) b['hrv_rmssd'] = v.hrv_rmssd_nightly!;
    if ((v.spo2 ?? 0) > 0) b['spo2'] = v.spo2!;
    if ((v.respiratory_rate ?? 0) > 0) b['respiratory_rate'] = v.respiratory_rate!;
    if (v.skin_temp_celsius !== null && v.skin_temp_celsius !== undefined) b['skin_temp_celsius'] = v.skin_temp_celsius;
    if ((v.weight_kg ?? 0) > 0) b['weight_kg'] = v.weight_kg!;
  }
  for (const c of hrCandidates) {
    if (!sourcesBreakdown[c.device]) sourcesBreakdown[c.device] = {};
    if (!sourcesBreakdown[c.device]['latest_heart_rate']) {
      sourcesBreakdown[c.device]['latest_heart_rate'] = c.bpm;
    }
  }
  for (const s of allSessions) {
    if (!sourcesBreakdown[s.source_device]) sourcesBreakdown[s.source_device] = {};
    sourcesBreakdown[s.source_device]['sleep_asleep_seconds'] = s.asleep_seconds;
    sourcesBreakdown[s.source_device]['sleep_score'] = s.sleep_score;
  }

  for (const src of orderedSources) {
    const devVitals = normalizedVitals.find(v => v.canonDevice === src);
    const devSleep = allSessions.find(s => s.source_device === src);
    const devHrPoints: IntradayHeartRatePoint[] =
      rawFilteredHrRows.length > 0
        ? rawFilteredHrRows
            .filter(r => r.canonDevice === src)
            .map(r => ({
              id: r.id,
              timestamp: new Date(localMidnightMs + r.bucket_minute * 60 * 1000).toISOString(),
              bpm: r.bpm_avg,
              zone: mapHeartRateZone(r.bpm_avg),
              source_device: src
            }))
        : archivedPts.filter(p => p.source_device && canonicalizeDeviceName(p.source_device, null) === src);

    const devHasSdnn = (devVitals?.hrv_sdnn_nightly ?? 0) > 0;
    const devHasRmssd = !devHasSdnn && (devVitals?.hrv_rmssd_nightly ?? 0) > 0;
    const devHrv = devHasSdnn
      ? devVitals!.hrv_sdnn_nightly!
      : devHasRmssd
        ? devVitals!.hrv_rmssd_nightly!
        : null;

    const devHistRows = historyVitalsRows.filter(
      h => canonicalizeDeviceName(h.source_device_key, h.host_device_name) === src
    );
    const devBaseSdnn =
      computeRollingMedianOrMean(devHistRows.map(h => h.hrv_sdnn_nightly ?? 0).filter(v => v > 0 && v <= 120)) ?? rollingSdnn;
    const devBaseRmssd =
      computeRollingMedianOrMean(devHistRows.map(h => h.hrv_rmssd_nightly ?? 0).filter(v => v >= 35)) ?? rollingRmssd;
    const devBaseRhr =
      computeRollingMedianOrMean(devHistRows.map(h => h.resting_heart_rate ?? 0).filter(v => v >= 40 && v <= 95)) ?? rollingRhr;

    const devHourlySteps: HourlyStepBucket[] = Array.isArray(devVitals?.hourly_steps)
      ? devVitals!.hourly_steps!
      : [];

    const devStress = computeStress({
      targetDateStr: targetDate,
      tzOffsetMin,
      hrvMs: devHrv,
      isRmssd: devHasRmssd,
      hrPoints: devHrPoints,
      hourlySteps: devHourlySteps,
      restingBpm: (devVitals?.resting_heart_rate ?? 0) > 0 ? devVitals!.resting_heart_rate! : null,
      priorSleepScore: devSleep ? devSleep.sleep_score : null,
      personalBaselineHrv: devHasRmssd ? devBaseRmssd : devBaseSdnn,
      personalBaselineRhr: devBaseRhr,
      sourceDevice: src
    });

    if (devStress) {
      if (!sourcesBreakdown[src]) sourcesBreakdown[src] = {};
      sourcesBreakdown[src]['stress_score'] = devStress.current_score;
      sourcesBreakdown[src]['stress_daily_avg'] = devStress.daily_average;
      if (!sourcesBreakdown[src]['resting_heart_rate'] && devStress.resting_heart_rate_bpm) {
        sourcesBreakdown[src]['derived_rhr'] = devStress.resting_heart_rate_bpm;
      }
    }
  }

  const allDevicesView: Record<string, any> = {};
  if (activitySummary.total_steps > 0 && activitySummary.source_device) {
    allDevicesView['steps'] = {
      value: activitySummary.total_steps,
      source_key: activitySummary.source_device,
      source_color: getCanonicalDeviceColor(activitySummary.source_device)
    };
  }
  if (primarySession && primarySession.asleep_seconds > 0) {
    allDevicesView['sleep_duration_seconds'] = {
      value: primarySession.asleep_seconds,
      source_key: primarySession.source_device,
      source_color: getCanonicalDeviceColor(primarySession.source_device),
      score: primarySession.sleep_score
    };
  }
  if (cardioSummary.latest_bpm && cardioSummary.latest_bpm > 0 && cardioSummary.latest_source_device) {
    allDevicesView['heart_rate'] = {
      value: cardioSummary.latest_bpm,
      source_key: cardioSummary.latest_source_device,
      source_color: getCanonicalDeviceColor(cardioSummary.latest_source_device),
      timestamp: cardioSummary.latest_bpm_at ?? undefined
    };
  }
  if (cardioSummary.resting_bpm && cardioSummary.resting_bpm > 0) {
    const rhrSrc = vitalsMap['restingheartrate']?.source_device || primarySession?.source_device || orderedSources[0] || 'Wearable';
    allDevicesView['resting_heart_rate'] = {
      value: cardioSummary.resting_bpm,
      source_key: rhrSrc,
      source_color: getCanonicalDeviceColor(rhrSrc)
    };
  }
  if (activitySummary.active_calories > 0 && activitySummary.source_device) {
    allDevicesView['active_calories'] = {
      value: activitySummary.active_calories,
      source_key: activitySummary.source_device,
      source_color: getCanonicalDeviceColor(activitySummary.source_device)
    };
  }
  if (stressSummary) {
    const stressSrc =
      stressSummary.source_device ||
      cardioSummary.latest_source_device ||
      vitalsMap['hrvsdnn']?.source_device ||
      vitalsMap['hrvrmssd']?.source_device ||
      primarySession?.source_device ||
      'Biometric Engine';
    allDevicesView['stress'] = {
      value: stressSummary.current_score,
      source_key: stressSrc,
      source_color: getCanonicalDeviceColor(stressSrc),
      score: stressSummary.current_score
    };
  }

  const computedAt = new Date().toISOString();
  const payload: DailyHealthSummaryPayload = {
    date: targetDate,
    engine_version: 'v2.0',
    computed_at: computedAt,
    sources: orderedSources,
    all_devices_view: allDevicesView,
    sources_breakdown: sourcesBreakdown,
    sleep: {
      primary_session: primarySession,
      all_sessions: allSessions,
      naps,
      guidance: sleepGuidance
    },
    activity: activitySummary,
    cardiovascular: cardioSummary,
    stress: stressSummary,
    vitals: vitalsMap
  };

  return {
    user_id: userId,
    local_date: targetDate,
    computed_at: computedAt,
    engine_version: 'v2.0',
    raw_watermark: computedAt,
    steps: activitySummary.total_steps > 0 ? activitySummary.total_steps : null,
    active_kcal: activitySummary.active_calories > 0 ? activitySummary.active_calories : null,
    sleep_asleep_s: primarySession
      ? primarySession.asleep_seconds
      : (naps.length > 0 ? naps.reduce((sum, n) => sum + n.duration_seconds, 0) : null),
    sleep_score: primarySession ? primarySession.sleep_score : null,
    stress_avg: stressSummary ? stressSummary.daily_average : null,
    rhr: cardioSummary.resting_bpm,
    hrv_sdnn: vitalsMap['hrvsdnn']?.value ?? null,
    hrv_rmssd: vitalsMap['hrvrmssd']?.value ?? null,
    weight: vitalsMap['weight']?.value ?? null,
    spo2: vitalsMap['oxygensaturation']?.value ?? null,
    summary: payload
  };
}
