# Hostel Mobile App

Flutter mobile version of the Shri Balaji Hostel management desktop application
(migrated from the WinForms project `hostelmanagement`).

## Migrated so far
1. **Login screen** (from `Forms/LoginForm.cs`): hostel photo background, dark sign in
   panel with gold title, user name prefilled as `admin`, terracotta Sign in button,
   "Incorrect user name or password." message on failure.
   Credentials are hard coded for now: **admin / admin** (user name not case sensitive).
2. **Home screen**: blank page shown after a successful sign in, with a Sign out button.

## Run
```
flutter pub get
flutter run          # Android emulator / device, iOS simulator, or -d chrome
flutter test
```

## Structure
- `lib/main.dart` app entry
- `lib/screens/login_screen.dart`, `lib/screens/home_screen.dart`
- `lib/services/auth_service.dart` hard coded admin / admin check
- `lib/theme/app_theme.dart` colours carried over from the desktop UiTheme
- `assets/images/login_background.jpg` hostel photo from the desktop app
