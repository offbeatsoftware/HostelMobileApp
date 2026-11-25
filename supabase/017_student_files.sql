-- =====================================================================
-- Shri Balaji Hostel: student photos and Aadhaar card scans
--
-- Run AFTER 001 to 016: Supabase Dashboard > SQL Editor. Safe to run again.
--
-- The files are kept in a private Supabase Storage bucket, "student-files":
--   S12_photo_20261125103000.jpg      the student's photo
--   S12_aadhaar_20261125103000.pdf    the Aadhaar card (jpg, png or pdf)
-- The file name is saved on the student (student.photo_path and
-- student.aadhaar_card_path, columns that already exist), so the lists know
-- who has a photo. A new upload gets a new name and the old file is deleted.
--
-- At most 5 MB per file (JPG, PNG or PDF; the app shrinks pictures first).
-- Only the signed in admin (is_hostel_admin(), script 002) can read, add or
-- remove them: nobody else can open a file, even with its name.
-- =====================================================================

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('student-files', 'student-files', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'application/pdf'])
ON CONFLICT (id) DO UPDATE
   SET public = false,
       file_size_limit = 5242880,
       allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'application/pdf'];

DROP POLICY IF EXISTS hostel_admin_student_files ON storage.objects;
CREATE POLICY hostel_admin_student_files ON storage.objects
    FOR ALL TO authenticated
    USING (bucket_id = 'student-files' AND public.is_hostel_admin())
    WITH CHECK (bucket_id = 'student-files' AND public.is_hostel_admin());

COMMIT;
