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
  HealthDailySummaryRow
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

export function generateSleepGuidance(session: SleepSession | null): SleepGuidance | null {
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

  const verdict: SleepRecoveryVerdict = {
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
    const lower = device.toLowerCase();
    const isPhone = lower.includes('phone') || lower.includes('pixel') || lower.includes('galaxy') || lower.includes('handset');
    const isWearable = !isPhone && (
      lower.includes('watch') ||
      lower.includes('apple') ||
      lower.includes('balance') ||
      lower.includes('amazfit') ||
      lower.includes('gt5') ||
      lower.includes('oura') ||
      lower.includes('fitbit') ||
      lower.includes('garmin') ||
      lower.includes('whoop') ||
      lower.includes('polar') ||
      lower.includes('huawei') ||
      (lower.includes('health') && !lower.includes('phone'))
    );

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
// 5. Autonomic Nervous System & Stress Engine
// ==========================================

export function scoreFromHrv(hrv: number, baseline: number): number {
  if (baseline <= 0) return 50.0;
  const z = (hrv - baseline) / 16.0;
  // tanh(z) transfer function: high HRV -> low stress (< 30), depressed HRV -> high stress (> 70)
  const normalized = 50.0 - Math.tanh(z) * 45.0;
  return Math.min(100.0, Math.max(0.0, normalized));
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
  hrPoints: IntradayHeartRatePoint[];
  hourlySteps: HourlyStepBucket[];
  restingBpm: number | null;
  priorSleepScore: number | null;
  personalBaselineHrv?: number;
  personalBaselineRhr?: number;
}): StressSummary | null {
  const {
    targetDateStr,
    tzOffsetMin,
    hrvMs,
    hrPoints,
    hourlySteps,
    restingBpm,
    priorSleepScore,
    personalBaselineHrv,
    personalBaselineRhr
  } = params;

  // Valid stress calculation requires genuine physiological signal (HRV or heart rate samples)
  if (hrvMs === null && hrPoints.length === 0) {
    return null;
  }

  const baselineHrv = personalBaselineHrv ?? 45.0;
  const baselineRhr = restingBpm ?? personalBaselineRhr ?? 62.0;
  const sleepScore = priorSleepScore ?? 80;

  // Build map of steps by hour
  const stepsByHour = new Map<number, number>();
  for (const b of hourlySteps) {
    stepsByHour.set(b.hour, b.steps);
  }

  // Group HR telemetry by local hour
  const hrByHour = new Map<number, number[]>();
  for (const pt of hrPoints) {
    const s = parseUtcDate(pt.timestamp);
    if (isSameLocalDate(s, targetDateStr, tzOffsetMin)) {
      const h = getLocalHour(s, tzOffsetMin);
      if (!hrByHour.has(h)) hrByHour.set(h, []);
      hrByHour.get(h)!.push(pt.bpm);
    }
  }

  const intradayPoints: IntradayStressPoint[] = [];
  const sleepPenalty = Math.max(0.0, Math.min(100.0, 100.0 - sleepScore));

  for (let hour = 0; hour < 24; hour++) {
    const steps = stepsByHour.get(hour) ?? 0;
    const isSedentary = steps < 300;

    const hrSamples = hrByHour.get(hour) ?? [];
    if (hrSamples.length === 0 && (hrvMs === null || steps === 0)) {
      continue;
    }

    const avgHr = hrSamples.length > 0 ? hrSamples.reduce((a, b) => a + b, 0) / hrSamples.length : null;
    const hourHrv = hrvMs ?? baselineHrv;

    // A. HRV Component (50%)
    const hrvScore = scoreFromHrv(hourHrv, baselineHrv);

    // B. HR Elevation Component (30%)
    let hrScore: number;
    if (avgHr !== null && isSedentary) {
      const delta = Math.max(0.0, avgHr - baselineRhr);
      hrScore = Math.min(100.0, (delta / 25.0) * 100.0);
    } else {
      hrScore = hrvScore * 0.8;
    }

    // C. Blended hourly stress
    const rawHourly = 0.5 * hrvScore + 0.3 * hrScore + 0.2 * sleepPenalty;
    const finalScore = Math.round(Math.min(98.0, Math.max(5.0, rawHourly)));
    const level = mapStressLevel(finalScore);

    const hourMidnight = getLocalMidnightUtc(targetDateStr, tzOffsetMin);
    const hourTimestamp = new Date(hourMidnight.getTime() + hour * 3600 * 1000).toISOString();

    intradayPoints.push({
      timestamp: hourTimestamp,
      hour,
      score: finalScore,
      level,
      hrv_ms: hourHrv,
      heart_rate_bpm: avgHr !== null ? Math.round(avgHr * 10) / 10 : null,
      is_sedentary: isSedentary
    });
  }

  // Resolve current / master stress score
  let currentScore: number;
  const currentHrv = hrvMs ?? baselineHrv;
  const currentHrvScore = scoreFromHrv(currentHrv, baselineHrv);

  const lastHr = hrPoints.length > 0 ? hrPoints[hrPoints.length - 1].bpm : null;
  let currentElevation: number | null = null;
  let currentHrScore: number;
  if (lastHr !== null) {
    currentElevation = Math.max(0.0, lastHr - baselineRhr);
    currentHrScore = Math.min(100.0, (currentElevation / 25.0) * 100.0);
  } else {
    currentHrScore = currentHrvScore * 0.8;
  }

  if (intradayPoints.length > 0) {
    currentScore = intradayPoints[intradayPoints.length - 1].score;
  } else {
    const blended = 0.5 * currentHrvScore + 0.3 * currentHrScore + 0.2 * sleepPenalty;
    currentScore = Math.round(Math.min(95.0, Math.max(10.0, blended)));
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
    resting_heart_rate_bpm: Math.round(baselineRhr),
    current_sedentary_bpm: lastHr !== null ? Math.round(lastHr) : null,
    heart_rate_elevation_bpm: currentElevation !== null ? Math.round(currentElevation * 10) / 10 : null,
    monkey_mood: monkeyMood,
    advice_quote: adviceQuote,
    recommended_breathing: recommendedBreathing,
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
  const sleepGuidance = generateSleepGuidance(sleepResult.primarySession);

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
