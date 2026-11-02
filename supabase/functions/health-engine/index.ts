// Supabase Edge Function: health-engine
// Canonical Daily Health & Vitals Engine v1.0
// Runs server-side on Deno runtime in Supabase Edge Functions.

// @ts-ignore: Resolved via deno.json or npm
import { createClient } from '@supabase/supabase-js';
import {
  computeDailyHealthSummary,
  getLocalMidnightUtc
} from './engine.ts';
import type { HealthTelemetryRow } from './types.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
};

// @ts-ignore: Deno is defined in Supabase Edge Function runtime
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // @ts-ignore: Deno is defined in runtime
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    // @ts-ignore: Deno is defined in runtime
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: 'Supabase environment variables not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let userId: string | null = null;
    let targetDate: string | null = null;
    let tzOffsetMin = 0;
    let preferredDevice: string | undefined = undefined;
    let processDirty = false;

    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      userId = body.user_id || body.userId;
      targetDate = body.date || body.local_date;
      tzOffsetMin = body.tz_offset_min ?? body.tzOffsetMin ?? 0;
      preferredDevice = body.preferred_device || body.preferredDevice;
      processDirty = body.process_dirty === true;
    } else if (req.method === 'GET') {
      const url = new URL(req.url);
      userId = url.searchParams.get('user_id');
      targetDate = url.searchParams.get('date');
      const tzParam = url.searchParams.get('tz_offset_min');
      if (tzParam !== null) tzOffsetMin = parseInt(tzParam, 10) || 0;
      preferredDevice = url.searchParams.get('preferred_device') || undefined;
      processDirty = url.searchParams.get('process_dirty') === 'true';
    }

    // Mode A: Process next batch of dirty days from health_day_dirty
    if (processDirty && (!userId || !targetDate)) {
      let query = supabase.from('health_day_dirty').select('user_id, local_date');
      if (userId) {
        query = query.eq('user_id', userId);
      }
      const { data: dirtyRows, error: dirtyErr } = await query
        .order('dirty_since', { ascending: true })
        .limit(10);

      if (dirtyErr) {
        return new Response(JSON.stringify({ error: dirtyErr.message }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const results = [];
      for (const d of dirtyRows || []) {
        const rowRes = await processDayForUser(
          supabase,
          d.user_id,
          d.local_date,
          tzOffsetMin,
          preferredDevice
        );
        results.push(rowRes);
      }

      // Apply retention policy during dirty batch processing
      try {
        await supabase.rpc('apply_health_data_retention');
      } catch (e: any) {
        console.warn('Retention RPC execution notice:', e);
      }

      return new Response(JSON.stringify({ processed_count: results.length, results }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (!userId || !targetDate) {
      return new Response(
        JSON.stringify({ error: 'Missing required parameters: user_id and date (YYYY-MM-DD)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const result = await processDayForUser(
      supabase,
      userId,
      targetDate,
      tzOffsetMin,
      preferredDevice
    );

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});

async function processDayForUser(
  supabase: any,
  userId: string,
  targetDate: string,
  tzOffsetMin: number,
  preferredDevice?: string
) {
  const targetMidnight = getLocalMidnightUtc(targetDate, tzOffsetMin);
  // Sleep window starts D-1 18:00 (-6h)
  const windowStartIso = new Date(targetMidnight.getTime() - 6 * 3600 * 1000).toISOString();
  // Day window ends D 23:59:59.999 (+24h)
  const windowEndIso = new Date(targetMidnight.getTime() + 24 * 3600 * 1000 - 1).toISOString();

  // 1. Fetch raw telemetry within the full window for this user using chunked range pagination
  // (PostgREST server caps at 1000 rows/request, so range pagination is mandatory to prevent truncation)
  const pageSize = 1000;
  let page = 0;
  const telemetryRows: any[] = [];

  while (true) {
    const from = page * pageSize;
    const to = from + pageSize - 1;
    const { data: batch, error: telemErr } = await supabase
      .from('health_telemetry')
      .select('*')
      .eq('user_id', userId)
      .gte('start_time', windowStartIso)
      .lte('start_time', windowEndIso)
      .order('start_time', { ascending: true })
      .range(from, to);

    if (telemErr) {
      console.error(`[health-engine] Error fetching telemetry page ${page}:`, telemErr);
      break;
    }

    if (!batch || batch.length === 0) {
      break;
    }

    telemetryRows.push(...batch);

    if (batch.length < pageSize) {
      break;
    }

    page++;
    if (page > 30) break; // Safety threshold (up to 30,000 records)
  }

  if (!telemetryRows || telemetryRows.length === 0) {
    // 1. Check if lean tables (health_daily_vitals or health_sleep_sessions) have data for this day
    const { data: vitalsRows } = await supabase
      .from('health_daily_vitals')
      .select('*')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .order('updated_at', { ascending: false });

    const { data: sleepRows } = await supabase
      .from('health_sleep_sessions')
      .select('*')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .order('source_priority', { ascending: true });

    const primaryVital = vitalsRows && vitalsRows.length > 0 ? vitalsRows[0] : null;
    const primarySleep = sleepRows && sleepRows.length > 0 ? sleepRows[0] : null;

    if (primaryVital || primarySleep) {
      // Fetch any existing summary to merge with
      const { data: existingSummary } = await supabase
        .from('health_daily_summary')
        .select('*')
        .eq('user_id', userId)
        .eq('local_date', targetDate)
        .maybeSingle();

      const mergedSummary = existingSummary?.summary || {};
      if (primarySleep) {
        mergedSummary.sleep = {
          duration_seconds: primarySleep.duration_seconds,
          efficiency_percent: primarySleep.efficiency_percent,
          sleep_score: primarySleep.sleep_score,
          deep_seconds: primarySleep.deep_seconds,
          rem_seconds: primarySleep.rem_seconds,
          light_seconds: primarySleep.light_seconds,
          awake_seconds: primarySleep.awake_seconds,
          start_time: primarySleep.start_time,
          end_time: primarySleep.end_time,
          source_device: primarySleep.source_device_key,
          stages: primarySleep.stages || []
        };
      }
      if (primaryVital) {
        mergedSummary.vitals = {
          steps: primaryVital.steps,
          active_calories: primaryVital.active_kcal,
          resting_heart_rate: primaryVital.resting_heart_rate,
          hrv_rmssd: primaryVital.hrv_rmssd_nightly,
          hrv_sdnn: primaryVital.hrv_sdnn_nightly,
          spo2: primaryVital.spo2,
          respiratory_rate: primaryVital.respiratory_rate,
          source_device: primaryVital.source_device_key
        };
      }

      await supabase
        .from('health_daily_summary')
        .upsert(
          {
            user_id: userId,
            local_date: targetDate,
            computed_at: new Date().toISOString(),
            engine_version: 2,
            raw_watermark: new Date().toISOString(),
            steps: primaryVital?.steps ?? existingSummary?.steps ?? null,
            active_kcal: primaryVital?.active_kcal ?? existingSummary?.active_kcal ?? null,
            sleep_asleep_s: primarySleep?.duration_seconds ?? existingSummary?.sleep_asleep_s ?? null,
            sleep_score: primarySleep?.sleep_score ?? existingSummary?.sleep_score ?? null,
            stress_avg: existingSummary?.stress_avg ?? null,
            rhr: primaryVital?.resting_heart_rate ?? existingSummary?.rhr ?? null,
            hrv_sdnn: primaryVital?.hrv_sdnn_nightly ?? existingSummary?.hrv_sdnn ?? null,
            hrv_rmssd: primaryVital?.hrv_rmssd_nightly ?? existingSummary?.hrv_rmssd ?? null,
            weight: primaryVital?.weight_kg ?? existingSummary?.weight ?? null,
            spo2: primaryVital?.spo2 ?? existingSummary?.spo2 ?? null,
            summary: mergedSummary
          },
          { onConflict: 'user_id,local_date' }
        );

      await supabase
        .from('health_day_dirty')
        .delete()
        .eq('user_id', userId)
        .eq('local_date', targetDate);

      return { success: true, date: targetDate, synthesized_from_lean: true };
    }

    // 2. If neither lean records exist, check if an existing summary exists and preserve it
    const { data: existingSummary } = await supabase
      .from('health_daily_summary')
      .select('steps, sleep_asleep_s')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .maybeSingle();

    if (existingSummary && (existingSummary.steps !== null || existingSummary.sleep_asleep_s !== null)) {
      await supabase
        .from('health_day_dirty')
        .delete()
        .eq('user_id', userId)
        .eq('local_date', targetDate);
      return { success: true, date: targetDate, preserved: true };
    }

    // 3. Otherwise drain from dirty queue to prevent infinite retry loops
    await supabase
      .from('health_day_dirty')
      .delete()
      .eq('user_id', userId)
      .eq('local_date', targetDate);
    return { success: true, date: targetDate, empty: true };
  }

  // Infer effective timezone if caller did not supply one (0) but telemetry records contain it
  let effectiveTz = tzOffsetMin;
  if (effectiveTz === 0 && telemetryRows && telemetryRows.length > 0) {
    const rowWithTz = telemetryRows.find((r: any) => r.tz_offset_min !== null && r.tz_offset_min !== undefined && r.tz_offset_min !== 0);
    if (rowWithTz) {
      effectiveTz = rowWithTz.tz_offset_min;
    }
  }

  // 2. Run the deterministic Canonical Health Engine
  const summaryRow = computeDailyHealthSummary({
    userId,
    targetDate,
    telemetry: (telemetryRows || []) as HealthTelemetryRow[],
    tzOffsetMin: effectiveTz,
    preferredDevice
  });

  // Check if lean vitals/sleep have better/supplemental data than the raw engine output
  const { data: vitalsRows } = await supabase
    .from('health_daily_vitals')
    .select('*')
    .eq('user_id', userId)
    .eq('local_date', targetDate)
    .order('updated_at', { ascending: false });

  const { data: sleepRows } = await supabase
    .from('health_sleep_sessions')
    .select('*')
    .eq('user_id', userId)
    .eq('local_date', targetDate)
    .order('source_priority', { ascending: true });

  const primaryVital = vitalsRows && vitalsRows.length > 0 ? vitalsRows[0] : null;
  const primarySleep = sleepRows && sleepRows.length > 0 ? sleepRows[0] : null;

  const finalSteps = summaryRow.steps ?? primaryVital?.steps ?? null;
  const finalActiveKcal = summaryRow.active_kcal ?? primaryVital?.active_kcal ?? null;
  const finalSleepAsleep = summaryRow.sleep_asleep_s ?? primarySleep?.duration_seconds ?? null;
  const finalSleepScore = summaryRow.sleep_score ?? primarySleep?.sleep_score ?? null;
  const finalRhr = summaryRow.rhr ?? primaryVital?.resting_heart_rate ?? null;
  const finalHrvSdnn = summaryRow.hrv_sdnn ?? primaryVital?.hrv_sdnn_nightly ?? null;
  const finalHrvRmssd = summaryRow.hrv_rmssd ?? primaryVital?.hrv_rmssd_nightly ?? null;
  const finalSpo2 = summaryRow.spo2 ?? primaryVital?.spo2 ?? null;
  const finalStress = summaryRow.stress_avg ?? null;

  const finalSummaryPayload = summaryRow.summary || {};
  if (primarySleep && (!finalSummaryPayload.sleep?.primary_session || finalSummaryPayload.sleep.primary_session.duration_seconds === 0)) {
    finalSummaryPayload.sleep = {
      ...(finalSummaryPayload.sleep || {}),
      duration_seconds: primarySleep.duration_seconds,
      efficiency_percent: primarySleep.efficiency_percent,
      sleep_score: primarySleep.sleep_score,
      deep_seconds: primarySleep.deep_seconds,
      rem_seconds: primarySleep.rem_seconds,
      light_seconds: primarySleep.light_seconds,
      awake_seconds: primarySleep.awake_seconds,
      start_time: primarySleep.start_time,
      end_time: primarySleep.end_time,
      source_device: primarySleep.source_device_key,
      stages: primarySleep.stages || []
    };
  }
  if (primaryVital && (!finalSummaryPayload.activity?.total_steps || finalSummaryPayload.activity.total_steps === 0)) {
    finalSummaryPayload.activity = {
      ...(finalSummaryPayload.activity || {}),
      total_steps: primaryVital.steps ?? 0,
      active_calories: primaryVital.active_kcal ?? 0,
      source_device: primaryVital.source_device_key
    };
  }

  // 3. Upsert canonical summary into health_daily_summary
  const { error: upsertErr } = await supabase
    .from('health_daily_summary')
    .upsert(
      {
        user_id: summaryRow.user_id,
        local_date: summaryRow.local_date,
        computed_at: summaryRow.computed_at,
        engine_version: summaryRow.engine_version,
        raw_watermark: summaryRow.raw_watermark,
        steps: finalSteps,
        active_kcal: finalActiveKcal,
        sleep_asleep_s: finalSleepAsleep,
        sleep_score: finalSleepScore,
        stress_avg: finalStress,
        rhr: finalRhr,
        hrv_sdnn: finalHrvSdnn,
        hrv_rmssd: finalHrvRmssd,
        weight: summaryRow.weight,
        spo2: finalSpo2,
        summary: finalSummaryPayload
      },
      { onConflict: 'user_id,local_date' }
    );

  if (upsertErr) {
    throw new Error(`Failed to upsert health_daily_summary: ${upsertErr.message}`);
  }

  // 4. Drain from health_day_dirty
  await supabase
    .from('health_day_dirty')
    .delete()
    .eq('user_id', userId)
    .eq('local_date', targetDate);

  return { success: true, date: targetDate, summary: summaryRow };
}
