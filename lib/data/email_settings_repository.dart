import 'package:flutter/foundation.dart';

import '../models/email_settings.dart';
import 'database.dart';

/// Email Settings in the app_setting table, and the email history.
///
/// The Gmail app password (Email.AppPassword) and the WhatsApp API settings
/// are never read or written here: the desktop keeps the password encrypted
/// for its Windows user.
class EmailSettingsRepository {
  static EmailSettingsRepository? _testInstance;

  static EmailSettingsRepository get instance =>
      _testInstance ?? EmailSettingsRepository();

  @visibleForTesting
  static void useInstance(EmailSettingsRepository? repository) =>
      _testInstance = repository;

  /// The setting keys the mobile app edits.
  static const keys = [
    'Email.SmtpHost',
    'Email.SmtpPort',
    'Email.SenderEmail',
    'Email.SenderName',
    'Email.Invoice.Subject',
    'Email.Invoice.Body',
    'Email.Receipt.Subject',
    'Email.Receipt.Body',
    'Email.Reminder.Subject',
    'Email.Reminder.Body',
    'Email.Absence.Subject',
    'Email.Absence.Body',
    'WhatsApp.FeeText',
    'WhatsApp.AttendanceText',
  ];

  /// The saved values by key; keys never saved are missing.
  Future<Map<String, String>> getValues() async {
    final rows = await Database.client
        .from('app_setting')
        .select('setting_key, setting_value')
        .inFilter('setting_key', keys);
    return {
      for (final r in rows)
        r['setting_key'] as String: (r['setting_value'] as String?) ?? '',
    };
  }

  /// Saves the values together (one request, so all or none).
  Future<void> saveValues(Map<String, String> values) async {
    await Database.client.from('app_setting').upsert([
      for (final e in values.entries)
        {'setting_key': e.key, 'setting_value': e.value},
    ], onConflict: 'setting_key');
  }

  /// The latest emails and WhatsApp messages of all hostels.
  Future<List<EmailHistoryEntry>> getHistory({int maxRows = 500}) async {
    final rows = await Database.client
        .from('email_history')
        .select('*, student(student_name), invoice(invoice_number)')
        .order('sent_date', ascending: false)
        .order('email_history_id', ascending: false)
        .limit(maxRows);
    return rows.map(EmailHistoryEntry.fromMap).toList();
  }
}
