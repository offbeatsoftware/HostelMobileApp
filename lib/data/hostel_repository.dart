import 'package:flutter/foundation.dart';

import '../models/hostel.dart';
import 'database.dart';

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

  /// All hostels by name, with their numbers of colleges, rooms and students.
  Future<List<Hostel>> getAll() async {
    final rows = await Database.client
        .from('hostel_list')
        .select()
        .order('hostel_name');
    return rows.map(Hostel.fromMap).toList();
  }

  /// Adds the hostel (hostelId null) or saves changes; returns its id.
  Future<int> save({
    int? hostelId,
    required String hostelName,
    required String address,
    required String phone,
    required String email,
  }) => Database.run(
    () async =>
        await Database.client.rpc(
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
  Future<void> delete(int hostelId) => Database.run(() async {
    await Database.client.rpc(
      'delete_hostel',
      params: {'p_hostel_id': hostelId},
    );
  });
}
