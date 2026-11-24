-- =====================================================================
-- Shri Balaji Hostel: Colleges screen (add, edit, delete colleges)
--
-- Run AFTER 001, 002 and 003: Supabase Dashboard > SQL Editor.
-- Safe to run again.
--
-- The same rules as the desktop CollegeService:
--   * a college belongs to one hostel and stays in it when edited
--   * college names are unique within a hostel, ignoring capitals
--   * a college can be deleted only when no student is linked to it
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- College names are unique within a hostel, ignoring capitals.
CREATE UNIQUE INDEX IF NOT EXISTS ux_college_hostel_name_lower
    ON public.college (hostel_id, lower(college_name));

-- Colleges with the number of students linked to them, for the list.
CREATE OR REPLACE VIEW public.college_list
WITH (security_invoker = true)
AS
SELECT c.college_id,
       c.hostel_id,
       c.college_name,
       c.address,
       c.phone,
       (SELECT count(*) FROM public.student s WHERE s.college_id = c.college_id)::int AS student_count
FROM public.college c;

-- Adds a college to p_hostel_id (p_college_id NULL) or saves changes to an
-- existing college, which stays in its hostel. Returns the college_id.
CREATE OR REPLACE FUNCTION public.save_college(
    p_college_id   INTEGER,
    p_hostel_id    INTEGER,
    p_college_name TEXT,
    p_address      TEXT,
    p_phone        TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_name      TEXT := btrim(coalesce(p_college_name, ''));
    v_hostel_id INTEGER;
    v_id        INTEGER;
BEGIN
    IF p_college_id IS NOT NULL THEN
        SELECT hostel_id INTO v_hostel_id FROM public.college WHERE college_id = p_college_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'This college no longer exists. It may have been deleted.'
                USING ERRCODE = 'P0001';
        END IF;
    ELSE
        SELECT hostel_id INTO v_hostel_id FROM public.hostel WHERE hostel_id = p_hostel_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Please select a hostel first.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'Please enter the college name.' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM public.college
               WHERE hostel_id = v_hostel_id
                 AND lower(college_name) = lower(v_name)
                 AND college_id IS DISTINCT FROM p_college_id) THEN
        RAISE EXCEPTION 'A college named "%" already exists in this hostel.', v_name
            USING ERRCODE = 'P0001';
    END IF;

    IF p_college_id IS NULL THEN
        INSERT INTO public.college (hostel_id, college_name, address, phone)
        VALUES (v_hostel_id, v_name, nullif(btrim(p_address), ''), nullif(btrim(p_phone), ''))
        RETURNING college_id INTO v_id;
    ELSE
        UPDATE public.college
        SET college_name = v_name,
            address      = nullif(btrim(p_address), ''),
            phone        = nullif(btrim(p_phone), '')
        WHERE college_id = p_college_id
        RETURNING college_id INTO v_id;
    END IF;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'A college named "%" already exists in this hostel.', v_name
            USING ERRCODE = 'P0001';
END;
$$;

-- Deletes a college that no student is linked to.
CREATE OR REPLACE FUNCTION public.delete_college(p_college_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_students INTEGER;
BEGIN
    SELECT student_count INTO v_students FROM public.college_list WHERE college_id = p_college_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This college no longer exists.' USING ERRCODE = 'P0001';
    END IF;

    IF v_students > 0 THEN
        RAISE EXCEPTION 'This college cannot be deleted because % student record(s) are linked to it.',
            v_students USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.college WHERE college_id = p_college_id;
END;
$$;

COMMIT;
