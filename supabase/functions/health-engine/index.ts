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
      await supabase.rpc('apply_health_data_retention').catch((e: any) => {
        console.warn('Retention RPC execution notice:', e);
      });

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

  // 1. Fetch raw telemetry within the full window for this user
  const { data: telemetryRows, error: telemErr } = await supabase
    .from('health_telemetry')
    .select('*')
    .eq('user_id', userId)
    .gte('start_time', windowStartIso)
    .lte('start_time', windowEndIso);

  if (telemErr) {
    throw new Error(`Failed to fetch telemetry: ${telemErr.message}`);
  }

  // 2. Run the deterministic Canonical Health Engine
  const summaryRow = computeDailyHealthSummary({
    userId,
    targetDate,
    telemetry: (telemetryRows || []) as HealthTelemetryRow[],
    tzOffsetMin,
    preferredDevice
  });

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

  // 4. Drain from health_day_dirty
  await supabase
    .from('health_day_dirty')
    .delete()
    .eq('user_id', userId)
    .eq('local_date', targetDate);

  return { success: true, date: targetDate, summary: summaryRow };
}
