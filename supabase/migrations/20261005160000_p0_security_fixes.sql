-- P0 Security Fixes: Secure watch pairing tables and functions
-- Date: 2026-10-05

BEGIN;

-- 1. Clean up stale expired pairing codes
DELETE FROM public.watch_pairing_codes WHERE expires_at < NOW();

-- 2. Secure watch_pairing_codes RLS policies
DROP POLICY IF EXISTS "Anyone can read pairing codes" ON public.watch_pairing_codes;
DROP POLICY IF EXISTS "Permite update la PIN" ON public.watch_pairing_codes;
DROP POLICY IF EXISTS "Watches can claim a PIN code" ON public.watch_pairing_codes;

-- Allow anon watches to check only unexpired pins
CREATE POLICY "Anon read active pairing codes"
ON public.watch_pairing_codes
FOR SELECT
TO public
USING (expires_at > NOW());

-- Allow authenticated users (phones) to attach tokens to an unclaimed pin
CREATE POLICY "Auth users attach tokens to pairing code"
ON public.watch_pairing_codes
FOR UPDATE
TO authenticated
USING (NOT claimed AND expires_at > NOW())
WITH CHECK (auth.uid() = user_id);

-- Allow watch to mark as claimed
CREATE POLICY "Watches claim active pairing code"
ON public.watch_pairing_codes
FOR UPDATE
TO public
USING (NOT claimed AND expires_at > NOW())
WITH CHECK (claimed = TRUE);

-- 3. Secure paired_watches RLS policies
DROP POLICY IF EXISTS "Anon select paired watches by id" ON public.paired_watches;
DROP POLICY IF EXISTS "Anon update paired watches clear tokens" ON public.paired_watches;

-- Anon watches can ONLY fetch their record if there is a pending token waiting
CREATE POLICY "Anon fetch watch with pending token"
ON public.paired_watches
FOR SELECT
TO anon
USING (pending_access_token IS NOT NULL AND is_active = TRUE);

-- Anon watches can ONLY update to clear pending tokens
CREATE POLICY "Anon clear pending watch tokens"
ON public.paired_watches
FOR UPDATE
TO anon
USING (pending_access_token IS NOT NULL)
WITH CHECK (pending_access_token IS NULL);

-- 4. Secure watch_pairings legacy table
DROP POLICY IF EXISTS "Allow anon select watch_pairings" ON public.watch_pairings;
DROP POLICY IF EXISTS "Allow anon insert watch_pairings" ON public.watch_pairings;
DROP POLICY IF EXISTS "Allow anon delete watch_pairings" ON public.watch_pairings;

-- 5. Harden SECURITY DEFINER functions with search_path and ownership check
CREATE OR REPLACE FUNCTION public.deactivate_paired_watch(watch_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.paired_watches
  SET is_active = FALSE
  WHERE id = watch_id AND user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_orbit_pin(p_pin_code character varying)
RETURNS TABLE(user_id uuid, access_token text, refresh_token text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.watch_pairing_codes
  SET claimed = TRUE
  WHERE pin_code = p_pin_code
    AND NOT claimed
    AND expires_at > NOW()
  RETURNING watch_pairing_codes.user_id, watch_pairing_codes.access_token, watch_pairing_codes.refresh_token;
END;
$$;

COMMIT;
