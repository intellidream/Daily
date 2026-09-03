CREATE OR REPLACE FUNCTION public.generate_watch_token()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  jwt_secret text;
  token text;
BEGIN
  -- 1. Ensure the user is logged in
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. Get the JWT secret. Newer Supabase versions block app.settings.jwt_secret.
  -- You MUST replace 'REPLACE_ME_WITH_YOUR_JWT_SECRET' with your actual JWT Secret!
  jwt_secret := current_setting('app.settings.jwt_secret', true);
  IF jwt_secret IS NULL OR jwt_secret = '' THEN
    jwt_secret := '8KGKlhehnHX7MXdidIPLYwMfeJw08QBM+Nrue1VOVpMCuPOuAPRYEJrxiuiol9L371jwkbMYk43wz/WZV+/hUg==';
  END IF;
  


  -- 3. Sign the JWT using the pgjwt extension
  -- We set the expiration (exp) to 10 years from now
  SELECT extensions.sign(
    json_build_object(
      'role', 'authenticated',
      'iss', 'supabase',
      'iat', extract(epoch from now())::integer,
      'exp', extract(epoch from (now() + interval '10 years'))::integer,
      'aud', 'authenticated',
      'sub', auth.uid()
    )::json,
    jwt_secret::text,
    'HS256'::text
  ) INTO token;

  RETURN token;
END;
$$;
