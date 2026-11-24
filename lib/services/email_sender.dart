import 'dart:convert';

import '../data/email_send_repository.dart';
import 'document_email.dart';
import 'document_share.dart';
import 'validators.dart';

/// Sends the prepared emails from the phone, through Gmail, as the desktop
/// EmailService does. The function also writes the email history and marks
/// an absence as emailed.
class EmailSender {
  /// True when the Gmail app password is saved, so emails can be sent.
  static Future<bool> isConfigured() =>
      EmailSendRepository.instance.isConfigured();

  /// Saves the Gmail app password (encrypted in Supabase Vault).
  static Future<void> savePassword(String password) async {
    final clean = password.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) {
      throw const ValidationException('Please enter the Gmail app password.');
    }
    final error = await EmailSendRepository.instance.call({
      'action': 'save_password',
      'password': clean,
    });
    if (error != null) throw ValidationException(error);
  }

  /// Sends the test email to [to], or to the Gmail address itself when empty.
  static Future<void> sendTest(String to) async {
    final address = Validators.clean(to);
    if (address.isNotEmpty && !Validators.isValidEmailOrEmpty(address)) {
      throw const ValidationException(
        'Please enter a valid email address to send the test to.',
      );
    }
    final error = await EmailSendRepository.instance.call({
      'action': 'test',
      'to': address,
    });
    if (error != null) throw ValidationException(error);
  }

  /// Sends the email with its PDFs; throws a [ValidationException] with the
  /// reason when Gmail does not take it.
  static Future<void> send(EmailDraft draft, List<SharedFile> files) async {
    final error = await EmailSendRepository.instance.call({
      'action': 'send',
      'to': draft.to,
      'toName': draft.parentName,
      'cc': draft.copyTo,
      'subject': draft.subject,
      'body': draft.body,
      'attachments': [
        for (final f in files)
          {'name': f.name, 'base64': base64Encode(f.bytes)},
      ],
      'log': {
        'emailType': draft.type,
        'studentId': draft.studentId,
        if (draft.invoiceIds.isNotEmpty) 'invoiceIds': draft.invoiceIds,
        if (draft.attendanceDate != null)
          'attendanceDate': draft.attendanceDate,
      },
    });
    if (error != null) throw ValidationException(error);
  }
}
