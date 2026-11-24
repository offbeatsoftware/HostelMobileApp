-- =====================================================================
-- Shri Balaji Hostel: Rooms screen (add, edit, delete rooms)
--
-- Run AFTER 001 to 004: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rules as the desktop RoomService:
--   * room numbers are unique within a hostel, ignoring capitals
--   * the sharing type (Single / Double / Triple) decides the number of beds
--   * a room is for boys (Male) or girls (Female)
--   * while students are in a room it cannot get fewer beds than students,
--     lose a bed that is in use, change between boys and girls, or be made
--     inactive
--   * a room that has ever had a student is kept for the records: it cannot
--     be deleted, only made inactive
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS ux_room_hostel_number_lower
    ON public.room (hostel_id, lower(room_number));

-- Rooms with their sharing type, beds and occupancy, for the list.
-- occupied = students in the room now (allocation status Current).
CREATE OR REPLACE VIEW public.room_list
WITH (security_invoker = true)
AS
SELECT r.room_id,
       r.hostel_id,
       r.room_number,
       r.floor,
       r.sharing_type_id,
       r.gender,
       r.is_active,
       r.remarks,
       s.sharing_name,
       s.capacity,
       (SELECT count(*) FROM public.room_allocation a
         WHERE a.room_id = r.room_id AND a.status = 'Current')::int AS occupied
FROM public.room r
JOIN public.sharing_type s ON s.sharing_type_id = r.sharing_type_id;

-- Adds a room to p_hostel_id (p_room_id NULL) or saves changes to an existing
-- room, which stays in its hostel. Returns the room_id.
CREATE OR REPLACE FUNCTION public.save_room(
    p_room_id         INTEGER,
    p_hostel_id       INTEGER,
    p_room_number     TEXT,
    p_floor           TEXT,
    p_sharing_type_id INTEGER,
    p_gender          TEXT,
    p_is_active       BOOLEAN,
    p_remarks         TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_number    TEXT := btrim(coalesce(p_room_number, ''));
    v_gender    TEXT := btrim(coalesce(p_gender, ''));
    v_active    BOOLEAN := coalesce(p_is_active, TRUE);
    v_hostel_id INTEGER;
    v_existing  public.room_list;
    v_sharing   public.sharing_type;
    v_max_bed   INTEGER;
    v_id        INTEGER;
BEGIN
    IF v_number = '' THEN
        RAISE EXCEPTION 'Please enter the room number.' USING ERRCODE = 'P0001';
    END IF;
    IF v_gender NOT IN ('Male', 'Female') THEN
        RAISE EXCEPTION 'Please select whether the room is for boys or girls.' USING ERRCODE = 'P0001';
    END IF;

    IF p_room_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM public.room_list WHERE room_id = p_room_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'This room no longer exists. It may have been deleted.' USING ERRCODE = 'P0001';
        END IF;
        v_hostel_id := v_existing.hostel_id;
    ELSE
        SELECT hostel_id INTO v_hostel_id FROM public.hostel WHERE hostel_id = p_hostel_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Please select a hostel first.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    SELECT * INTO v_sharing FROM public.sharing_type
     WHERE sharing_type_id = p_sharing_type_id AND hostel_id = v_hostel_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Please select the sharing type.' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM public.room
               WHERE hostel_id = v_hostel_id
                 AND lower(room_number) = lower(v_number)
                 AND room_id IS DISTINCT FROM p_room_id) THEN
        RAISE EXCEPTION 'Room number "%" already exists in this hostel.', v_number USING ERRCODE = 'P0001';
    END IF;

    IF p_room_id IS NOT NULL THEN
        IF v_existing.occupied > v_sharing.capacity THEN
            RAISE EXCEPTION 'Room % has % students, so it cannot be changed to % sharing (% %). Move students out first.',
                v_existing.room_number, v_existing.occupied, v_sharing.sharing_name, v_sharing.capacity,
                CASE WHEN v_sharing.capacity = 1 THEN 'bed' ELSE 'beds' END
                USING ERRCODE = 'P0001';
        END IF;

        SELECT max(bed_number) INTO v_max_bed FROM public.room_allocation
         WHERE room_id = p_room_id AND status = 'Current' AND bed_number > v_sharing.capacity;
        IF v_max_bed IS NOT NULL THEN
            RAISE EXCEPTION 'Bed % in room % is in use, so the room cannot be changed to % sharing. Transfer that student to another room first.',
                v_max_bed, v_existing.room_number, v_sharing.sharing_name USING ERRCODE = 'P0001';
        END IF;

        IF v_gender <> v_existing.gender AND v_existing.occupied > 0 THEN
            RAISE EXCEPTION 'Room % has % student(s), so it cannot be changed from % to %. Move the students out first.',
                v_existing.room_number, v_existing.occupied,
                CASE v_existing.gender WHEN 'Male' THEN 'Boys' ELSE 'Girls' END,
                CASE v_gender WHEN 'Male' THEN 'Boys' ELSE 'Girls' END
                USING ERRCODE = 'P0001';
        END IF;

        IF NOT v_active AND v_existing.occupied > 0 THEN
            RAISE EXCEPTION 'Room % has % student(s) and cannot be made inactive. Check out or transfer the students first.',
                v_existing.room_number, v_existing.occupied USING ERRCODE = 'P0001';
        END IF;

        UPDATE public.room
        SET room_number     = v_number,
            floor           = nullif(btrim(p_floor), ''),
            sharing_type_id = v_sharing.sharing_type_id,
            gender          = v_gender,
            is_active       = v_active,
            remarks         = nullif(btrim(p_remarks), '')
        WHERE room_id = p_room_id
        RETURNING room_id INTO v_id;
    ELSE
        INSERT INTO public.room (hostel_id, room_number, floor, sharing_type_id, gender, is_active, remarks)
        VALUES (v_hostel_id, v_number, nullif(btrim(p_floor), ''), v_sharing.sharing_type_id,
                v_gender, v_active, nullif(btrim(p_remarks), ''))
        RETURNING room_id INTO v_id;
    END IF;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Room number "%" already exists in this hostel.', v_number USING ERRCODE = 'P0001';
END;
$$;

-- Deletes a room that has never had a student.
CREATE OR REPLACE FUNCTION public.delete_room(p_room_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.room WHERE room_id = p_room_id) THEN
        RAISE EXCEPTION 'This room no longer exists.' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM public.room_allocation WHERE room_id = p_room_id) THEN
        RAISE EXCEPTION 'This room cannot be deleted because students have stayed in it. Edit the room and mark it inactive instead.'
            USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.room WHERE room_id = p_room_id;
END;
$$;

COMMIT;
