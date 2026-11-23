import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/hostel.dart';
import '../services/validators.dart';

/// Reads and changes hostels in the Supabase database.
/// Adding, editing and deleting use the database functions in
/// supabase/003_hostel_functions.sql, so each runs as one step.
class HostelRepository {
  static HostelRepository? _testInstance;

  /// The repository the screens use.
  static HostelRepository get instance => _testInstance ?? HostelRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(HostelRepository? repository) =>
      _testInstance = repository;

  SupabaseClient get _db {
    if (!SupabaseConfig.isConfigured) {
      throw StateError(
        'The Supabase URL and key are not set in '
        'lib/config/supabase_config.dart.',
      );
    }
    return Supabase.instance.client;
  }

  /// All hostels by name, with their numbers of colleges, rooms and students.
  Future<List<Hostel>> getAll() async {
    final rows = await _db.from('hostel_list').select().order('hostel_name');
    return rows.map(Hostel.fromMap).toList();
  }

  /// Adds the hostel (hostelId null) or saves changes; returns its id.
  Future<int> save({
    int? hostelId,
    required String hostelName,
    required String address,
    required String phone,
    required String email,
  }) => _run(
    () async =>
        await _db.rpc(
              'save_hostel',
              params: {
                'p_hostel_id': hostelId,
                'p_hostel_name': hostelName,
                'p_address': address,
                'p_phone': phone,
                'p_email': email,
              },
            )
            as int,
  );

  /// Deletes a hostel that has no students, colleges or rooms.
  Future<void> delete(int hostelId) => _run(() async {
    await _db.rpc('delete_hostel', params: {'p_hostel_id': hostelId});
  });

  /// The database functions explain refusals (error P0001); those messages
  /// are shown to the admin as they are.
  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ValidationException(e.message);
      rethrow;
    }
  }
}
