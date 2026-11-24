-- =====================================================================
-- Shri Balaji Hostel: Fee Reminders screen
--
-- Run AFTER 001 to 010: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- A WhatsApp fee reminder sent from the phone is kept in the email history
-- as the desktop keeps one sent with "WhatsApp on this PC": one row per
-- invoice it was about, type WhatsAppReminder, subject "manual fee
-- reminder". The Fee Reminders screen shows the last reminder from it.
-- The function runs with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use it.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.log_fee_reminder(
    p_student_id  INTEGER,
    p_mobile      TEXT,
    p_invoice_ids INTEGER[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.student WHERE student_id = p_student_id) THEN
        RAISE EXCEPTION 'This student no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(coalesce(p_invoice_ids, '{}')) AS x(id)
               WHERE NOT EXISTS (SELECT 1 FROM public.invoice i
                                  WHERE i.invoice_id = x.id AND i.student_id = p_student_id)) THEN
        RAISE EXCEPTION 'An invoice of this reminder no longer exists. Please refresh.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.email_history (student_id, invoice_id, recipient_email, email_type, subject, sent_date, status)
    SELECT p_student_id, x.id, '+' || p_mobile, 'WhatsAppReminder', 'manual fee reminder', now(), 'Sent'
      FROM unnest(CASE WHEN cardinality(coalesce(p_invoice_ids, '{}')) = 0
                       THEN ARRAY[NULL::INTEGER] ELSE p_invoice_ids END) AS x(id);
END;
$$;

COMMIT;
