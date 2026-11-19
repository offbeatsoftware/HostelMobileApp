import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Home page shown after a successful sign in. Blank for now; the desktop
/// screens (Students, Rooms, Payments and so on) will be migrated here.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppInfo.businessName),
        actions: [
          IconButton(
            key: const Key('signOut'),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
      body: const SizedBox.expand(key: Key('homeBody')),
    );
  }
}
