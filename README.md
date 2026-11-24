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
8. Put the project URL and publishable key in `lib/config/supabase_config.dart`.

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
