-- =====================================================================
-- Shri Balaji Hostel: Hostels screen (add, edit, delete hostels)
--
-- Run AFTER 001 and 002: Supabase Dashboard > SQL Editor.
-- Safe to run again.
--
-- The same rules as the desktop HostelService:
--   * hostel names are unique, ignoring capitals
--   * a new hostel gets the Single, Double and Triple sharing types
--   * a hostel can be deleted only when it has no students, colleges or rooms
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- Hostel names are unique ignoring capitals ("Boys Hostel" = "BOYS HOSTEL").
CREATE UNIQUE INDEX IF NOT EXISTS ux_hostel_hostel_name_lower
    ON public.hostel (lower(hostel_name));

-- Hostels with the number of colleges, rooms and students, for the list.
CREATE OR REPLACE VIEW public.hostel_list
WITH (security_invoker = true)
AS
SELECT h.hostel_id,
       h.hostel_name,
       h.address,
       h.phone,
       h.email,
       (SELECT count(*) FROM public.college c WHERE c.hostel_id = h.hostel_id)::int AS college_count,
       (SELECT count(*) FROM public.room r    WHERE r.hostel_id = h.hostel_id)::int AS room_count,
       (SELECT count(*) FROM public.student s WHERE s.hostel_id = h.hostel_id)::int AS student_count
FROM public.hostel h;

-- Adds a hostel (p_hostel_id NULL) with its sharing types, or saves changes.
-- Returns the hostel_id.
CREATE OR REPLACE FUNCTION public.save_hostel(
    p_hostel_id   INTEGER,
    p_hostel_name TEXT,
    p_address     TEXT,
    p_phone       TEXT,
    p_email       TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT := btrim(coalesce(p_hostel_name, ''));
    v_id   INTEGER;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Please enter the hostel name.' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM public.hostel
               WHERE lower(hostel_name) = lower(v_name)
                 AND hostel_id IS DISTINCT FROM p_hostel_id) THEN
        RAISE EXCEPTION 'A hostel named "%" already exists.', v_name USING ERRCODE = 'P0001';
    END IF;

    IF p_hostel_id IS NULL THEN
        INSERT INTO public.hostel (hostel_name, address, phone, email)
        VALUES (v_name,
                nullif(btrim(p_address), ''),
                nullif(btrim(p_phone), ''),
                nullif(btrim(p_email), ''))
        RETURNING hostel_id INTO v_id;

        INSERT INTO public.sharing_type (hostel_id, sharing_name, capacity)
        VALUES (v_id, 'Single', 1), (v_id, 'Double', 2), (v_id, 'Triple', 3);
    ELSE
        UPDATE public.hostel
        SET hostel_name  = v_name,
            address      = nullif(btrim(p_address), ''),
            phone        = nullif(btrim(p_phone), ''),
            email        = nullif(btrim(p_email), ''),
            updated_date = now()
        WHERE hostel_id = p_hostel_id
        RETURNING hostel_id INTO v_id;

        IF v_id IS NULL THEN
            RAISE EXCEPTION 'This hostel no longer exists. It may have been deleted.'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN v_id;
EXCEPTION
    -- Two people saving the same name at the same moment.
    WHEN unique_violation THEN
        RAISE EXCEPTION 'A hostel named "%" already exists.', v_name USING ERRCODE = 'P0001';
END;
$$;

-- Deletes a hostel that has no students, colleges or rooms, with its sharing types.
CREATE OR REPLACE FUNCTION public.delete_hostel(p_hostel_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_hostel public.hostel_list;
BEGIN
    SELECT * INTO v_hostel FROM public.hostel_list WHERE hostel_id = p_hostel_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This hostel no longer exists.' USING ERRCODE = 'P0001';
    END IF;

    IF v_hostel.student_count > 0 OR v_hostel.college_count > 0 OR v_hostel.room_count > 0 THEN
        RAISE EXCEPTION '"%" cannot be deleted because it has % student(s), % college(s) and % room(s). Delete those first.',
            v_hostel.hostel_name, v_hostel.student_count, v_hostel.college_count, v_hostel.room_count
            USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.sharing_type WHERE hostel_id = p_hostel_id;
    DELETE FROM public.hostel WHERE hostel_id = p_hostel_id;
END;
$$;

-- Sharing types for the "Shri Balaji Hostel" added by 002 (it was added
-- directly, without save_hostel).
INSERT INTO public.sharing_type (hostel_id, sharing_name, capacity)
SELECT h.hostel_id, d.sharing_name, d.capacity
FROM public.hostel h
CROSS JOIN (VALUES ('Single', 1), ('Double', 2), ('Triple', 3)) AS d (sharing_name, capacity)
WHERE NOT EXISTS (SELECT 1 FROM public.sharing_type s WHERE s.hostel_id = h.hostel_id);

COMMIT;
