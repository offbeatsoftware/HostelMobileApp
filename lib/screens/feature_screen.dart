import 'package:flutter/material.dart';

import '../models/hostel.dart';
import '../models/menu_item.dart';
import '../theme/app_theme.dart';

/// A screen opened from the home menu. The desktop screens are migrated one by
/// one; until then this shows what the screen will do.
class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key, required this.item, this.hostel});

  final MenuItem item;

  /// The selected hostel (null for screens that do not need one).
  final Hostel? hostel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        bottom: hostel == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    hostel!.hostelName,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(item.icon, size: 64, color: AppColors.terracotta),
          const SizedBox(height: 16),
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'This screen is being moved from the desktop application.',
            key: Key('comingSoon'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
