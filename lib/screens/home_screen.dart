import 'package:flutter/material.dart';

import '../data/hostel_repository.dart';
import '../models/hostel.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Home page shown after a successful sign in. For now it lists the hostels
/// from the Supabase database, which shows the connection works; the desktop
/// screens (Students, Rooms, Payments and so on) will be added here.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Hostel>> _hostels;

  @override
  void initState() {
    super.initState();
    _hostels = _load();
  }

  Future<List<Hostel>> _load() => HostelRepository.instance.getAll();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _hostels = next);
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

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
            onPressed: _signOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Hostel>>(
          future: _hostels,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Message(
                key: const Key('homeError'),
                icon: Icons.cloud_off,
                title: 'Could not load data from the database',
                detail: '${snapshot.error}',
              );
            }
            final hostels = snapshot.data!;
            if (hostels.isEmpty) {
              return const _Message(
                key: Key('homeEmpty'),
                icon: Icons.cloud_done,
                title: 'Connected to the database',
                detail: 'No hostels yet.',
              );
            }
            return ListView(
              key: const Key('hostelList'),
              padding: const EdgeInsets.all(16),
              children: [
                Text('Hostels', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final hostel in hostels)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.apartment,
                        color: AppColors.terracotta,
                      ),
                      title: Text(hostel.hostelName),
                      subtitle: hostel.address == null
                          ? null
                          : Text(hostel.address!),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A centred icon and text; scrollable so pull to refresh works.
class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: AppColors.terracotta),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        const Text(
          'Pull down to try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}
