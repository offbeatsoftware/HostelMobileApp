-- =====================================================================
-- Shri Balaji Hostel: Attendance screen
--
-- Run AFTER 001 to 009: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rules as the desktop AttendanceService:
--   * attendance is marked for the students in a room of the hostel that
--     night (checked in on or before the date, not checked out or
--     transferred that day); everyone starts as present
--   * earlier dates can be corrected; future dates cannot be marked
--   * saving again updates the night's records (the time a parent was
--     emailed is kept)
-- WhatsApp messages to parents are kept in the email history as on the
-- desktop (type WhatsAppAbsence, subject "attendance 24 Nov 2026"), so a
-- parent is not messaged twice for the same night from either app.
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- Attendance records with the student's hostel.
CREATE OR REPLACE VIEW public.attendance_list
WITH (security_invoker = true)
AS
SELECT a.*, s.hostel_id
FROM public.attendance a
JOIN public.student s ON s.student_id = a.student_id;

-- Emails and WhatsApp messages sent, with the student's hostel.
CREATE OR REPLACE VIEW public.message_history_list
WITH (security_invoker = true)
AS
SELECT e.*, s.student_name, s.hostel_id
FROM public.email_history e
JOIN public.student s ON s.student_id = e.student_id;

-- Saves the night's attendance:
-- p_entries = [{"student_id": 1, "is_present": false, "remarks": "..."}, ...].
-- Returns how many students were saved as absent.
CREATE OR REPLACE FUNCTION public.save_attendance(p_hostel_id INTEGER, p_date DATE, p_entries JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    e         JSONB;
    v_student INTEGER;
    v_name    TEXT;
    v_remarks TEXT;
BEGIN
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Please choose the date.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date > public.local_today() THEN
        RAISE EXCEPTION 'Attendance cannot be marked for a future date.' USING ERRCODE = 'P0001';
    END IF;

    -- Check every entry before saving any.
    FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) LOOP
        v_student := (e ->> 'student_id')::int;
        SELECT student_name INTO v_name FROM public.student
         WHERE student_id = v_student AND hostel_id = p_hostel_id;
        IF NOT FOUND OR NOT EXISTS (
            SELECT 1 FROM public.room_allocation a JOIN public.room r ON r.room_id = a.room_id
             WHERE a.student_id = v_student AND r.hostel_id = p_hostel_id
               AND a.check_in_date <= p_date
               AND (a.check_out_date IS NULL OR a.check_out_date > p_date)) THEN
            RAISE EXCEPTION '% was not in a room of this hostel on %.',
                coalesce(v_name, 'A student'), to_char(p_date, 'DD Mon YYYY') USING ERRCODE = 'P0001';
        END IF;
        IF length(btrim(coalesce(e ->> 'remarks', ''))) > 255 THEN
            RAISE EXCEPTION 'The remarks for % can be at most 255 characters.', v_name USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) LOOP
        v_remarks := nullif(btrim(coalesce(e ->> 'remarks', '')), '');
        INSERT INTO public.attendance (student_id, attendance_date, is_present, remarks, marked_date)
        VALUES ((e ->> 'student_id')::int, p_date, coalesce((e ->> 'is_present')::boolean, TRUE), v_remarks, now())
        ON CONFLICT (student_id, attendance_date) DO UPDATE
           SET is_present = EXCLUDED.is_present,
               remarks = EXCLUDED.remarks,
               marked_date = EXCLUDED.marked_date;
    END LOOP;

    RETURN (SELECT count(*) FROM jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) x
             WHERE NOT coalesce((x ->> 'is_present')::boolean, TRUE));
END;
$$;

-- Records a WhatsApp absence message sent to a parent, as the desktop does.
CREATE OR REPLACE FUNCTION public.log_absence_message(p_student_id INTEGER, p_mobile TEXT, p_date DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.student WHERE student_id = p_student_id) THEN
        RAISE EXCEPTION 'This student no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.email_history (student_id, invoice_id, recipient_email, email_type, subject, sent_date, status)
    VALUES (p_student_id, NULL, '+' || p_mobile, 'WhatsAppAbsence',
            'attendance ' || to_char(p_date, 'DD Mon YYYY'), now(), 'Sent');
END;
$$;

COMMIT;
