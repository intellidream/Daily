-- Ensure UPDATE upserts on health_sleep_sessions refresh ingested_at for cross-device staleness visibility
CREATE OR REPLACE FUNCTION public.trg_fn_touch_sleep_ingested_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.ingested_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_z_touch_sleep_ingested_at ON public.health_sleep_sessions;
CREATE TRIGGER trg_z_touch_sleep_ingested_at
    BEFORE UPDATE ON public.health_sleep_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_sleep_ingested_at();
