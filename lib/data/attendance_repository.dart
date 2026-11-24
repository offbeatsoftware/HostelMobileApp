import 'package:flutter/foundation.dart';

import '../models/attendance.dart';
import 'database.dart';

/// Night attendance in the Supabase database, using the functions in
/// supabase/010_attendance_functions.sql.
class AttendanceRepository {
  static AttendanceRepository? _testInstance;

  /// The repository the screens use.
  static AttendanceRepository get instance =>
      _testInstance ?? AttendanceRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(AttendanceRepository? repository) =>
      _testInstance = repository;

  /// The hostel's saved records for the date (yyyy-mm-dd).
  Future<List<SavedAttendance>> getForDate(int hostelId, String date) async {
    final rows = await Database.client
        .from('attendance_list')
        .select('student_id, is_present, remarks')
        .eq('hostel_id', hostelId)
        .eq('attendance_date', date);
    return rows.map(SavedAttendance.fromMap).toList();
  }

  /// Students whose parent was sent a WhatsApp absence message with this
  /// subject ("attendance 24 Nov 2026").
  Future<Set<int>> getMessaged(int hostelId, String subject) async {
    final rows = await Database.client
        .from('message_history_list')
        .select('student_id')
        .eq('hostel_id', hostelId)
        .eq('email_type', 'WhatsAppAbsence')
        .eq('subject', subject)
        .eq('status', 'Sent');
    return {for (final r in rows) r['student_id'] as int};
  }

  /// Saves the night's attendance; returns how many are absent.
  Future<int> save(int hostelId, String date, List<AttendanceEntry> entries) =>
      Database.run(
        () async =>
            await Database.client.rpc(
                  'save_attendance',
                  params: {
                    'p_hostel_id': hostelId,
                    'p_date': date,
                    'p_entries': [
                      for (final e in entries)
                        {
                          'student_id': e.studentId,
                          'is_present': e.isPresent,
                          'remarks': e.remarks,
                        },
                    ],
                  },
                )
                as int,
      );

  /// Records that a parent was sent a WhatsApp absence message.
  Future<void> logAbsenceMessage(int studentId, String mobile, String date) =>
      Database.run(() async {
        await Database.client.rpc(
          'log_absence_message',
          params: {
            'p_student_id': studentId,
            'p_mobile': mobile,
            'p_date': date,
          },
        );
      });
}
