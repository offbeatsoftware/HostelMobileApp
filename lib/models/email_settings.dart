/// Kinds of email, stored in email_history.email_type.
class EmailType {
  static const invoice = 'Invoice';
  static const receipt = 'Receipt';
  static const dueReminder = 'DueReminder';
  static const absence = 'Absence';
  static const refund = 'Refund';

  // WhatsApp messages are in the same history (the recipient is then the
  // mobile number).
  static const whatsAppReminder = 'WhatsAppReminder';
  static const whatsAppAbsence = 'WhatsAppAbsence';

  static String displayName(String type) => switch (type) {
    dueReminder => 'Fee reminder',
    whatsAppReminder => 'WhatsApp fee reminder',
    whatsAppAbsence => 'WhatsApp attendance',
    refund => 'Refund receipt',
    _ => type,
  };
}

class EmailStatus {
  static const sent = 'Sent';
  static const failed = 'Failed';
}

/// Subject and message of one kind of email; {Fields} are filled in when the
/// email is sent.
class EmailTemplate {
  const EmailTemplate(this.subject, this.body);

  final String subject;
  final String body;
}

/// The settings of Email Settings that the mobile app edits. The Gmail app
/// password and the WhatsApp API details stay on the desktop.
class EmailSettings {
  const EmailSettings({
    required this.smtpHost,
    required this.smtpPort,
    required this.senderEmail,
    required this.senderName,
    required this.invoice,
    required this.receipt,
    required this.reminder,
    required this.absence,
    required this.whatsAppFeeText,
    required this.whatsAppAttendanceText,
  });

  final String smtpHost;
  final int smtpPort;
  final String senderEmail;
  final String senderName;
  final EmailTemplate invoice;
  final EmailTemplate receipt;
  final EmailTemplate reminder;
  final EmailTemplate absence;
  final String whatsAppFeeText;
  final String whatsAppAttendanceText;
}

/// One row of the email history.
class EmailHistoryEntry {
  const EmailHistoryEntry({
    required this.emailHistoryId,
    required this.recipientEmail,
    required this.emailType,
    required this.sentDate,
    required this.status,
    this.errorMessage = '',
    this.studentName = '',
    this.invoiceNumber = '',
  });

  final int emailHistoryId;
  final String recipientEmail;
  final String emailType;
  final DateTime sentDate;
  final String status;
  final String errorMessage;
  final String studentName;
  final String invoiceNumber;

  String get typeText => EmailType.displayName(emailType);

  bool get failed => status == EmailStatus.failed;

  /// From the email_history row with its student and invoice embedded.
  factory EmailHistoryEntry.fromMap(Map<String, dynamic> map) {
    final student = map['student'] as Map<String, dynamic>?;
    final invoice = map['invoice'] as Map<String, dynamic>?;
    return EmailHistoryEntry(
      emailHistoryId: map['email_history_id'] as int,
      recipientEmail: (map['recipient_email'] as String?) ?? '',
      emailType: map['email_type'] as String,
      sentDate: DateTime.parse(map['sent_date'] as String).toLocal(),
      status: map['status'] as String,
      errorMessage: (map['error_message'] as String?) ?? '',
      studentName: (student?['student_name'] as String?) ?? '',
      invoiceNumber: (invoice?['invoice_number'] as String?) ?? '',
    );
  }
}
