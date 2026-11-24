import 'package:flutter/foundation.dart';

import '../models/college.dart';
import 'database.dart';

/// Reads and changes colleges in the Supabase database, using the functions
/// in supabase/004_college_functions.sql.
class CollegeRepository {
  static CollegeRepository? _testInstance;

  /// The repository the screens use.
  static CollegeRepository get instance => _testInstance ?? CollegeRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(CollegeRepository? repository) =>
      _testInstance = repository;

  /// The hostel's colleges by name, with their numbers of students.
  Future<List<College>> getForHostel(int hostelId) async {
    final rows = await Database.client
        .from('college_list')
        .select()
        .eq('hostel_id', hostelId)
        .order('college_name');
    return rows.map(College.fromMap).toList();
  }

  /// Adds a college to the hostel (collegeId null) or saves changes to an
  /// existing college, which stays in its hostel. Returns its id.
  Future<int> save({
    int? collegeId,
    required int hostelId,
    required String collegeName,
    required String address,
    required String phone,
  }) => Database.run(
    () async =>
        await Database.client.rpc(
              'save_college',
              params: {
                'p_college_id': collegeId,
                'p_hostel_id': hostelId,
                'p_college_name': collegeName,
                'p_address': address,
                'p_phone': phone,
              },
            )
            as int,
  );

  /// Deletes a college that no student is linked to.
  Future<void> delete(int collegeId) => Database.run(() async {
    await Database.client.rpc(
      'delete_college',
      params: {'p_college_id': collegeId},
    );
  });
}
