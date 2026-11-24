import 'package:flutter/foundation.dart';

import 'database.dart';

/// Fee reminders in the Supabase database (supabase/011_fee_reminder_functions.sql).
class ReminderRepository {
  static ReminderRepository? _testInstance;

  static ReminderRepository get instance =>
      _testInstance ?? ReminderRepository();

  @visibleForTesting
  static void useInstance(ReminderRepository? repository) =>
      _testInstance = repository;

  /// When each student's parent was last sent a fee reminder (by email from
  /// the desktop or on WhatsApp from either app).
  Future<Map<int, DateTime>> getLastReminders(int hostelId) async {
    final rows = await Database.client
        .from('message_history_list')
        .select('student_id, sent_date')
        .eq('hostel_id', hostelId)
        .inFilter('email_type', ['DueReminder', 'WhatsAppReminder'])
        .eq('status', 'Sent');
    final last = <int, DateTime>{};
    for (final r in rows) {
      final id = r['student_id'] as int;
      final sent = DateTime.parse(r['sent_date'] as String).toLocal();
      if (last[id] == null || sent.isAfter(last[id]!)) last[id] = sent;
    }
    return last;
  }

  /// Records a WhatsApp fee reminder about the invoices.
  Future<void> logFeeReminder(
    int studentId,
    String mobile,
    List<int> invoiceIds,
  ) => Database.run(() async {
    await Database.client.rpc(
      'log_fee_reminder',
      params: {
        'p_student_id': studentId,
        'p_mobile': mobile,
        'p_invoice_ids': invoiceIds,
      },
    );
  });
}
