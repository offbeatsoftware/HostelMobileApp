# Hostel Mobile App

Flutter mobile version of the Shri Balaji Hostel management desktop application
(migrated from the WinForms project `hostelmanagement`).

## Migrated so far
1. **Login screen** (from `Forms/LoginForm.cs`): hostel photo background, dark sign in
   panel with gold title, user name prefilled as `admin`, terracotta Sign in button,
   "Incorrect user name or password." message on failure.
   Credentials are hard coded for now: **admin / admin** (user name not case sensitive).
2. **Home screen**: blank page shown after a successful sign in, with a Sign out button.

## Database (Supabase)
The data lives in a Supabase (PostgreSQL) database. The admin signs in with
Firebase, and every database request carries the Firebase ID token.

One time setup:
1. Supabase SQL Editor: run `supabase/001_hostel_schema.sql` (all desktop tables).
2. Supabase Dashboard > Authentication > Third-party Auth > Add provider >
   **Firebase**, Firebase project ID `hostelmanagement-86380`.
3. Copy the admin's User UID from Firebase Console > Authentication > Users into
   `supabase/002_mobile_access.sql`, then run it in the SQL Editor (access rules).
4. Run `supabase/003_hostel_functions.sql` (Hostels screen: add, edit, delete).
5. Run `supabase/004_college_functions.sql` (Colleges screen).
6. Run `supabase/005_room_functions.sql` (Rooms screen).
7. Run `supabase/006_student_functions.sql` (Students screen).
8. Run `supabase/007_allocation_functions.sql` (Room Allocation screen).
9. Run `supabase/008_billing_functions.sql` (Invoices and Payments screens).
10. Run `supabase/009_dashboard.sql` (Dashboard).
11. Run `supabase/010_attendance_functions.sql` (Attendance screen).
12. Run `supabase/011_fee_reminder_functions.sql` (Fee Reminders screen).
13. Run `supabase/012_refund_functions.sql` (Refunds).
14. Run `supabase/013_delete_student_permanently.sql` (Students > Delete Permanently).
15. Run `supabase/014_payment_qr_storage.sql` (payment QR image in WhatsApp reminders).
16. Run `supabase/015_email_sending.sql` (sending emails from the phone).
17. Deploy the `send-email` function (see "Sending emails from the phone" below).
18. Run `supabase/016_agreement.sql` (student agreement and its signatures).
19. Run `supabase/017_student_files.sql` (student photos and Aadhaar cards).
20. Put the project URL and publishable key in `lib/config/supabase_config.dart`.

> **Firebase and the database role:** Firebase sign-in tokens have no `role`
> claim, so Supabase runs the app's requests as role `anon`. Every access rule
> therefore says `TO anon, authenticated`; the check inside
> `is_hostel_admin()` decides who gets in. Scripts 014 to 017 had
> `TO authenticated` only, which made Storage refuse uploads (403) until they
> were corrected: run 014, 015, 016 and 017 again if you ran the earlier versions.

## Sending emails from the phone

The phone sends invoices, receipts, fee reminders and attendance emails
through the hostel's Gmail account, as the desktop program does. Gmail is
contacted by a small Supabase Edge Function, `send-email`, so the Gmail app
password never has to be on the phone. Without it the Email buttons still
open the phone's mail app with the PDF attached.

1. Run `supabase/015_email_sending.sql` (step 16 above).
2. Supabase Dashboard > **Edge Functions** > **Deploy a new function** > **Via Editor**.
   Name it exactly `send-email`, paste the whole of
   `supabase/functions/send-email/index.ts` and deploy.
3. Open the function's settings and turn **off** "Verify JWT with legacy secret"
   (the function checks the signed in admin itself, because the app signs in
   with Firebase). Nothing else needs setting: `SUPABASE_URL`,
   `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided to the
   function by Supabase.
4. In the app: Email Settings > Gmail account: check the Gmail address, type the
   Gmail app password (16 letters, see the help text there), tap **Save**, then
   **Send Test Email**.

The password is kept encrypted in Supabase Vault and is never sent back to the
phone. It is separate from the desktop program's own copy. Supabase blocks
outgoing SMTP ports 25 and 587, so the function connects to Gmail on port 465
with the same account and password.

## Run
```
flutter pub get
flutter run          # Android emulator / device, iOS simulator, or -d chrome
flutter test
```

## Structure
- `lib/main.dart` app entry
- `lib/screens/login_screen.dart`, `lib/screens/home_screen.dart`
- `lib/services/auth_service.dart` Firebase sign in
- `lib/config/supabase_config.dart` Supabase URL and publishable key
- `lib/data/` database access (`hostel_repository.dart`), `lib/models/` table rows
- `supabase/` database scripts, run in order
- `lib/theme/app_theme.dart` colours carried over from the desktop UiTheme
- `assets/images/login_background.jpg` hostel photo from the desktop app
