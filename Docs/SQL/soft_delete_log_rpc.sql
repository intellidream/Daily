-- RPC function for soft-deleting habit logs from HarmonyOS watch app
-- Required because HarmonyOS @ohos.net.http does not support HTTP PATCH method
-- Called via POST /rest/v1/rpc/soft_delete_log

CREATE OR REPLACE FUNCTION soft_delete_log(log_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.habits_logs
  SET is_deleted = true
  WHERE id = log_id
    AND user_id = auth.uid();
END;
$$;
