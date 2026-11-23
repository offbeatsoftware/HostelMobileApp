-- =====================================================================
-- Shri Balaji Hostel: let the mobile app's admin read and change data
--
-- Run AFTER 001_hostel_schema.sql: Supabase Dashboard > SQL Editor.
--
-- The mobile app signs in with Firebase Authentication and sends the
-- Firebase ID token with every request. Supabase checks the token
-- (Authentication > Third-party Auth > Firebase). These rules then allow a
-- request only when:
--   1. the token was issued by this Firebase project, and
--   2. the Firebase user is an admin: their User UID is in admin_user.firebase_uid.
-- Anyone else, including a request with only the publishable key, sees no
-- rows and cannot change anything.
-- =====================================================================

BEGIN;

-- True when the signed in Firebase user is a hostel admin.
-- SECURITY DEFINER lets it read admin_user, which is itself protected.
CREATE OR REPLACE FUNCTION public.is_hostel_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(auth.jwt() ->> 'iss', '')
               = 'https://securetoken.google.com/hostelmanagement-86380'
       AND EXISTS (
               SELECT 1
               FROM public.admin_user
               WHERE firebase_uid = auth.jwt() ->> 'sub'
           );
$$;

-- One rule per table: admins can read, add, change and delete.
-- "anon, authenticated" covers Firebase tokens with or without a role claim;
-- the check inside is_hostel_admin() is what decides.
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'schema_info', 'hostel', 'college', 'sharing_type', 'room',
        'student', 'room_allocation', 'invoice', 'payment', 'payment_change',
        'refund', 'email_history', 'attendance', 'admin_user', 'app_setting'
    ]
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS hostel_admin_all ON public.%I', t);
        EXECUTE format(
            'CREATE POLICY hostel_admin_all ON public.%I
                 FOR ALL TO anon, authenticated
                 USING (public.is_hostel_admin())
                 WITH CHECK (public.is_hostel_admin())', t);
    END LOOP;
END
$$;

-- Link the admin row to the Firebase user.
-- Copy the User UID from Firebase Console > Authentication > Users
-- (the row for admin@shribalajihostel.com) and paste it below.
UPDATE public.admin_user
SET firebase_uid = 'PASTE_FIREBASE_USER_UID_HERE',
    updated_date = now()
WHERE email = 'admin@shribalajihostel.com';

-- A first hostel, so the app has something to show.
INSERT INTO public.hostel (hostel_name)
VALUES ('Shri Balaji Hostel')
ON CONFLICT (hostel_name) DO NOTHING;

COMMIT;
