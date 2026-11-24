-- =====================================================================
-- Shri Balaji Hostel: Dashboard
--
-- Run AFTER 001 to 008: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The dashboard shows money received net of the refunds paid back in the
-- same period (as the desktop does), so it needs the hostel's refunds.
-- =====================================================================

BEGIN;

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
       r.reason
FROM public.refund r
JOIN public.student s ON s.student_id = r.student_id;

COMMIT;
