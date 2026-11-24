import '../data/email_settings_repository.dart';
import '../models/email_settings.dart';
import 'message_text.dart';
import 'validators.dart';

/// Email Settings rules, the same as the desktop EmailSettingsService and
/// WhatsAppSettingsService (texts only).
class EmailSettingsService {
  static const gmailHost = 'smtp.gmail.com';
  static const gmailPort = 587;
  static const defaultSenderEmail = 'shribalajihostelsuddhowala@gmail.com';

  static const _common = [
    'StudentName',
    'ParentName',
    'HostelName',
    'HostelPhone',
    'AdminEmail',
    'AdminPhone',
  ];

  /// The {Fields} each kind of email can use.
  static const Map<String, List<String>> fields = {
    EmailType.invoice: [
      ..._common,
      'InvoiceNumber',
      'AcademicYear',
      'RoomRent',
      'Transport',
      'Amount',
      'PaidAmount',
      'Pending',
    ],
    EmailType.receipt: [
      ..._common,
      'InvoiceNumber',
      'AcademicYear',
      'ReceiptNumber',
      'PaidAmount',
      'PaymentDate',
      'PaymentMethod',
      'TotalAmount',
      'Pending',
    ],
    EmailType.dueReminder: [
      ..._common,
      'FeeDetails',
      'TotalAmount',
      'PaidAmount',
      'Pending',
    ],
    EmailType.absence: [..._common, 'AttendanceDate', 'RoomNumber', 'Remarks'],
  };

  static const whatsAppFeeFields = [
    'ParentName',
    'StudentName',
    'HostelName',
    'HostelPhone',
    'AcademicYear',
    'TotalAmount',
    'PaidAmount',
    'Pending',
  ];

  static const whatsAppAttendanceFields = [
    'ParentName',
    'StudentName',
    'HostelName',
    'HostelPhone',
    'AttendanceDate',
  ];

  static const defaultInvoice = EmailTemplate(
    'Invoice {InvoiceNumber} for {StudentName}, {HostelName}',
    'Dear {ParentName},\n'
        '\n'
        'Please find attached invoice {InvoiceNumber} for the hostel fee of '
        '{StudentName} for the academic year {AcademicYear}.\n'
        '\n'
        'Room rent: {RoomRent}\n'
        'Transport: {Transport}\n'
        'Total fee: {Amount}\n'
        'Paid so far: {PaidAmount}\n'
        'Pending: {Pending}\n'
        '\n'
        'Thank you,\n'
        '{HostelName}\n'
        '{HostelPhone}',
  );

  static const defaultReceipt = EmailTemplate(
    'Payment receipt {ReceiptNumber} for {StudentName}, {HostelName}',
    'Dear {ParentName},\n'
        '\n'
        'Thank you for your payment of {PaidAmount} on {PaymentDate} towards '
        'the hostel fee of {StudentName} ({AcademicYear}).\n'
        'The receipt is attached.\n'
        '\n'
        'Total fee: {TotalAmount}\n'
        'Balance pending: {Pending}\n'
        '\n'
        'Thank you,\n'
        '{HostelName}\n'
        '{HostelPhone}',
  );

  static const defaultAbsence = EmailTemplate(
    '{StudentName} was not present at {HostelName} on {AttendanceDate}',
    'Dear {ParentName},\n'
        '\n'
        'This is to inform you that {StudentName} (room {RoomNumber}) was not '
        'present in the hostel at the night attendance on {AttendanceDate}.\n'
        '\n'
        'If you were not aware of this, please contact the hostel.\n'
        '\n'
        'Thank you,\n'
        '{HostelName}\n'
        '{HostelPhone}',
  );

  static const defaultReminder = EmailTemplate(
    'Fee reminder for {StudentName}, {HostelName}',
    'Dear {ParentName},\n'
        '\n'
        'This is a reminder about the hostel fee of {StudentName}.\n'
        '\n'
        '{FeeDetails}\n'
        '\n'
        'Total fee: {TotalAmount}\n'
        'Paid so far: {PaidAmount}\n'
        'Pending amount: {Pending}\n'
        '\n'
        'Kindly pay the pending amount at the earliest. The invoice with all '
        'payments is attached.\n'
        'Please ignore this message if you have already paid.\n'
        '\n'
        'Thank you,\n'
        '{HostelName}\n'
        '{HostelPhone}',
  );

  static final _fieldPattern = RegExp(r'\{([A-Za-z]+)\}');

  /// The saved settings; anything never saved has the desktop's default.
  static Future<EmailSettings> get() async =>
      fromValues(await EmailSettingsRepository.instance.getValues());

  static EmailSettings fromValues(Map<String, String> values) {
    String v(String key, String fallback) {
      final x = values[key];
      return x != null && x.isNotEmpty ? x : fallback;
    }

    EmailTemplate t(String name, EmailTemplate d) => EmailTemplate(
      v('Email.$name.Subject', d.subject),
      v('Email.$name.Body', d.body),
    );

    final port = values['Email.SmtpPort'] ?? '';
    return EmailSettings(
      smtpHost: v('Email.SmtpHost', gmailHost),
      smtpPort: RegExp(r'^[0-9]+$').hasMatch(port)
          ? int.parse(port)
          : gmailPort,
      senderEmail: v('Email.SenderEmail', defaultSenderEmail),
      senderName: values['Email.SenderName'] ?? '',
      invoice: t('Invoice', defaultInvoice),
      receipt: t('Receipt', defaultReceipt),
      reminder: t('Reminder', defaultReminder),
      absence: t('Absence', defaultAbsence),
      whatsAppFeeText: v(MessageText.feeKey, MessageText.defaultFeeText),
      whatsAppAttendanceText: v(
        MessageText.attendanceKey,
        MessageText.defaultAttendanceText,
      ),
    );
  }

  /// Saves the Gmail account details and the four email texts. The app
  /// password is not part of it (it is entered on the desktop).
  static Future<void> saveEmail({
    required String senderEmail,
    required String senderName,
    required String smtpHost,
    required String port,
    required EmailTemplate invoice,
    required EmailTemplate receipt,
    required EmailTemplate reminder,
    required EmailTemplate absence,
  }) async {
    senderEmail = Validators.clean(senderEmail);
    senderName = Validators.clean(senderName);
    smtpHost = Validators.clean(smtpHost);
    port = Validators.clean(port);
    if (senderEmail.isEmpty) {
      throw const ValidationException(
        'Please enter the Gmail address that sends the emails.',
      );
    }
    if (!Validators.isValidEmailOrEmpty(senderEmail)) {
      throw const ValidationException(
        'Please enter a valid sender email address.',
      );
    }
    if (smtpHost.isEmpty) {
      throw const ValidationException('Please enter the SMTP server.');
    }
    final portNumber = RegExp(r'^[0-9]{1,5}$').hasMatch(port)
        ? int.parse(port)
        : 0;
    if (portNumber < 1 || portNumber > 65535) {
      throw const ValidationException(
        'Please enter a valid SMTP port (587 for Gmail).',
      );
    }
    Validators.checkLength(senderEmail, 150, 'Gmail address');
    Validators.checkLength(smtpHost, 100, 'SMTP server');
    Validators.checkLength(senderName, 100, 'Sender name');

    final templates = [
      (EmailType.invoice, 'invoice', 'Invoice', invoice),
      (EmailType.receipt, 'receipt', 'Receipt', receipt),
      (EmailType.dueReminder, 'fee reminder', 'Reminder', reminder),
      (EmailType.absence, 'attendance', 'Absence', absence),
    ];
    for (final t in templates) {
      validateTemplate(t.$1, t.$2, t.$4);
    }
    await EmailSettingsRepository.instance.saveValues({
      'Email.SmtpHost': smtpHost,
      'Email.SmtpPort': '$portNumber',
      'Email.SenderEmail': senderEmail,
      'Email.SenderName': senderName,
      for (final t in templates) ...{
        'Email.${t.$3}.Subject': t.$4.subject.trim(),
        'Email.${t.$3}.Body': t.$4.body.trim(),
      },
    });
  }

  /// The subject and message are required and may only use the fields the
  /// kind of email has.
  static void validateTemplate(String type, String name, EmailTemplate t) {
    if (t.subject.trim().isEmpty || t.body.trim().isEmpty) {
      throw ValidationException(
        'Please enter the subject and message of the $name email.',
      );
    }
    Validators.checkLength(t.subject.trim(), 255, 'The $name email subject');
    final unknown = _unknown('${t.subject}${t.body}', fields[type]!);
    if (unknown.isNotEmpty) {
      throw ValidationException(
        'The $name email uses ${unknown.join(', ')}, which is not available. '
        'Available: ${_braced(fields[type]!)}.',
      );
    }
  }

  /// Saves the two WhatsApp messages (the desktop's "WhatsApp on this PC"
  /// texts).
  static Future<void> saveWhatsApp({
    required String feeText,
    required String attendanceText,
  }) async {
    _validateWhatsApp(feeText, whatsAppFeeFields, 'fee reminder');
    _validateWhatsApp(attendanceText, whatsAppAttendanceFields, 'attendance');
    await EmailSettingsRepository.instance.saveValues({
      MessageText.feeKey: feeText,
      MessageText.attendanceKey: attendanceText,
    });
  }

  static void _validateWhatsApp(
    String text,
    List<String> allowed,
    String name,
  ) {
    if (text.trim().isEmpty) {
      throw ValidationException('Please enter the $name WhatsApp message.');
    }
    Validators.checkLength(text, 1500, 'The $name WhatsApp message');
    final unknown = _unknown(text, allowed);
    if (unknown.isNotEmpty) {
      throw ValidationException(
        'The $name WhatsApp message uses ${unknown.join(', ')}, which is not '
        'available. Available: ${_braced(allowed)}.',
      );
    }
  }

  static List<String> _unknown(String text, List<String> allowed) => {
    for (final m in _fieldPattern.allMatches(text))
      if (!allowed.contains(m.group(1))) '{${m.group(1)}}',
  }.toList();

  static String _braced(List<String> names) =>
      names.map((f) => '{$f}').join(', ');
}
