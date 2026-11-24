-- =====================================================================
-- Shri Balaji Hostel: Refunds
--
-- Run AFTER 001 to 011: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The same rules as the desktop RefundService:
--   * the admin pays back all or part of what was paid on a fee, any number
--     of times, also after the student has left
--   * a refund is never more than what is still paid on the fee after
--     earlier refunds; it lowers the fee by the same amount, so the pending
--     amount stays the same
--   * methods are those of payments; every method except cash needs a
--     reference; a reason is required
--   * refund numbers are SBH/RF/2026-2027/0001, one sequence per academic
--     year of the refund date
--   * a refund entered by mistake can be deleted with a reason; the deletion
--     is kept in the payment change history
-- The functions run with the caller's rights (SECURITY INVOKER), so the
-- access rules from 002 still decide who may use them.
-- =====================================================================

BEGIN;

-- The list also shows the invoice number (the new column goes last).
CREATE OR REPLACE VIEW public.refund_list
WITH (security_invoker = true)
AS
SELECT r.refund_id,
       r.refund_number,
       r.student_id,
       s.student_name,
       s.hostel_id,
       r.invoice_id,
       r.refund_date,
       r.amount,
       r.refund_method,
       r.reference,
       r.reason,
       i.invoice_number
FROM public.refund r
JOIN public.student s ON s.student_id = r.student_id
JOIN public.invoice i ON i.invoice_id = r.invoice_id;

-- Records a refund; returns its number.
CREATE OR REPLACE FUNCTION public.record_refund(
    p_invoice_id INTEGER,
    p_date       DATE,
    p_amount     NUMERIC,
    p_method     TEXT,
    p_reference  TEXT,
    p_reason     TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v         public.invoice_list;
    v_method  TEXT := btrim(coalesce(p_method, ''));
    v_ref     TEXT := btrim(coalesce(p_reference, ''));
    v_reason  TEXT := btrim(coalesce(p_reason, ''));
    v_refundable NUMERIC;
    v_label   TEXT;
    v_short   TEXT;
    v_prefix  TEXT;
    v_next    INTEGER;
    v_number  TEXT;
BEGIN
    -- Lock the invoice so two quick refunds cannot together exceed what was paid.
    PERFORM 1 FROM public.invoice WHERE invoice_id = p_invoice_id FOR UPDATE;
    SELECT * INTO v FROM public.invoice_list WHERE invoice_id = p_invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Please select the fee to refund from.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Please choose the refund date.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date > public.local_today() THEN
        RAISE EXCEPTION 'The refund date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF coalesce(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Please enter an amount greater than zero.' USING ERRCODE = 'P0001';
    END IF;
    IF round(p_amount, 2) <> p_amount THEN
        RAISE EXCEPTION 'The amount can have at most two decimal places (paise).' USING ERRCODE = 'P0001';
    END IF;
    IF v_method NOT IN ('Cash', 'UPI', 'Bank transfer', 'Cheque') THEN
        RAISE EXCEPTION 'Please select how the money was paid back.' USING ERRCODE = 'P0001';
    END IF;
    IF v_method <> 'Cash' AND v_ref = '' THEN
        RAISE EXCEPTION 'Please enter the %.',
            CASE v_method WHEN 'UPI' THEN 'upi transaction id'
                          WHEN 'Bank transfer' THEN 'bank reference'
                          ELSE 'cheque number' END USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = '' THEN
        RAISE EXCEPTION 'Please enter the reason for the refund, for example "left the hostel in December".'
            USING ERRCODE = 'P0001';
    END IF;
    IF length(v_ref) > 100 THEN
        RAISE EXCEPTION 'Reference can be at most 100 characters.' USING ERRCODE = 'P0001';
    END IF;
    IF length(v_reason) > 255 THEN
        RAISE EXCEPTION 'Reason can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;

    v_refundable := v.received_amount - v.refunded_amount;
    IF v_refundable <= 0 THEN
        RAISE EXCEPTION 'Nothing is paid on invoice %, so nothing can be refunded.', v.invoice_number
            USING ERRCODE = 'P0001';
    END IF;
    IF p_amount > v_refundable THEN
        RAISE EXCEPTION 'The refund cannot be more than %, the amount paid on invoice % after earlier refunds.',
            public.format_money(v_refundable), v.invoice_number USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('hostel numbers refund'));
    v_label := public.academic_year_label(public.academic_year_of(p_date));
    v_short := CASE WHEN public.academic_year_start_month() = 1
                    THEN public.academic_year_of(p_date)::text
                    ELSE public.academic_year_of(p_date) || '-'
                         || lpad(((public.academic_year_of(p_date) + 1) % 100)::text, 2, '0') END;
    v_prefix := 'SBH/RF/';
    SELECT coalesce(max(substring(refund_number FROM '([0-9]+)$')::int), 0) + 1 INTO v_next
      FROM public.refund
     WHERE refund_number LIKE v_prefix || v_label || '/%'
        OR refund_number LIKE v_prefix || v_short || '/%';
    v_number := v_prefix || v_label || '/' || lpad(v_next::text, 4, '0');

    INSERT INTO public.refund (refund_number, student_id, invoice_id, refund_date, amount,
                               refund_method, reference, reason)
    VALUES (v_number, v.student_id, p_invoice_id, p_date, p_amount, v_method,
            nullif(v_ref, ''), v_reason);
    RETURN v_number;
END;
$$;

-- Deletes a refund entered by mistake; the fee and the paid amount go back
-- up. The deletion is kept in the payment change history.
CREATE OR REPLACE FUNCTION public.delete_refund(p_refund_id INTEGER, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    r public.refund;
    v_invoice TEXT;
    v_reason  TEXT := btrim(coalesce(p_reason, ''));
BEGIN
    SELECT * INTO r FROM public.refund WHERE refund_id = p_refund_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This refund no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = '' THEN
        RAISE EXCEPTION 'Please enter the reason, for example "entered twice by mistake".'
            USING ERRCODE = 'P0001';
    END IF;
    IF length(v_reason) > 255 THEN
        RAISE EXCEPTION 'Reason can be at most 255 characters.' USING ERRCODE = 'P0001';
    END IF;
    SELECT invoice_number INTO v_invoice FROM public.invoice WHERE invoice_id = r.invoice_id;

    DELETE FROM public.refund WHERE refund_id = p_refund_id;
    -- payment_id 0: not a payment, so it stays out of any payment's own
    -- history; the number identifies the refund.
    INSERT INTO public.payment_change (payment_id, receipt_number, student_id, change_type, details, reason)
    VALUES (0, r.refund_number, r.student_id, 'Refund del',
            left('Deleted refund of ' || public.format_money(r.amount) || ' on '
                 || to_char(r.refund_date, 'DD Mon YYYY') || ' by ' || r.refund_method
                 || CASE WHEN coalesce(r.reference, '') <> '' THEN ' (ref. ' || r.reference || ')' ELSE '' END
                 || ', invoice ' || v_invoice, 255),
            v_reason);
END;
$$;

COMMIT;
