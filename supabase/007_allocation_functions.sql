-- =====================================================================
-- Shri Balaji Hostel: Room Allocation screen (check-in, transfer, check-out)
--
-- Run AFTER 001 to 006: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rules as the desktop AllocationService and InvoiceService:
--   * a student is in at most one room at a time; a bed holds one student
--   * check-in / transfer: an active student set as Male or Female, into an
--     active room of their hostel, for their gender, with a free bed; the
--     date is not before the admission (or current check-in) and not in the
--     future; the bed is chosen or the lowest free bed is used
--   * at check-in the yearly fee (room rent + transport) for the academic
--     year of the check-in date is entered, unless one already exists; it
--     becomes an invoice numbered SBH/2026-2027/0001 (one sequence per year)
--   * transfer: the old room is left and the new one entered on the same date
--   * check-out: the student's status becomes Left; a pending fee stays
--     pending, or is waived (the fee is reduced to what was paid)
-- "Today" is the date in India, not the server's UTC date.
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- One current room per student, one student per bed (safe against two
-- people checking in at the same moment).
CREATE UNIQUE INDEX IF NOT EXISTS ux_room_allocation_current_student
    ON public.room_allocation (student_id) WHERE status = 'Current';
CREATE UNIQUE INDEX IF NOT EXISTS ux_room_allocation_current_bed
    ON public.room_allocation (room_id, bed_number)
    WHERE status = 'Current' AND bed_number IS NOT NULL;

-- Today's date in India.
CREATE OR REPLACE FUNCTION public.local_today()
RETURNS DATE
LANGUAGE sql
STABLE
SET search_path = ''
AS $$ SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date $$;

-- The month the academic year starts (AppSetting AcademicYear.StartMonth,
-- July when not set), as on the desktop.
CREATE OR REPLACE FUNCTION public.academic_year_start_month()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(
        (SELECT setting_value::int FROM public.app_setting
          WHERE setting_key = 'AcademicYear.StartMonth'
            AND setting_value ~ '^(1[0-2]|[1-9])$'),
        7)
$$;

-- The academic year (its starting calendar year) that contains the date.
CREATE OR REPLACE FUNCTION public.academic_year_of(p_date DATE)
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
    SELECT CASE WHEN extract(month FROM p_date) >= public.academic_year_start_month()
                THEN extract(year FROM p_date)::int
                ELSE extract(year FROM p_date)::int - 1 END
$$;

-- "2026-2027" (or "2026" when the year runs January to December).
CREATE OR REPLACE FUNCTION public.academic_year_label(p_year INTEGER)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
    SELECT CASE WHEN public.academic_year_start_month() = 1 THEN p_year::text
                ELSE p_year || '-' || (p_year + 1) END
$$;

-- Invoices with what was received, refunded and is still pending.
-- pending = room rent + transport - waived - payments received.
CREATE OR REPLACE VIEW public.invoice_list
WITH (security_invoker = true)
AS
SELECT i.*,
       s.student_name,
       s.hostel_id,
       coalesce((SELECT sum(p.amount) FROM public.payment p WHERE p.invoice_id = i.invoice_id), 0) AS received_amount,
       coalesce((SELECT sum(r.amount) FROM public.refund r  WHERE r.invoice_id = i.invoice_id), 0) AS refunded_amount,
       i.room_rent + i.transport_amount - coalesce(i.waived_amount, 0)
         - coalesce((SELECT sum(p.amount) FROM public.payment p WHERE p.invoice_id = i.invoice_id), 0) AS pending_amount
FROM public.invoice i
JOIN public.student s ON s.student_id = i.student_id;

-- Allocations with the student and room, for the list.
CREATE OR REPLACE VIEW public.allocation_list
WITH (security_invoker = true)
AS
SELECT a.allocation_id,
       a.student_id,
       s.student_name,
       s.mobile AS student_mobile,
       a.room_id,
       r.room_number,
       r.hostel_id,
       a.bed_number,
       a.check_in_date,
       a.check_out_date,
       a.status,
       a.remarks
FROM public.room_allocation a
JOIN public.student s ON s.student_id = a.student_id
JOIN public.room r    ON r.room_id = a.room_id;

-- ---------------------------------------------------------------------
-- Shared checks
-- ---------------------------------------------------------------------

-- The student, who must be active and Male or Female.
CREATE OR REPLACE FUNCTION public._student_for_allocation(p_student_id INTEGER)
RETURNS public.student
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v public.student;
BEGIN
    SELECT * INTO v FROM public.student WHERE student_id = p_student_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Please select the student.' USING ERRCODE = 'P0001';
    END IF;
    IF v.status <> 'Active' THEN
        RAISE EXCEPTION '%''s status is %. Set the status to Active on the Students screen first.',
            v.student_name, v.status USING ERRCODE = 'P0001';
    END IF;
    IF coalesce(v.gender, '') NOT IN ('Male', 'Female') THEN
        RAISE EXCEPTION 'Please set %''s gender (Male or Female) on the Students screen first. Rooms are for boys or girls.',
            v.student_name USING ERRCODE = 'P0001';
    END IF;
    RETURN v;
END;
$$;

-- Checks the room for the student and returns the bed to use: the
-- requested one when free, otherwise the lowest free bed.
CREATE OR REPLACE FUNCTION public._bed_for(p_student public.student, p_room_id INTEGER, p_bed INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_room   public.room;
    v_cap    INTEGER;
    v_taken  INTEGER[];
    v_free   INTEGER;
BEGIN
    -- Lock the room so two check-ins cannot take the same bed.
    SELECT * INTO v_room FROM public.room WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This room no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    SELECT capacity INTO v_cap FROM public.sharing_type WHERE sharing_type_id = v_room.sharing_type_id;
    SELECT coalesce(array_agg(bed_number), '{}') INTO v_taken
      FROM public.room_allocation WHERE room_id = p_room_id AND status = 'Current';

    IF NOT v_room.is_active THEN
        RAISE EXCEPTION 'Room % is inactive. Students cannot be allocated to it.', v_room.room_number USING ERRCODE = 'P0001';
    END IF;
    IF cardinality(v_taken) >= v_cap THEN
        RAISE EXCEPTION 'Room % is full (% of % beds occupied).', v_room.room_number, cardinality(v_taken), v_cap
            USING ERRCODE = 'P0001';
    END IF;
    IF v_room.hostel_id <> p_student.hostel_id THEN
        RAISE EXCEPTION 'Room % belongs to another hostel.', v_room.room_number USING ERRCODE = 'P0001';
    END IF;
    IF v_room.gender <> p_student.gender THEN
        RAISE EXCEPTION 'Room % is for %. % cannot be allocated to it.', v_room.room_number,
            CASE v_room.gender WHEN 'Male' THEN 'boys' ELSE 'girls' END, p_student.student_name USING ERRCODE = 'P0001';
    END IF;

    IF p_bed IS NOT NULL THEN
        IF p_bed < 1 OR p_bed > v_cap THEN
            RAISE EXCEPTION 'Room % has beds 1 to %.', v_room.room_number, v_cap USING ERRCODE = 'P0001';
        END IF;
        IF p_bed = ANY (v_taken) THEN
            RAISE EXCEPTION 'Bed % in room % is already taken.', p_bed, v_room.room_number USING ERRCODE = 'P0001';
        END IF;
        RETURN p_bed;
    END IF;

    SELECT min(b) INTO v_free FROM generate_series(1, v_cap) AS b WHERE NOT (b = ANY (v_taken));
    IF v_free IS NULL THEN
        RAISE EXCEPTION 'Room % has no free bed.', v_room.room_number USING ERRCODE = 'P0001';
    END IF;
    RETURN v_free;
END;
$$;

CREATE OR REPLACE FUNCTION public._check_date(p_date DATE, p_action TEXT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Please choose the % date.', p_action USING ERRCODE = 'P0001';
    END IF;
    IF p_date > public.local_today() THEN
        RAISE EXCEPTION 'The % date cannot be in the future.', p_action USING ERRCODE = 'P0001';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._check_amount(p_amount NUMERIC, p_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF p_amount < 0 THEN
        RAISE EXCEPTION 'The % cannot be negative.', p_name USING ERRCODE = 'P0001';
    END IF;
    IF p_amount > 10000000 THEN
        RAISE EXCEPTION 'The % cannot be more than ₹1,00,00,000.00.', p_name USING ERRCODE = 'P0001';
    END IF;
    IF round(p_amount, 2) <> p_amount THEN
        RAISE EXCEPTION 'The % can have at most two decimal places (paise).', p_name USING ERRCODE = 'P0001';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._clean_remarks(p_remarks TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v TEXT := btrim(coalesce(p_remarks, ''));
BEGIN
    IF length(v) > 255 THEN
        RAISE EXCEPTION 'Remarks can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v;
END;
$$;

-- Keeps the check-in remarks and adds the closing remarks, within 255 characters.
CREATE OR REPLACE FUNCTION public._join_remarks(p_existing TEXT, p_added TEXT)
RETURNS TEXT
LANGUAGE sql
SET search_path = ''
AS $$
    SELECT nullif(left(CASE WHEN coalesce(p_existing, '') = '' THEN p_added
                            WHEN p_added = '' THEN p_existing
                            ELSE p_existing || ' | ' || p_added END, 255), '')
$$;

-- ---------------------------------------------------------------------
-- Check-in, transfer, check-out
-- ---------------------------------------------------------------------

-- Puts a student in a room and bed (the lowest free bed when p_bed is NULL).
-- With p_room_rent the yearly fee is created too. Returns the allocation_id.
CREATE OR REPLACE FUNCTION public.check_in(
    p_student_id INTEGER,
    p_room_id    INTEGER,
    p_date       DATE,
    p_remarks    TEXT,
    p_bed        INTEGER,
    p_room_rent  NUMERIC,
    p_transport  NUMERIC)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_student public.student;
    v_room    TEXT;
    v_remarks TEXT;
    v_bed     INTEGER;
    v_year    INTEGER;
    v_label   TEXT;
    v_short   TEXT;
    v_next    INTEGER;
    v_number  TEXT;
    v_id      INTEGER;
    v_existing public.invoice;
BEGIN
    v_student := public._student_for_allocation(p_student_id);

    SELECT r.room_number INTO v_room FROM public.room_allocation a JOIN public.room r ON r.room_id = a.room_id
     WHERE a.student_id = p_student_id AND a.status = 'Current';
    IF v_room IS NOT NULL THEN
        RAISE EXCEPTION '% is already in room %. Use Transfer to move the student.', v_student.student_name, v_room
            USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NOT NULL AND p_date < v_student.admission_date THEN
        RAISE EXCEPTION 'The check-in date cannot be before the admission date (%).',
            to_char(v_student.admission_date, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_date(p_date, 'check-in');
    v_remarks := public._clean_remarks(p_remarks);
    v_bed := public._bed_for(v_student, p_room_id, p_bed);

    v_year := public.academic_year_of(p_date);
    IF p_room_rent IS NOT NULL THEN
        PERFORM public._check_amount(p_room_rent, 'room rent');
        IF p_room_rent <= 0 THEN
            RAISE EXCEPTION 'Please enter the room rent for the year.' USING ERRCODE = 'P0001';
        END IF;
        PERFORM public._check_amount(coalesce(p_transport, 0), 'transport amount');
        SELECT * INTO v_existing FROM public.invoice WHERE student_id = p_student_id AND academic_year = v_year;
        IF FOUND THEN
            RAISE EXCEPTION '% already has a fee for % (invoice %). Use Edit Fee on the Invoices screen to change it.',
                v_student.student_name, public.academic_year_label(v_year), v_existing.invoice_number
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    INSERT INTO public.room_allocation (student_id, room_id, check_in_date, status, remarks, bed_number)
    VALUES (p_student_id, p_room_id, p_date, 'Current', nullif(v_remarks, ''), v_bed)
    RETURNING allocation_id INTO v_id;

    IF p_room_rent IS NOT NULL THEN
        -- One invoice number sequence per academic year; numbers made with
        -- the desktop's earlier short year (SBH/2026-27/0003) count too.
        PERFORM pg_advisory_xact_lock(hashtext('hostel invoice numbers'));
        v_label := public.academic_year_label(v_year);
        v_short := CASE WHEN public.academic_year_start_month() = 1 THEN v_year::text
                        ELSE v_year || '-' || lpad(((v_year + 1) % 100)::text, 2, '0') END;
        SELECT coalesce(max(substring(invoice_number FROM '([0-9]+)$')::int), 0) + 1 INTO v_next
          FROM public.invoice
         WHERE invoice_number LIKE 'SBH/' || v_label || '/%'
            OR invoice_number LIKE 'SBH/' || v_short || '/%';
        v_number := 'SBH/' || v_label || '/' || lpad(v_next::text, 4, '0');

        INSERT INTO public.invoice (invoice_number, student_id, invoice_date, academic_year,
                                    room_rent, transport_amount, remarks)
        VALUES (v_number, p_student_id, p_date, v_year, p_room_rent, coalesce(p_transport, 0), NULL);
    END IF;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'The room or bed was taken in the meantime. Please refresh and try again.'
            USING ERRCODE = 'P0001';
END;
$$;

-- Moves a student to another room: the old allocation ends and the new one
-- starts on the same date. Returns the new allocation_id.
CREATE OR REPLACE FUNCTION public.transfer_room(
    p_student_id  INTEGER,
    p_new_room_id INTEGER,
    p_date        DATE,
    p_remarks     TEXT,
    p_bed         INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_student public.student;
    v_current public.room_allocation;
    v_room    TEXT;
    v_remarks TEXT;
    v_bed     INTEGER;
    v_id      INTEGER;
BEGIN
    v_student := public._student_for_allocation(p_student_id);
    SELECT * INTO v_current FROM public.room_allocation
     WHERE student_id = p_student_id AND status = 'Current' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '% is not in a room. Use Check-in instead.', v_student.student_name USING ERRCODE = 'P0001';
    END IF;
    SELECT room_number INTO v_room FROM public.room WHERE room_id = v_current.room_id;
    IF p_new_room_id = v_current.room_id THEN
        RAISE EXCEPTION '% is already in room %.', v_student.student_name, v_room USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NOT NULL AND p_date < v_current.check_in_date THEN
        RAISE EXCEPTION 'The transfer date cannot be before the check-in date (%).',
            to_char(v_current.check_in_date, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_date(p_date, 'transfer');
    v_remarks := public._clean_remarks(p_remarks);
    v_bed := public._bed_for(v_student, p_new_room_id, p_bed);

    UPDATE public.room_allocation
       SET check_out_date = p_date, status = 'Transferred',
           remarks = public._join_remarks(v_current.remarks, v_remarks)
     WHERE allocation_id = v_current.allocation_id;

    INSERT INTO public.room_allocation (student_id, room_id, check_in_date, status, remarks, bed_number)
    VALUES (p_student_id, p_new_room_id, p_date, 'Current', nullif(v_remarks, ''), v_bed)
    RETURNING allocation_id INTO v_id;
    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'The room or bed was taken in the meantime. Please refresh and try again.'
            USING ERRCODE = 'P0001';
END;
$$;

-- Checks the student out; the status becomes Left. With p_waive the rest of
-- each pending fee is waived.
CREATE OR REPLACE FUNCTION public.check_out(
    p_student_id INTEGER,
    p_date       DATE,
    p_remarks    TEXT,
    p_waive      BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_student public.student;
    v_current public.room_allocation;
    v_remarks TEXT;
BEGIN
    SELECT * INTO v_student FROM public.student WHERE student_id = p_student_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This student no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_current FROM public.room_allocation
     WHERE student_id = p_student_id AND status = 'Current' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '% is not in a room.', v_student.student_name USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NOT NULL AND p_date < v_current.check_in_date THEN
        RAISE EXCEPTION 'The check-out date cannot be before the check-in date (%).',
            to_char(v_current.check_in_date, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_date(p_date, 'check-out');
    v_remarks := public._clean_remarks(p_remarks);

    UPDATE public.room_allocation
       SET check_out_date = p_date, status = 'CheckedOut',
           remarks = public._join_remarks(v_current.remarks, v_remarks)
     WHERE allocation_id = v_current.allocation_id;

    UPDATE public.student SET status = 'Left' WHERE student_id = p_student_id;

    IF coalesce(p_waive, FALSE) THEN
        UPDATE public.invoice i
           SET waived_amount = coalesce(i.waived_amount, 0) + l.pending_amount
          FROM public.invoice_list l
         WHERE l.invoice_id = i.invoice_id
           AND i.student_id = p_student_id
           AND l.pending_amount > 0;
    END IF;
END;
$$;

COMMIT;
