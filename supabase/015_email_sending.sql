-- =====================================================================
-- Shri Balaji Hostel: sending emails from the phone
--
-- Run AFTER 001 to 014: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The phone sends emails through the Edge Function "send-email"
-- (supabase/functions/send-email/index.ts), which connects to Gmail. The
-- Gmail app password is kept in Supabase Vault (encrypted), under the name
-- "gmail_app_password". It is never sent back to the phone: the app can only
-- ask whether one is saved.
--
-- These functions only prepare Vault for that:
--   * gmail_password_saved()  - the admin's app asks "is a password saved?"
--   * _set_gmail_app_password / _get_gmail_app_password - used only by the
--     Edge Function, with the service role. Nobody else can run them.
-- =====================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS supabase_vault;

-- True when the signed in admin has saved the Gmail app password.
CREATE OR REPLACE FUNCTION public.gmail_password_saved()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT public.is_hostel_admin()
       AND EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'gmail_app_password');
$$;

CREATE OR REPLACE FUNCTION public._set_gmail_app_password(p_password TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF btrim(coalesce(p_password, '')) = '' THEN
        RAISE EXCEPTION 'Please enter the Gmail app password.' USING ERRCODE = 'P0001';
    END IF;
    SELECT id INTO v_id FROM vault.secrets WHERE name = 'gmail_app_password';
    IF v_id IS NULL THEN
        PERFORM vault.create_secret(p_password, 'gmail_app_password',
                                    'Gmail app password for the hostel emails');
    ELSE
        PERFORM vault.update_secret(v_id, p_password, 'gmail_app_password',
                                    'Gmail app password for the hostel emails');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._get_gmail_app_password()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'gmail_app_password';
$$;

-- Only the Edge Function (service role) may read or write the password.
REVOKE ALL ON FUNCTION public._set_gmail_app_password(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._get_gmail_app_password()     FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._set_gmail_app_password(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public._get_gmail_app_password()     TO service_role;

-- Firebase tokens have no "role" claim, so the app's requests run as role
-- anon: it needs this too. The check inside the function decides.
REVOKE ALL ON FUNCTION public.gmail_password_saved() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gmail_password_saved() TO anon, authenticated;

COMMIT;
