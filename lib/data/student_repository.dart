import 'package:flutter/foundation.dart';

import '../models/student.dart';
import 'database.dart';

/// Reads and changes students in the Supabase database, using the functions
/// in supabase/006_student_functions.sql.
class StudentRepository {
  static StudentRepository? _testInstance;

  /// The repository the screens use.
  static StudentRepository get instance => _testInstance ?? StudentRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(StudentRepository? repository) =>
      _testInstance = repository;

  /// The hostel's students (active and left) with college and current room.
  Future<List<Student>> getForHostel(int hostelId) async {
    final rows = await Database.client
        .from('student_list')
        .select()
        .eq('hostel_id', hostelId);
    return rows.map(Student.fromMap).toList();
  }

  /// Adds a student to the hostel (studentId null) or saves changes; the
  /// fields are named as the database columns. Returns the student's id.
  Future<int> save({
    int? studentId,
    required int hostelId,
    required Map<String, Object?> data,
  }) => Database.run(
    () async =>
        await Database.client.rpc(
              'save_student',
              params: {
                'p_student_id': studentId,
                'p_hostel_id': hostelId,
                'p_data': data,
              },
            )
            as int,
  );

  /// Deletes a student who has no room, invoice or payment records.
  Future<void> delete(int studentId) => Database.run(() async {
    await Database.client.rpc(
      'delete_student',
      params: {'p_student_id': studentId},
    );
  });

  /// Makes an inactive (Left) student active again.
  Future<void> makeActive(int studentId) => Database.run(() async {
    await Database.client.rpc(
      'make_student_active',
      params: {'p_student_id': studentId},
    );
  });

  /// Deletes an inactive (Left) student with every record of them
  /// (supabase/013_delete_student_permanently.sql).
  Future<void> deletePermanently(int studentId, String reason) =>
      Database.run(() async {
        await Database.client.rpc(
          'delete_student_permanently',
          params: {'p_student_id': studentId, 'p_reason': reason},
        );
      });
}
