import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/email_settings_repository.dart';
import 'package:hostel_mobile_app/models/email_settings.dart';
import 'package:hostel_mobile_app/screens/email_settings_screen.dart';
import 'package:hostel_mobile_app/services/email_settings_service.dart';
import 'package:hostel_mobile_app/services/message_text.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

class MemorySettings extends EmailSettingsRepository {
  MemorySettings([Map<String, String>? values, this.history = const []])
    : values = {...?values};

  final Map<String, String> values;
  final List<EmailHistoryEntry> history;
  var saves = 0;
  bool failHistory = false;

  @override
  Future<Map<String, String>> getValues() async => {...values};

  @override
  Future<void> saveValues(Map<String, String> v) async {
    saves++;
    values.addAll(v);
  }

  @override
  Future<List<EmailHistoryEntry>> getHistory({int maxRows = 500}) async {
    if (failHistory) throw Exception('offline');
    return history;
  }
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

Future<void> saveEmail(
  MemorySettings db, {
  String senderEmail = 'hostel@gmail.com',
  String port = '587',
  EmailTemplate? invoice,
  EmailTemplate? reminder,
}) => EmailSettingsService.saveEmail(
  senderEmail: senderEmail,
  senderName: '  Shri Balaji ',
  smtpHost: 'smtp.gmail.com',
  port: port,
  invoice: invoice ?? EmailSettingsService.defaultInvoice,
  receipt: EmailSettingsService.defaultReceipt,
  reminder: reminder ?? EmailSettingsService.defaultReminder,
  absence: EmailSettingsService.defaultAbsence,
);

void main() {
  late MemorySettings db;

  setUp(() {
    db = MemorySettings();
    EmailSettingsRepository.useInstance(db);
  });
  tearDown(() => EmailSettingsRepository.useInstance(null));

  group('EmailSettingsService', () {
    test('nothing saved: the desktop defaults', () async {
      final s = await EmailSettingsService.get();
      expect(s.smtpHost, 'smtp.gmail.com');
      expect(s.smtpPort, 587);
      expect(s.senderEmail, 'shribalajihostelsuddhowala@gmail.com');
      expect(s.senderName, '');
      expect(
        s.invoice.subject,
        'Invoice {InvoiceNumber} for {StudentName}, {HostelName}',
      );
      expect(s.reminder.body, contains('{FeeDetails}'));
      expect(s.whatsAppFeeText, MessageText.defaultFeeText);
    });

    test('saved values win; empty ones fall back; bad port falls back', () {
      final s = EmailSettingsService.fromValues({
        'Email.SmtpHost': 'smtp.example.com',
        'Email.SmtpPort': 'x25',
        'Email.SenderEmail': '',
        'Email.Absence.Subject': 'Absent: {StudentName}',
        'WhatsApp.AttendanceText': 'Hi {ParentName}',
      });
      expect(s.smtpHost, 'smtp.example.com');
      expect(s.smtpPort, 587);
      expect(s.senderEmail, 'shribalajihostelsuddhowala@gmail.com');
      expect(s.absence.subject, 'Absent: {StudentName}');
      expect(s.absence.body, EmailSettingsService.defaultAbsence.body);
      expect(s.whatsAppAttendanceText, 'Hi {ParentName}');
    });

    test('saves the account and texts, never the app password', () async {
      await saveEmail(db);
      expect(db.values['Email.SenderName'], 'Shri Balaji');
      expect(db.values['Email.SmtpPort'], '587');
      expect(db.values.containsKey('Email.AppPassword'), isFalse);
      expect(db.values.keys.where((k) => k.startsWith('WhatsApp')), isEmpty);
      expect(db.values['Email.Invoice.Body'], isNot(endsWith('\n')));
      expect(
        EmailSettingsRepository.keys,
        isNot(contains('Email.AppPassword')),
      );
    });

    test('account: the desktop messages', () async {
      await expectMessage(
        saveEmail(db, senderEmail: ' '),
        'Please enter the Gmail address that sends the emails.',
      );
      await expectMessage(
        saveEmail(db, senderEmail: 'nope'),
        'Please enter a valid sender email address.',
      );
      await expectMessage(
        saveEmail(db, port: '70000'),
        'Please enter a valid SMTP port (587 for Gmail).',
      );
      await expectMessage(
        saveEmail(db, port: 'abc'),
        'Please enter a valid SMTP port (587 for Gmail).',
      );
      expect(db.saves, 0);
    });

    test('texts: required, and only the fields of that email', () async {
      await expectMessage(
        saveEmail(db, invoice: const EmailTemplate('Hi', '  ')),
        'Please enter the subject and message of the invoice email.',
      );
      await expectMessage(
        saveEmail(
          db,
          reminder: const EmailTemplate('Due {Pending}', 'Room {RoomNumber}'),
        ),
        'The fee reminder email uses {RoomNumber}, which is not available. '
        'Available: {StudentName}, {ParentName}, {HostelName}, {HostelPhone}, '
        '{AdminEmail}, {AdminPhone}, {FeeDetails}, {TotalAmount}, '
        '{PaidAmount}, {Pending}.',
      );
      expect(db.saves, 0);
    });

    test('WhatsApp texts: required, short enough, known fields', () async {
      await expectMessage(
        EmailSettingsService.saveWhatsApp(feeText: ' ', attendanceText: 'x'),
        'Please enter the fee reminder WhatsApp message.',
      );
      await expectMessage(
        EmailSettingsService.saveWhatsApp(
          feeText: 'Hi {ParentName}',
          attendanceText: 'Room {RoomNumber}',
        ),
        'The attendance WhatsApp message uses {RoomNumber}, which is not '
        'available. Available: {ParentName}, {StudentName}, {HostelName}, '
        '{HostelPhone}, {AttendanceDate}.',
      );
      await expectMessage(
        EmailSettingsService.saveWhatsApp(
          feeText: 'a' * 1501,
          attendanceText: 'x',
        ),
        'The fee reminder WhatsApp message can be at most 1500 characters.',
      );
      await EmailSettingsService.saveWhatsApp(
        feeText: MessageText.defaultFeeText,
        attendanceText: MessageText.defaultAttendanceText,
      );
      expect(db.values['WhatsApp.FeeText'], MessageText.defaultFeeText);
    });

    test('every default only uses its own fields', () {
      for (final e in {
        EmailType.invoice: EmailSettingsService.defaultInvoice,
        EmailType.receipt: EmailSettingsService.defaultReceipt,
        EmailType.dueReminder: EmailSettingsService.defaultReminder,
        EmailType.absence: EmailSettingsService.defaultAbsence,
      }.entries) {
        EmailSettingsService.validateTemplate(e.key, e.key, e.value);
      }
    });
  });

  group('history', () {
    test('reads the embedded student and invoice', () {
      final e = EmailHistoryEntry.fromMap({
        'email_history_id': 5,
        'recipient_email': 'p@x.com',
        'email_type': 'DueReminder',
        'sent_date': '2026-11-20T10:30:00+00:00',
        'status': 'Failed',
        'error_message': 'Mailbox full',
        'student': {'student_name': 'Ravi'},
        'invoice': {'invoice_number': 'SBH/2026-2027/0001'},
      });
      expect(e.typeText, 'Fee reminder');
      expect(e.failed, isTrue);
      expect(e.studentName, 'Ravi');
      expect(e.invoiceNumber, 'SBH/2026-2027/0001');
      expect(EmailType.displayName('WhatsAppAbsence'), 'WhatsApp attendance');
      expect(EmailType.displayName('Invoice'), 'Invoice');
    });
  });

  group('screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const EmailSettingsScreen()),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tab(WidgetTester tester, String name) async {
      final finder = find.widgetWithText(Tab, name);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    testWidgets('shows the saved account and the defaults', (tester) async {
      db.values['Email.SenderEmail'] = 'mine@gmail.com';
      await open(tester);
      expect(text(tester, 'senderEmail'), 'mine@gmail.com');
      expect(text(tester, 'smtpHost'), 'smtp.gmail.com');
      expect(text(tester, 'smtpPort'), '587');
      expect(find.byKey(const Key('saveEmail')), findsOneWidget);
      await tab(tester, 'Invoice email');
      expect(
        text(tester, 'subject_Invoice'),
        'Invoice {InvoiceNumber} for {StudentName}, {HostelName}',
      );
      expect(find.textContaining('{RoomRent}  {Transport}'), findsOneWidget);
    });

    testWidgets('saves, and says what is wrong', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('senderEmail')), 'bad');
      await tester.tap(find.byKey(const Key('saveEmail')));
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid sender email address.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('senderEmail')),
        'boss@gmail.com',
      );
      await tester.tap(find.byKey(const Key('saveEmail')));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(db.values['Email.SenderEmail'], 'boss@gmail.com');
    });

    testWidgets('Restore Default puts the desktop text back', (tester) async {
      db.values['Email.Receipt.Subject'] = 'Mine';
      await open(tester);
      await tab(tester, 'Receipt email');
      expect(text(tester, 'subject_Receipt'), 'Mine');
      await tester.tap(find.byKey(const Key('restore_Receipt')));
      await tester.pump();
      expect(
        text(tester, 'subject_Receipt'),
        'Payment receipt {ReceiptNumber} for {StudentName}, {HostelName}',
      );
    });

    testWidgets('WhatsApp texts have their own Save', (tester) async {
      await open(tester);
      await tab(tester, 'WhatsApp');
      expect(find.byKey(const Key('saveEmail')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('whatsAppAttendanceText')),
        'Absent {StudentName}',
      );
      await tester.tap(find.byKey(const Key('saveWhatsApp')));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(db.values['WhatsApp.AttendanceText'], 'Absent {StudentName}');
      expect(db.values.containsKey('Email.SenderEmail'), isFalse);
      await tester.tap(find.byKey(const Key('restoreWhatsApp')));
      await tester.pump();
      expect(
        text(tester, 'whatsAppAttendanceText'),
        MessageText.defaultAttendanceText,
      );
    });

    testWidgets('history lists messages, failures in red', (tester) async {
      EmailSettingsRepository.useInstance(
        MemorySettings({}, [
          EmailHistoryEntry(
            emailHistoryId: 2,
            recipientEmail: 'p@x.com',
            emailType: EmailType.dueReminder,
            sentDate: DateTime(2026, 11, 20, 9, 5),
            status: EmailStatus.failed,
            errorMessage: 'Mailbox full',
            studentName: 'Ravi',
            invoiceNumber: 'SBH/2026-2027/0001',
          ),
        ]),
      );
      await open(tester);
      expect(find.byKey(const Key('saveEmail')), findsOneWidget);
      await tab(tester, 'Email history');
      expect(find.byKey(const Key('saveEmail')), findsNothing);
      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Fee reminder, SBH/2026-2027/0001'), findsOneWidget);
      expect(find.text('20 Nov 2026 09:05, to p@x.com'), findsOneWidget);
      expect(find.text('Mailbox full'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('history empty and error states', (tester) async {
      await open(tester);
      await tab(tester, 'Email history');
      expect(find.byKey(const Key('historyEmpty')), findsOneWidget);

      EmailSettingsRepository.useInstance(MemorySettings()..failHistory = true);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await tab(tester, 'Email history');
      expect(find.byKey(const Key('historyError')), findsOneWidget);
    });
  });
}
