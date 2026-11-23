import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Flutter must be ready before Firebase and Supabase are started.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
      // The admin signs in with Firebase; every database request carries the
      // Firebase ID token, which Supabase checks (Third-party Auth).
      accessToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
  }
  runApp(const HostelMobileApp());
}

class HostelMobileApp extends StatelessWidget {
  const HostelMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.productName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Firebase remembers the sign in, so an admin who is still signed in
      // goes straight to the home page.
      home: AuthService.isSignedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
