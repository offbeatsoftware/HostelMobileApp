-- =====================================================================
-- Shri Balaji Hostel: payment QR image for WhatsApp fee reminders
--
-- Run AFTER 001 to 013: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The desktop keeps the payment QR image as a file on the PC. The phone
-- cannot read that file, so the mobile app keeps its own copy in a private
-- Supabase Storage bucket, "payment-qr" (PNG or JPG, at most 5 MB). Only
-- the signed in admin can read, add or remove it (is_hostel_admin(), from
-- script 002). Its name is kept in app_setting "WhatsApp.PaymentQrCloud",
-- so the desktop's own QR setting is not touched.
-- =====================================================================

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('payment-qr', 'payment-qr', false, 5242880, ARRAY['image/png', 'image/jpeg'])
ON CONFLICT (id) DO UPDATE
   SET public = false,
       file_size_limit = 5242880,
       allowed_mime_types = ARRAY['image/png', 'image/jpeg'];

DROP POLICY IF EXISTS hostel_admin_payment_qr ON storage.objects;
CREATE POLICY hostel_admin_payment_qr ON storage.objects
    FOR ALL TO authenticated
    USING (bucket_id = 'payment-qr' AND public.is_hostel_admin())
    WITH CHECK (bucket_id = 'payment-qr' AND public.is_hostel_admin());

COMMIT;
