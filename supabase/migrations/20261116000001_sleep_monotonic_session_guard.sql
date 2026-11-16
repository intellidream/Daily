-- Prevent stale/lagging companion devices (e.g. a second Android phone whose Health Connect sync trails behind)
-- from overwriting a finalized primary sleep session backwards with an earlier-ending or truncated snapshot.
-- Preserves existing empty-stages guard and works with `trg_zz_suppress_redundant_sleep_updates` so blocked
-- regressions trigger zero disk writes, zero ingested_at bumps, and zero Realtime broadcasts.

CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_sleep_sessions()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    user_prio integer;
    old_stages_len integer;
    new_stages_len integer;
BEGIN
    NEW.source_device_key := public.canonicalize_health_source_key(NEW.source_device_key, NEW.host_device_name);

    IF coalesce(NEW.session_type, 'primary_sleep') = 'nap' THEN
        NEW.source_priority := 99;
    ELSE
        SELECT hs.priority_sleep INTO user_prio
        FROM public.health_sources hs
        WHERE hs.user_id = NEW.user_id
          AND hs.display_name = NEW.source_device_key
        LIMIT 1;

        NEW.source_priority := COALESCE(
            user_prio,
            public.canonical_sleep_priority(NEW.source_device_key, NEW.session_type)
        );
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.id := 'sleep_' || NEW.user_id::text || '_' || NEW.local_date::text || '_' || NEW.session_type || '_' ||
                  regexp_replace(lower(NEW.source_device_key), '[^a-z0-9]+', '_', 'g');
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        NEW.is_user_selected := COALESCE(OLD.is_user_selected, false) OR COALESCE(NEW.is_user_selected, false);

        old_stages_len := jsonb_array_length(COALESCE(OLD.stages, '[]'::jsonb));
        new_stages_len := jsonb_array_length(COALESCE(NEW.stages, '[]'::jsonb));

        IF new_stages_len = 0 AND old_stages_len > 0 THEN
            NEW.stages := OLD.stages;
            NEW.deep_seconds := OLD.deep_seconds;
            NEW.rem_seconds := OLD.rem_seconds;
            NEW.light_seconds := OLD.light_seconds;
            NEW.awake_seconds := OLD.awake_seconds;
            NEW.duration_seconds := GREATEST(OLD.duration_seconds, NEW.duration_seconds);
            NEW.time_in_bed_seconds := GREATEST(OLD.time_in_bed_seconds, NEW.time_in_bed_seconds);
        ELSIF old_stages_len > 0
          AND NEW.start_time IS NOT NULL AND OLD.start_time IS NOT NULL
          AND NEW.end_time IS NOT NULL AND OLD.end_time IS NOT NULL
          AND ABS(EXTRACT(EPOCH FROM (NEW.start_time - OLD.start_time))) <= 3600
          AND NOT (
              COALESCE(OLD.deep_seconds, 0) + COALESCE(OLD.rem_seconds, 0) = 0
              AND COALESCE(NEW.deep_seconds, 0) + COALESCE(NEW.rem_seconds, 0) > 0
          )
          AND (
              -- Case A: Block truncated / earlier-ending sleep snapshot from regressing wake time and asleep duration
              (
                  NEW.end_time < OLD.end_time - INTERVAL '60 seconds'
                  AND COALESCE(NEW.duration_seconds, 0) < COALESCE(OLD.duration_seconds, 0) - 60
              )
              OR
              -- Case B: Block cross-host lagging overwrite carrying fewer restorative stages and non-longer sleep
              (
                  NEW.host_device_name IS DISTINCT FROM OLD.host_device_name
                  AND NEW.host_device_name IS NOT NULL AND OLD.host_device_name IS NOT NULL
                  AND NEW.end_time <= OLD.end_time
                  AND COALESCE(NEW.duration_seconds, 0) <= COALESCE(OLD.duration_seconds, 0)
                  AND (COALESCE(NEW.deep_seconds, 0) + COALESCE(NEW.rem_seconds, 0))
                      < (COALESCE(OLD.deep_seconds, 0) + COALESCE(OLD.rem_seconds, 0))
              )
          ) THEN
            NEW.host_device_name := OLD.host_device_name;
            NEW.start_time := OLD.start_time;
            NEW.end_time := OLD.end_time;
            NEW.duration_seconds := OLD.duration_seconds;
            NEW.time_in_bed_seconds := OLD.time_in_bed_seconds;
            NEW.efficiency_percent := OLD.efficiency_percent;
            NEW.sleep_score := OLD.sleep_score;
            NEW.deep_seconds := OLD.deep_seconds;
            NEW.rem_seconds := OLD.rem_seconds;
            NEW.light_seconds := OLD.light_seconds;
            NEW.awake_seconds := OLD.awake_seconds;
            NEW.latency_seconds := OLD.latency_seconds;
            NEW.quality_rating := OLD.quality_rating;
            NEW.stages := OLD.stages;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
