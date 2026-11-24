import 'package:flutter/foundation.dart';

import '../models/allocation.dart';
import '../models/invoice.dart';
import 'database.dart';

/// Room allocation (check-in, transfer, check-out) in the Supabase database,
/// using the functions in supabase/007_allocation_functions.sql.
class AllocationRepository {
  static AllocationRepository? _testInstance;

  /// The repository the screens use.
  static AllocationRepository get instance =>
      _testInstance ?? AllocationRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(AllocationRepository? repository) =>
      _testInstance = repository;

  /// The hostel's allocations; current ones only unless [includeHistory].
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async {
    var query = Database.client
        .from('allocation_list')
        .select()
        .eq('hostel_id', hostelId);
    if (!includeHistory) query = query.eq('status', AllocationStatus.current);
    final rows = await query;
    return rows.map(RoomAllocation.fromMap).toList();
  }

  /// The student's invoices (to see this year's fee and what is pending).
  Future<List<Invoice>> getInvoicesForStudent(int studentId) async {
    final rows = await Database.client
        .from('invoice_list')
        .select()
        .eq('student_id', studentId)
        .order('academic_year', ascending: false);
    return rows.map(Invoice.fromMap).toList();
  }

  /// The month the academic year starts (July unless changed on the desktop).
  Future<int> getAcademicYearStartMonth() async =>
      await Database.client.rpc('academic_year_start_month') as int;

  /// Puts a student in a room (and bed); with [roomRent] the yearly fee is
  /// created too.
  Future<void> checkIn({
    required int studentId,
    required int roomId,
    required String date,
    required String remarks,
    int? bed,
    double? roomRent,
    double? transport,
  }) => Database.run(() async {
    await Database.client.rpc(
      'check_in',
      params: {
        'p_student_id': studentId,
        'p_room_id': roomId,
        'p_date': date,
        'p_remarks': remarks,
        'p_bed': bed,
        'p_room_rent': roomRent,
        'p_transport': transport,
      },
    );
  });

  /// Moves a student to another room on the date.
  Future<void> transfer({
    required int studentId,
    required int newRoomId,
    required String date,
    required String remarks,
    int? bed,
  }) => Database.run(() async {
    await Database.client.rpc(
      'transfer_room',
      params: {
        'p_student_id': studentId,
        'p_new_room_id': newRoomId,
        'p_date': date,
        'p_remarks': remarks,
        'p_bed': bed,
      },
    );
  });

  /// Checks the student out (status Left); [waive] waives the pending fee.
  Future<void> checkOut({
    required int studentId,
    required String date,
    required String remarks,
    required bool waive,
  }) => Database.run(() async {
    await Database.client.rpc(
      'check_out',
      params: {
        'p_student_id': studentId,
        'p_date': date,
        'p_remarks': remarks,
        'p_waive': waive,
      },
    );
  });
}
