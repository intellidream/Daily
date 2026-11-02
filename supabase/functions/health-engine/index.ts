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

    // Mode A: Process dirty batch
    if (processDirty && (!userId || !targetDate) && !targetDates) {
      let query = supabase.from('health_day_dirty').select('user_id, local_date');
      if (userId) {
        query = query.eq('user_id', userId);
      }
      const { data: dirtyRows, error: dirtyErr } = await query
        .order('dirty_since', { ascending: true })
        .limit(15);

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
  // Fetch all 3 lean tables for this user & date in parallel
  const [vitalsRes, sleepRes, hrRes] = await Promise.all([
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
      .limit(2000)
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

  if (vitalsRows.length === 0 && sleepRows.length === 0 && hrRows.length === 0) {
    // Preserve any pre-existing historical summary when lean tables have 0 rows for an older date
    const { data: existingSummary } = await supabase
      .from('health_daily_summary')
      .select('steps, sleep_asleep_s')
      .eq('user_id', userId)
      .eq('local_date', targetDate)
      .maybeSingle();

    await supabase
      .from('health_day_dirty')
      .delete()
      .eq('user_id', userId)
      .eq('local_date', targetDate);

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

    await supabase
      .from('health_day_dirty')
      .delete()
      .eq('user_id', userId)
      .eq('local_date', targetDate);
  }

  return {
    success: true,
    date: targetDate,
    synthesized_from_lean: true,
    summary: summaryRow
  };
}
