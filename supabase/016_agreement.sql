-- =====================================================================
-- Shri Balaji Hostel: student agreement and its signatures
--
-- Run AFTER 001 to 015: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The agreement text is kept in app_setting "Agreement.Text" (the same key
-- as the desktop, so both programs share the wording).
--
-- Signatures are PNG images in a private Storage bucket, "signatures":
--   S12_student.png, S12_parent.png, S12_witness.png, S12_owner.png
--   for student 12, and H3_owner.png, the owner's signature saved once for
--   hostel 3 and used on every agreement of that hostel.
-- The date the agreement was signed and the witness's name are kept in the
-- table agreement_signing. The desktop keeps its own signatures as files on
-- the PC, which the phone cannot read, so the two are separate.
--
-- Only the signed in admin (is_hostel_admin(), script 002) can use them.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.agreement_signing (
    student_id   INTEGER      NOT NULL CONSTRAINT pk_agreement_signing PRIMARY KEY,
    signed_date  DATE         NOT NULL,
    witness_name VARCHAR(100),
    CONSTRAINT fk_agreement_signing_student FOREIGN KEY (student_id)
        REFERENCES public.student (student_id) ON DELETE CASCADE
);

ALTER TABLE public.agreement_signing ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hostel_admin_all ON public.agreement_signing;
CREATE POLICY hostel_admin_all ON public.agreement_signing
    FOR ALL TO authenticated
    USING (public.is_hostel_admin())
    WITH CHECK (public.is_hostel_admin());

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('signatures', 'signatures', false, 2097152, ARRAY['image/png'])
ON CONFLICT (id) DO UPDATE
   SET public = false,
       file_size_limit = 2097152,
       allowed_mime_types = ARRAY['image/png'];

DROP POLICY IF EXISTS hostel_admin_signatures ON storage.objects;
CREATE POLICY hostel_admin_signatures ON storage.objects
    FOR ALL TO authenticated
    USING (bucket_id = 'signatures' AND public.is_hostel_admin())
    WITH CHECK (bucket_id = 'signatures' AND public.is_hostel_admin());

COMMIT;
