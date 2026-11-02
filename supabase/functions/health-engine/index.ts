// Supabase Edge Function: health-engine
// Canonical Daily Health & Vitals Engine v2.0 (Lean Architecture)
// Runs server-side on Deno runtime in Supabase Edge Functions.

// @ts-ignore: Resolved via deno.json or npm
import { createClient } from '@supabase/supabase-js';
import { synthesizeDailyHealthSummaryFromLean } from './engine.ts';
import type {
  LeanDailyVitalsRow,
  LeanSleepSessionRow,
  LeanIntradayHrRow
} from './types.ts';

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
    let targetDates: string[] | null = null;
    let tzOffsetMin = 120;
    let preferredDevice: string | undefined = undefined;
    let processDirty = false;

    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      userId = body.user_id || body.userId;
      targetDate = body.date || body.local_date;
      if (Array.isArray(body.dates)) {
        targetDates = body.dates;
      }
      const rawTz = body.tz_offset_min ?? body.tzOffsetMin;
      if (rawTz !== undefined && rawTz !== null && rawTz !== 0) {
        tzOffsetMin = Number(rawTz) || 120;
      }
      preferredDevice = body.preferred_device || body.preferredDevice;
      processDirty = body.process_dirty === true;
    } else if (req.method === 'GET') {
      const url = new URL(req.url);
      userId = url.searchParams.get('user_id');
      targetDate = url.searchParams.get('date');
      const tzParam = url.searchParams.get('tz_offset_min');
      if (tzParam !== null) {
        const parsed = parseInt(tzParam, 10);
        if (!isNaN(parsed) && parsed !== 0) tzOffsetMin = parsed;
      }
      preferredDevice = url.searchParams.get('preferred_device') || undefined;
      processDirty = url.searchParams.get('process_dirty') === 'true';
    }

    // Mode A: Legacy process_dirty compatibility no-op (health_day_dirty retired in Lean v2.0)
    if (processDirty && (!userId || !targetDate) && !targetDates) {
      try {
        await supabase.rpc('apply_health_data_retention');
      } catch (e: any) {
        console.warn('Retention RPC execution notice:', e);
      }

      return new Response(JSON.stringify({ processed_count: 0, results: [] }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Mode B: Process batch of explicit dates for a user
    if (userId && targetDates && targetDates.length > 0) {
      const results = [];
      for (const d of targetDates) {
        const rowRes = await processDayForUser(supabase, userId, d, tzOffsetMin, preferredDevice);
        results.push(rowRes);
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
  // Compute 28-day rolling baseline window [targetDate - 28d, targetDate - 1d]
  const parsedTarget = new Date(`${targetDate}T00:00:00Z`);
  const histStart = new Date(parsedTarget.getTime() - 28 * 86400 * 1000)
    .toISOString()
    .slice(0, 10);

  // Fetch all 3 lean tables + 28-day rolling vitals baseline in parallel
  const [vitalsRes, sleepRes, hrRes, historyVitalsRes] = await Promise.all([
    supabase
      .from('health_daily_vitals')
      .select('*')
      .eq('user_id', userId)
      .eq('local_date', targetDate),
    supabase
      .from('health_sleep_sessions')
      .select('*')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .order('source_priority', { ascending: true }),
    supabase
      .from('health_intraday_heart_rate')
      .select('*')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .order('bucket_minute', { ascending: true })
      .limit(2000),
    supabase
      .from('health_daily_vitals')
      .select('local_date, source_device_key, host_device_name, resting_heart_rate, hrv_sdnn_nightly, hrv_rmssd_nightly')
      .eq('user_id', userId)
      .gte('local_date', histStart)
      .lt('local_date', targetDate)
      .limit(250)
  ]);

  if (vitalsRes.error) {
    console.error(`[health-engine] health_daily_vitals query error:`, vitalsRes.error);
  }
  if (sleepRes.error) {
    console.error(`[health-engine] health_sleep_sessions query error:`, sleepRes.error);
  }
  if (hrRes.error) {
    console.error(`[health-engine] health_intraday_heart_rate query error:`, hrRes.error);
  }

  const vitalsRows = (vitalsRes.data || []) as LeanDailyVitalsRow[];
  const sleepRows = (sleepRes.data || []) as LeanSleepSessionRow[];
  const hrRows = (hrRes.data || []) as LeanIntradayHrRow[];
  const historyVitalsRows = (historyVitalsRes.data || []) as LeanDailyVitalsRow[];

  if (vitalsRows.length === 0 && sleepRows.length === 0 && hrRows.length === 0) {
    // Preserve any pre-existing historical summary when lean tables have 0 rows for an older date
    const { data: existingSummary } = await supabase
      .from('health_daily_summary')
      .select('steps, sleep_asleep_s')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .maybeSingle();

    if (existingSummary && (existingSummary.steps !== null || existingSummary.sleep_asleep_s !== null)) {
      return { success: true, date: targetDate, preserved: true };
    }
    return { success: true, date: targetDate, empty: true };
  }

  const summaryRow = synthesizeDailyHealthSummaryFromLean({
    userId,
    targetDate,
    vitalsRows,
    sleepRows,
    hrRows,
    historyVitalsRows,
    tzOffsetMin,
    preferredDevice
  });

  // Only persist canonical unfiltered summary into health_daily_summary
  if (!preferredDevice) {
    const { error: upsertErr } = await supabase
      .from('health_daily_summary')
      .upsert(
        {
          user_id: summaryRow.user_id,
          local_date: summaryRow.local_date,
          computed_at: summaryRow.computed_at,
          engine_version: summaryRow.engine_version,
          raw_watermark: summaryRow.raw_watermark,
          steps: summaryRow.steps,
          active_kcal: summaryRow.active_kcal,
          sleep_asleep_s: summaryRow.sleep_asleep_s,
          sleep_score: summaryRow.sleep_score,
          stress_avg: summaryRow.stress_avg,
          rhr: summaryRow.rhr,
          hrv_sdnn: summaryRow.hrv_sdnn,
          hrv_rmssd: summaryRow.hrv_rmssd,
          weight: summaryRow.weight,
          spo2: summaryRow.spo2,
          summary: summaryRow.summary
        },
        { onConflict: 'user_id,local_date' }
      );

    if (upsertErr) {
      throw new Error(`Failed to upsert health_daily_summary: ${upsertErr.message}`);
    }
  }

  return {
    success: true,
    date: targetDate,
    synthesized_from_lean: true,
    summary: summaryRow
  };
}
