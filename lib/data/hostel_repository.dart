import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/hostel.dart';

/// Reads hostels from the Supabase database.
class HostelRepository {
  static HostelRepository? _testInstance;

  /// The repository the screens use.
  static HostelRepository get instance => _testInstance ?? HostelRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(HostelRepository? repository) =>
      _testInstance = repository;

  /// All hostels, by name.
  Future<List<Hostel>> getAll() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError(
        'The Supabase URL and key are not set in '
        'lib/config/supabase_config.dart.',
      );
    }
    final rows = await Supabase.instance.client
        .from('hostel')
        .select('hostel_id, hostel_name, address, phone')
        .order('hostel_name');
    return rows.map(Hostel.fromMap).toList();
  }
}
