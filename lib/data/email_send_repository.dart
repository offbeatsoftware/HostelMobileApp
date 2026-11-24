import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';

/// Sends emails through the Edge Function "send-email"
/// (supabase/functions/send-email/index.ts) and asks whether the Gmail app
/// password is saved (supabase/015_email_sending.sql). The password itself
/// never comes back to the phone.
class EmailSendRepository {
  static EmailSendRepository? _testInstance;

  static EmailSendRepository get instance =>
      _testInstance ?? EmailSendRepository();

  @visibleForTesting
  static void useInstance(EmailSendRepository? repository) =>
      _testInstance = repository;

  /// True when the admin has saved the Gmail app password. False also when
  /// script 015 has not been run.
  Future<bool> isConfigured() async {
    try {
      return await Database.client.rpc('gmail_password_saved') == true;
    } catch (_) {
      return false;
    }
  }

  /// Calls the function; returns null when it worked, otherwise a message
  /// for the admin.
  Future<String?> call(Map<String, Object?> body) async {
    try {
      final response = await Database.client.functions.invoke(
        'send-email',
        body: body,
      );
      final data = response.data;
      if (data is Map && data['ok'] == true) return null;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
      return 'The email could not be sent.';
    } on FunctionException catch (e) {
      if (e.status == 404) {
        return 'The send-email function is not deployed yet. Deploy it in '
            'Supabase (see the README, "Sending emails from the phone").';
      }
      final details = e.details;
      if (details is Map && details['error'] is String) {
        return details['error'] as String;
      }
      return 'The email could not be sent (${e.status}).';
    }
  }
}
