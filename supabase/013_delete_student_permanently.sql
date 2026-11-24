-- =====================================================================
-- Shri Balaji Hostel: Delete Permanently (Students screen)
--
-- Run AFTER 001 to 012: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rule as the desktop StudentService.DeletePermanently: an
-- inactive (Left) student can be deleted for good, at any time, with all
-- their fees, payments, refunds, room history, attendance, emails and
-- payment change history. A reason is required. Active students, and
-- students still in a room, cannot be deleted.
--
-- The desktop makes a backup of its database file first. On Supabase the
-- database is not a file the app can copy: take a backup from the Supabase
-- Dashboard (Database > Backups) if you want one before deleting.
--
-- The function runs with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use it.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_student_permanently(p_student_id INTEGER, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    s public.student;
    v_reason TEXT := btrim(coalesce(p_reason, ''));
BEGIN
    SELECT * INTO s FROM public.student WHERE student_id = p_student_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This student no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    IF s.status <> 'Left'
       OR EXISTS (SELECT 1 FROM public.room_allocation
                   WHERE student_id = p_student_id AND status = 'Current') THEN
        RAISE EXCEPTION '% is active. Check the student out first; only inactive students can be deleted.',
            s.student_name USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = '' THEN
        RAISE EXCEPTION 'Please enter the reason for deleting the student.' USING ERRCODE = 'P0001';
    END IF;
    IF length(v_reason) > 255 THEN
        RAISE EXCEPTION 'Reason can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.attendance     WHERE student_id = p_student_id;
    DELETE FROM public.email_history  WHERE student_id = p_student_id;
    DELETE FROM public.payment_change WHERE student_id = p_student_id;
    DELETE FROM public.refund         WHERE student_id = p_student_id;
    DELETE FROM public.payment        WHERE student_id = p_student_id;
    DELETE FROM public.invoice        WHERE student_id = p_student_id;
    DELETE FROM public.room_allocation WHERE student_id = p_student_id;
    DELETE FROM public.student        WHERE student_id = p_student_id;
END;
$$;

COMMIT;
