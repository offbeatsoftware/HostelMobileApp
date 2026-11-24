-- =====================================================================
-- Shri Balaji Hostel: Students screen (add, edit, delete, make active)
--
-- Run AFTER 001 to 005: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rules as the desktop StudentService:
--   * only the name and gender are required; everything entered must be valid
--   * gender Male / Female / Other; status Active / Left
--   * the date of birth is in the past and before the admission date
--   * Aadhaar number: 12 digits, not starting with 0 or 1, with a valid
--     Verhoeff check digit; no two students share one
--   * a student stays in the hostel they were added to; the college, when
--     chosen, must be one of that hostel
--   * a student in a room cannot be set to Left (use check-out) or change
--     gender
--   * a student with room, invoice, payment, refund, email or attendance
--     records cannot be deleted; set the status to Left instead
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- No two students share an Aadhaar number (students without one are fine).
CREATE UNIQUE INDEX IF NOT EXISTS ux_student_aadhaar_number
    ON public.student (aadhaar_number)
    WHERE aadhaar_number IS NOT NULL;

-- True when the 12 digit Aadhaar number has a valid Verhoeff check digit
-- (the check UIDAI uses; it catches most typing mistakes).
CREATE OR REPLACE FUNCTION public.is_valid_aadhaar(p_number TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    d INTEGER[] := ARRAY[
        0,1,2,3,4,5,6,7,8,9, 1,2,3,4,0,6,7,8,9,5, 2,3,4,0,1,7,8,9,5,6,
        3,4,0,1,2,8,9,5,6,7, 4,0,1,2,3,9,5,6,7,8, 5,9,8,7,6,0,4,3,2,1,
        6,5,9,8,7,1,0,4,3,2, 7,6,5,9,8,2,1,0,4,3, 8,7,6,5,9,3,2,1,0,4,
        9,8,7,6,5,4,3,2,1,0];
    p INTEGER[] := ARRAY[
        0,1,2,3,4,5,6,7,8,9, 1,5,7,6,2,8,3,0,9,4, 5,8,0,3,7,9,6,1,4,2,
        8,9,1,6,0,4,3,5,2,7, 9,4,5,3,1,2,6,8,7,0, 4,2,8,6,5,7,3,9,0,1,
        2,7,9,3,8,0,6,4,1,5, 7,0,4,6,9,1,3,2,5,8];
    c INTEGER := 0;
    digit INTEGER;
BEGIN
    IF p_number IS NULL OR p_number !~ '^[2-9][0-9]{11}$' THEN
        RETURN FALSE;
    END IF;
    FOR i IN 0..11 LOOP
        digit := substr(p_number, 12 - i, 1)::INTEGER;
        c := d[c * 10 + p[(i % 8) * 10 + digit + 1] + 1];
    END LOOP;
    RETURN c = 0;
END;
$$;

-- Students with their college and the room they are in now, for the list.
CREATE OR REPLACE VIEW public.student_list
WITH (security_invoker = true)
AS
SELECT s.*,
       c.college_name,
       (SELECT r.room_number
          FROM public.room_allocation a
          JOIN public.room r ON r.room_id = a.room_id
         WHERE a.student_id = s.student_id AND a.status = 'Current'
         LIMIT 1) AS room_number
FROM public.student s
LEFT JOIN public.college c ON c.college_id = s.college_id;

-- Adds a student to p_hostel_id (p_student_id NULL) or saves changes to an
-- existing student, who stays in their hostel. p_data holds the fields by
-- column name; dates as YYYY-MM-DD. Returns the student_id.
CREATE OR REPLACE FUNCTION public.save_student(
    p_student_id INTEGER,
    p_hostel_id  INTEGER,
    p_data       JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_existing  public.student;
    v_hostel_id INTEGER;
    v_room      TEXT;
    v_id        INTEGER;
    v_name      TEXT := btrim(coalesce(p_data ->> 'student_name', ''));
    v_gender    TEXT := btrim(coalesce(p_data ->> 'gender', ''));
    v_status    TEXT := coalesce(nullif(btrim(p_data ->> 'status'), ''), 'Active');
    v_aadhaar   TEXT := nullif(regexp_replace(coalesce(p_data ->> 'aadhaar_number', ''), '[ -]', '', 'g'), '');
    v_birth     DATE := nullif(p_data ->> 'date_of_birth', '')::DATE;
    v_admission DATE := coalesce(nullif(p_data ->> 'admission_date', '')::DATE, current_date);
    v_college   INTEGER := nullif(p_data ->> 'college_id', '')::INTEGER;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Please enter the student''s name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_gender = '' THEN
        RAISE EXCEPTION 'Please select the gender.' USING ERRCODE = 'P0001';
    END IF;
    IF v_gender NOT IN ('Male', 'Female', 'Other') THEN
        RAISE EXCEPTION 'Please select the gender from the list.' USING ERRCODE = 'P0001';
    END IF;
    IF v_status NOT IN ('Active', 'Left') THEN
        RAISE EXCEPTION 'Please select the status (Active or Left).' USING ERRCODE = 'P0001';
    END IF;
    IF v_birth IS NOT NULL AND v_birth >= current_date THEN
        RAISE EXCEPTION 'The date of birth must be in the past.' USING ERRCODE = 'P0001';
    END IF;
    IF v_birth IS NOT NULL AND v_admission <= v_birth THEN
        RAISE EXCEPTION 'The admission date must be after the date of birth.' USING ERRCODE = 'P0001';
    END IF;
    IF v_aadhaar IS NOT NULL AND NOT public.is_valid_aadhaar(v_aadhaar) THEN
        RAISE EXCEPTION 'The Aadhaar number is not valid. It must have 12 digits; please check it for typing mistakes.'
            USING ERRCODE = 'P0001';
    END IF;
    IF v_aadhaar IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.student
        WHERE aadhaar_number = v_aadhaar AND student_id IS DISTINCT FROM p_student_id) THEN
        RAISE EXCEPTION 'Another student already has this Aadhaar number.' USING ERRCODE = 'P0001';
    END IF;

    IF p_student_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM public.student WHERE student_id = p_student_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'This student no longer exists. It may have been deleted.' USING ERRCODE = 'P0001';
        END IF;
        v_hostel_id := v_existing.hostel_id;
    ELSE
        SELECT hostel_id INTO v_hostel_id FROM public.hostel WHERE hostel_id = p_hostel_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Please select a hostel first.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF v_college IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.college WHERE college_id = v_college AND hostel_id = v_hostel_id) THEN
        RAISE EXCEPTION 'Please select a college of this hostel from the list.' USING ERRCODE = 'P0001';
    END IF;

    IF p_student_id IS NOT NULL THEN
        SELECT r.room_number INTO v_room
          FROM public.room_allocation a JOIN public.room r ON r.room_id = a.room_id
         WHERE a.student_id = p_student_id AND a.status = 'Current'
         LIMIT 1;
        IF v_room IS NOT NULL AND v_status = 'Left' THEN
            RAISE EXCEPTION '% is in room %. Use Check-out on the Room Allocation screen; it sets the status to Left.',
                v_existing.student_name, v_room USING ERRCODE = 'P0001';
        END IF;
        IF v_room IS NOT NULL AND v_gender <> coalesce(v_existing.gender, '') THEN
            RAISE EXCEPTION '% is in room %, so the gender cannot be changed. Check out first.',
                v_existing.student_name, v_room USING ERRCODE = 'P0001';
        END IF;

        UPDATE public.student SET
            student_name   = v_name,
            date_of_birth  = v_birth,
            gender         = v_gender,
            address        = nullif(btrim(p_data ->> 'address'), ''),
            college_id     = v_college,
            course         = nullif(btrim(p_data ->> 'course'), ''),
            class_name     = nullif(btrim(p_data ->> 'class_name'), ''),
            mobile         = nullif(btrim(p_data ->> 'mobile'), ''),
            email          = nullif(btrim(p_data ->> 'email'), ''),
            father_name    = nullif(btrim(p_data ->> 'father_name'), ''),
            father_mobile  = nullif(btrim(p_data ->> 'father_mobile'), ''),
            father_email   = nullif(btrim(p_data ->> 'father_email'), ''),
            mother_name    = nullif(btrim(p_data ->> 'mother_name'), ''),
            mother_mobile  = nullif(btrim(p_data ->> 'mother_mobile'), ''),
            mother_email   = nullif(btrim(p_data ->> 'mother_email'), ''),
            aadhaar_number = v_aadhaar,
            admission_date = v_admission,
            status         = v_status,
            remarks        = nullif(btrim(p_data ->> 'remarks'), '')
        WHERE student_id = p_student_id
        RETURNING student_id INTO v_id;
    ELSE
        INSERT INTO public.student (
            hostel_id, student_name, date_of_birth, gender, address, college_id, course, class_name,
            mobile, email, father_name, father_mobile, father_email,
            mother_name, mother_mobile, mother_email, aadhaar_number, admission_date, status, remarks)
        VALUES (
            v_hostel_id, v_name, v_birth, v_gender,
            nullif(btrim(p_data ->> 'address'), ''), v_college,
            nullif(btrim(p_data ->> 'course'), ''), nullif(btrim(p_data ->> 'class_name'), ''),
            nullif(btrim(p_data ->> 'mobile'), ''), nullif(btrim(p_data ->> 'email'), ''),
            nullif(btrim(p_data ->> 'father_name'), ''), nullif(btrim(p_data ->> 'father_mobile'), ''),
            nullif(btrim(p_data ->> 'father_email'), ''),
            nullif(btrim(p_data ->> 'mother_name'), ''), nullif(btrim(p_data ->> 'mother_mobile'), ''),
            nullif(btrim(p_data ->> 'mother_email'), ''),
            v_aadhaar, v_admission, v_status, nullif(btrim(p_data ->> 'remarks'), ''))
        RETURNING student_id INTO v_id;
    END IF;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Another student already has this Aadhaar number.' USING ERRCODE = 'P0001';
END;
$$;

-- Deletes a student who has no room, invoice, payment, refund, email or
-- attendance records.
CREATE OR REPLACE FUNCTION public.delete_student(p_student_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
BEGIN
    SELECT student_name INTO v_name FROM public.student WHERE student_id = p_student_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This student no longer exists.' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM public.room_allocation WHERE student_id = p_student_id)
       OR EXISTS (SELECT 1 FROM public.invoice        WHERE student_id = p_student_id)
       OR EXISTS (SELECT 1 FROM public.payment        WHERE student_id = p_student_id)
       OR EXISTS (SELECT 1 FROM public.refund         WHERE student_id = p_student_id)
       OR EXISTS (SELECT 1 FROM public.payment_change WHERE student_id = p_student_id)
       OR EXISTS (SELECT 1 FROM public.email_history  WHERE student_id = p_student_id)
       OR EXISTS (SELECT 1 FROM public.attendance     WHERE student_id = p_student_id) THEN
        RAISE EXCEPTION '% has room, invoice or payment records and cannot be deleted. Edit the student and set the status to Left instead.',
            v_name USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.student WHERE student_id = p_student_id;
END;
$$;

-- Makes an inactive (Left) student active again, for example one who comes back.
CREATE OR REPLACE FUNCTION public.make_student_active(p_student_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_student public.student;
BEGIN
    SELECT * INTO v_student FROM public.student WHERE student_id = p_student_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This student no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    IF v_student.status = 'Active' THEN
        RAISE EXCEPTION '% is already active.', v_student.student_name USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.student SET status = 'Active' WHERE student_id = p_student_id;
END;
$$;

COMMIT;
