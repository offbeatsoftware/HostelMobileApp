-- =====================================================================
-- Shri Balaji Hostel: Invoices and Payments screens
--
-- Run AFTER 001 to 007: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rules as the desktop InvoiceService and PaymentService:
--   * a fee can be changed, but (less any waived part) never below the
--     payments already received
--   * an invoice with payments, refunds or emails cannot be deleted
--   * New Year Fees: a fee for each student in a room who has none for the
--     year; every fee is checked before any is saved
--   * a payment is never more than the fee still pending (no advance or
--     extra payments); cash, UPI, bank transfer or cheque, and every method
--     except cash needs a reference; receipts are numbered
--     SBH/R/2026-2027/0001, one sequence per academic year of the payment
--   * a payment can be corrected or deleted with a reason; every change is
--     kept in the change history; payments cannot drop below what was
--     refunded
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- ₹2,68,500.00 (Indian grouping), as the desktop shows amounts.
CREATE OR REPLACE FUNCTION public.format_money(p_amount NUMERIC)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_fixed TEXT := to_char(abs(p_amount), 'FM999999999990.00');
    v_whole TEXT := split_part(v_fixed, '.', 1);
    v_paise TEXT := split_part(v_fixed, '.', 2);
    v_head  TEXT;
    v_out   TEXT;
BEGIN
    IF length(v_whole) > 3 THEN
        v_head := left(v_whole, length(v_whole) - 3);
        v_out := right(v_whole, 3);
        WHILE length(v_head) > 2 LOOP
            v_out := right(v_head, 2) || ',' || v_out;
            v_head := left(v_head, length(v_head) - 2);
        END LOOP;
        v_out := v_head || ',' || v_out;
    ELSE
        v_out := v_whole;
    END IF;
    RETURN CASE WHEN p_amount < 0 THEN '-' ELSE '' END || '₹' || v_out || '.' || v_paise;
END;
$$;

-- The next number of a sequence such as SBH/2026-2027/0001 or
-- SBH/R/2026-2027/0001, counting numbers made with the desktop's earlier
-- short year (SBH/2026-27/0003). p_table is 'invoice' or 'payment'.
CREATE OR REPLACE FUNCTION public._next_number(p_table TEXT, p_prefix TEXT, p_year INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_label TEXT := public.academic_year_label(p_year);
    v_short TEXT := CASE WHEN public.academic_year_start_month() = 1 THEN p_year::text
                         ELSE p_year || '-' || lpad(((p_year + 1) % 100)::text, 2, '0') END;
    v_next  INTEGER;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('hostel numbers ' || p_table));
    IF p_table = 'invoice' THEN
        SELECT coalesce(max(substring(invoice_number FROM '([0-9]+)$')::int), 0) + 1 INTO v_next
          FROM public.invoice
         WHERE invoice_number LIKE p_prefix || '/' || v_label || '/%'
            OR invoice_number LIKE p_prefix || '/' || v_short || '/%';
    ELSE
        SELECT coalesce(max(substring(receipt_number FROM '([0-9]+)$')::int), 0) + 1 INTO v_next
          FROM public.payment
         WHERE receipt_number LIKE p_prefix || '/' || v_label || '/%'
            OR receipt_number LIKE p_prefix || '/' || v_short || '/%';
    END IF;
    RETURN p_prefix || '/' || v_label || '/' || lpad(v_next::text, 4, '0');
END;
$$;

-- Payments with the student and invoice, for the list.
CREATE OR REPLACE VIEW public.payment_list
WITH (security_invoker = true)
AS
SELECT p.*,
       s.student_name,
       s.hostel_id,
       i.invoice_number,
       i.academic_year
FROM public.payment p
JOIN public.student s ON s.student_id = p.student_id
JOIN public.invoice i ON i.invoice_id = p.invoice_id;

-- Corrections and deletions of payments, for the change history.
CREATE OR REPLACE VIEW public.payment_change_list
WITH (security_invoker = true)
AS
SELECT c.*,
       s.student_name,
       s.hostel_id
FROM public.payment_change c
JOIN public.student s ON s.student_id = c.student_id;

-- ---------------------------------------------------------------------
-- Invoices
-- ---------------------------------------------------------------------

-- Checks a yearly fee as the desktop ValidateFee does.
CREATE OR REPLACE FUNCTION public._check_fee(p_rent NUMERIC, p_transport NUMERIC, p_remarks TEXT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    PERFORM public._check_amount(coalesce(p_rent, 0), 'room rent');
    IF coalesce(p_rent, 0) <= 0 THEN
        RAISE EXCEPTION 'Please enter the room rent for the year.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_amount(coalesce(p_transport, 0), 'transport amount');
    IF length(btrim(coalesce(p_remarks, ''))) > 255 THEN
        RAISE EXCEPTION 'Remarks can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;
END;
$$;

-- Changes the room rent and transport of an invoice.
CREATE OR REPLACE FUNCTION public.update_fee(
    p_invoice_id INTEGER,
    p_room_rent  NUMERIC,
    p_transport  NUMERIC,
    p_remarks    TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v public.invoice_list;
    v_total NUMERIC;
BEGIN
    PERFORM 1 FROM public.invoice WHERE invoice_id = p_invoice_id FOR UPDATE;
    SELECT * INTO v FROM public.invoice_list WHERE invoice_id = p_invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This invoice no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_fee(p_room_rent, p_transport, p_remarks);

    v_total := p_room_rent + coalesce(p_transport, 0);
    IF v_total - coalesce(v.waived_amount, 0) < v.received_amount THEN
        RAISE EXCEPTION '%', public.format_money(v.received_amount) || ' has already been paid against invoice '
            || v.invoice_number
            || CASE WHEN coalesce(v.waived_amount, 0) > 0
                    THEN ' and ' || public.format_money(v.waived_amount) || ' was waived' ELSE '' END
            || '. The new total cannot be less than that.'
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.invoice
       SET room_rent = p_room_rent,
           transport_amount = coalesce(p_transport, 0),
           remarks = nullif(btrim(p_remarks), '')
     WHERE invoice_id = p_invoice_id;
END;
$$;

-- Deletes an invoice that has no payments, refunds or emails.
CREATE OR REPLACE FUNCTION public.delete_invoice(p_invoice_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_number TEXT;
BEGIN
    SELECT invoice_number INTO v_number FROM public.invoice WHERE invoice_id = p_invoice_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This invoice no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM public.payment       WHERE invoice_id = p_invoice_id)
       OR EXISTS (SELECT 1 FROM public.refund        WHERE invoice_id = p_invoice_id)
       OR EXISTS (SELECT 1 FROM public.email_history WHERE invoice_id = p_invoice_id) THEN
        RAISE EXCEPTION 'Invoice % has payments or emails and cannot be deleted. Use Edit Fee to change it.',
            v_number USING ERRCODE = 'P0001';
    END IF;
    DELETE FROM public.invoice WHERE invoice_id = p_invoice_id;
END;
$$;

-- Creates the fees entered on the New Year Fees screen:
-- p_fees = [{"student_id": 1, "room_rent": 85000, "transport": 12000}, ...].
-- Every fee is checked before any is saved. Returns how many were created.
CREATE OR REPLACE FUNCTION public.create_year_fees(p_year INTEGER, p_fees JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    f        JSONB;
    v_name   TEXT;
    v_count  INTEGER := 0;
    v_today  DATE := public.local_today();
BEGIN
    IF p_fees IS NULL OR jsonb_array_length(p_fees) = 0 THEN
        RAISE EXCEPTION 'Please enter the room rent for at least one student.' USING ERRCODE = 'P0001';
    END IF;
    IF p_year < 2000 OR p_year > public.academic_year_of(v_today) + 1 THEN
        RAISE EXCEPTION 'Please choose this academic year or the next one.' USING ERRCODE = 'P0001';
    END IF;

    -- Check everything first.
    FOR f IN SELECT * FROM jsonb_array_elements(p_fees) LOOP
        SELECT student_name INTO v_name FROM public.student WHERE student_id = (f ->> 'student_id')::int;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A student in the list no longer exists. Please refresh.' USING ERRCODE = 'P0001';
        END IF;
        BEGIN
            PERFORM public._check_fee((f ->> 'room_rent')::numeric, (f ->> 'transport')::numeric, NULL);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE EXCEPTION '%: %', v_name, SQLERRM USING ERRCODE = 'P0001';
        END;
        IF EXISTS (SELECT 1 FROM public.invoice
                    WHERE student_id = (f ->> 'student_id')::int AND academic_year = p_year) THEN
            RAISE EXCEPTION '% already has a fee for %. Use Edit Fee to change it.',
                v_name, public.academic_year_label(p_year) USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    FOR f IN SELECT * FROM jsonb_array_elements(p_fees) LOOP
        INSERT INTO public.invoice (invoice_number, student_id, invoice_date, academic_year, room_rent, transport_amount)
        VALUES (public._next_number('invoice', 'SBH', p_year), (f ->> 'student_id')::int, v_today, p_year,
                (f ->> 'room_rent')::numeric, coalesce((f ->> 'transport')::numeric, 0));
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'A fee was added for one of these students in the meantime. Please refresh and try again.'
            USING ERRCODE = 'P0001';
END;
$$;

-- ---------------------------------------------------------------------
-- Payments
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._check_payment(
    p_date DATE, p_amount NUMERIC, p_method TEXT, p_reference TEXT, p_remarks TEXT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Please choose the payment date.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date > public.local_today() THEN
        RAISE EXCEPTION 'The payment date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF coalesce(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Please enter an amount greater than zero.' USING ERRCODE = 'P0001';
    END IF;
    IF round(p_amount, 2) <> p_amount THEN
        RAISE EXCEPTION 'The amount can have at most two decimal places (paise).' USING ERRCODE = 'P0001';
    END IF;
    IF coalesce(p_method, '') NOT IN ('Cash', 'UPI', 'Bank transfer', 'Cheque') THEN
        RAISE EXCEPTION 'Please select how the payment was made.' USING ERRCODE = 'P0001';
    END IF;
    IF p_method <> 'Cash' AND btrim(coalesce(p_reference, '')) = '' THEN
        RAISE EXCEPTION 'Please enter the %.',
            CASE p_method WHEN 'UPI' THEN 'upi transaction id'
                          WHEN 'Bank transfer' THEN 'bank reference'
                          ELSE 'cheque number' END USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_reference, ''))) > 100 THEN
        RAISE EXCEPTION 'Reference can be at most 100 characters.' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_remarks, ''))) > 255 THEN
        RAISE EXCEPTION 'Remarks can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;
END;
$$;

-- Payments may not drop below the money already refunded on the fee.
CREATE OR REPLACE FUNCTION public._check_refunds_covered(p_invoice_id INTEGER, p_reduction NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v public.invoice_list;
BEGIN
    SELECT * INTO v FROM public.invoice_list WHERE invoice_id = p_invoice_id;
    IF v.refunded_amount > 0 AND v.received_amount - p_reduction < v.refunded_amount THEN
        RAISE EXCEPTION '% has been refunded on invoice %, so the payments cannot be less than that. Delete the refund first if it was a mistake.',
            public.format_money(v.refunded_amount), v.invoice_number USING ERRCODE = 'P0001';
    END IF;
END;
$$;

-- Records a payment against an invoice; returns the receipt number.
CREATE OR REPLACE FUNCTION public.record_payment(
    p_invoice_id INTEGER,
    p_date       DATE,
    p_amount     NUMERIC,
    p_method     TEXT,
    p_reference  TEXT,
    p_remarks    TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v public.invoice_list;
    v_pending NUMERIC;
    v_number  TEXT;
BEGIN
    -- Lock the invoice so two quick payments cannot together exceed it.
    PERFORM 1 FROM public.invoice WHERE invoice_id = p_invoice_id FOR UPDATE;
    SELECT * INTO v FROM public.invoice_list WHERE invoice_id = p_invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Please select the invoice.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_payment(p_date, p_amount, btrim(p_method), p_reference, p_remarks);

    v_pending := v.pending_amount;
    IF v_pending <= 0 THEN
        RAISE EXCEPTION 'Invoice % is already fully paid.', v.invoice_number USING ERRCODE = 'P0001';
    END IF;
    IF p_amount > v_pending THEN
        RAISE EXCEPTION 'The amount cannot be more than the pending amount of %. Advance or extra payments are not accepted.',
            public.format_money(v_pending) USING ERRCODE = 'P0001';
    END IF;

    v_number := public._next_number('payment', 'SBH/R', public.academic_year_of(p_date));
    INSERT INTO public.payment (receipt_number, student_id, invoice_id, payment_date, amount,
                                payment_method, reference, remarks)
    VALUES (v_number, v.student_id, p_invoice_id, p_date, p_amount, btrim(p_method),
            nullif(btrim(p_reference), ''), nullif(btrim(p_remarks), ''));
    RETURN v_number;
END;
$$;

-- Corrects a payment entered wrongly; the receipt number stays and the
-- change is kept in the history.
CREATE OR REPLACE FUNCTION public.edit_payment(
    p_payment_id INTEGER,
    p_date       DATE,
    p_amount     NUMERIC,
    p_method     TEXT,
    p_reference  TEXT,
    p_remarks    TEXT,
    p_reason     TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    p public.payment;
    v public.invoice_list;
    v_ref     TEXT := btrim(coalesce(p_reference, ''));
    v_rem     TEXT := btrim(coalesce(p_remarks, ''));
    v_reason  TEXT := btrim(coalesce(p_reason, ''));
    v_parts   TEXT[] := '{}';
    v_allowed NUMERIC;
BEGIN
    SELECT * INTO p FROM public.payment WHERE payment_id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This payment no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_payment(p_date, p_amount, btrim(p_method), v_ref, v_rem);
    IF length(v_reason) > 255 THEN
        RAISE EXCEPTION 'Reason can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;

    IF p.payment_date <> p_date THEN
        v_parts := v_parts || ('Date ' || to_char(p.payment_date, 'DD Mon YYYY') || ' to ' || to_char(p_date, 'DD Mon YYYY'));
    END IF;
    IF p.amount <> p_amount THEN
        v_parts := v_parts || ('Amount ' || public.format_money(p.amount) || ' to ' || public.format_money(p_amount));
    END IF;
    IF p.payment_method <> btrim(p_method) THEN
        v_parts := v_parts || ('Paid by ' || p.payment_method || ' to ' || btrim(p_method));
    END IF;
    IF coalesce(p.reference, '') <> v_ref THEN
        v_parts := v_parts || ('Reference ''' || coalesce(p.reference, '') || ''' to ''' || v_ref || '''');
    END IF;
    IF coalesce(p.remarks, '') <> v_rem THEN
        v_parts := v_parts || 'Remarks changed'::text;
    END IF;
    IF cardinality(v_parts) = 0 THEN
        RAISE EXCEPTION 'Nothing was changed.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM 1 FROM public.invoice WHERE invoice_id = p.invoice_id FOR UPDATE;
    SELECT * INTO v FROM public.invoice_list WHERE invoice_id = p.invoice_id;
    -- The other payments plus this one may not exceed the fee.
    v_allowed := v.pending_amount + p.amount;
    IF p_amount > v_allowed THEN
        RAISE EXCEPTION 'The amount cannot be more than %, the fee still open without this payment. Advance or extra payments are not accepted.',
            public.format_money(v_allowed) USING ERRCODE = 'P0001';
    END IF;
    PERFORM public._check_refunds_covered(p.invoice_id, p.amount - p_amount);

    UPDATE public.payment
       SET payment_date = p_date, amount = p_amount, payment_method = btrim(p_method),
           reference = nullif(v_ref, ''), remarks = nullif(v_rem, '')
     WHERE payment_id = p_payment_id;

    INSERT INTO public.payment_change (payment_id, receipt_number, student_id, change_type, details, reason)
    VALUES (p.payment_id, p.receipt_number, p.student_id, 'Edited',
            left(array_to_string(v_parts, '; '), 255), nullif(v_reason, ''));
END;
$$;

-- Deletes a payment entered by mistake; the deletion is kept in the history.
CREATE OR REPLACE FUNCTION public.delete_payment(p_payment_id INTEGER, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    p public.payment;
    v_invoice TEXT;
    v_reason  TEXT := btrim(coalesce(p_reason, ''));
BEGIN
    SELECT * INTO p FROM public.payment WHERE payment_id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This payment no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    IF length(v_reason) > 255 THEN
        RAISE EXCEPTION 'Reason can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;
    SELECT invoice_number INTO v_invoice FROM public.invoice WHERE invoice_id = p.invoice_id FOR UPDATE;
    PERFORM public._check_refunds_covered(p.invoice_id, p.amount);

    DELETE FROM public.payment WHERE payment_id = p_payment_id;
    INSERT INTO public.payment_change (payment_id, receipt_number, student_id, change_type, details, reason)
    VALUES (p.payment_id, p.receipt_number, p.student_id, 'Deleted',
            left('Deleted ' || public.format_money(p.amount) || ' paid on ' || to_char(p.payment_date, 'DD Mon YYYY')
                 || ' by ' || p.payment_method
                 || CASE WHEN coalesce(p.reference, '') <> '' THEN ' (ref. ' || p.reference || ')' ELSE '' END
                 || ', invoice ' || v_invoice, 255),
            nullif(v_reason, ''));
END;
$$;

COMMIT;
