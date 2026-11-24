import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/reminder_repository.dart';
import 'package:hostel_mobile_app/data/settings_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/fee_reminders_screen.dart';
import 'package:hostel_mobile_app/services/fee_reminder_service.dart';
import 'package:hostel_mobile_app/services/launcher.dart';
import 'package:hostel_mobile_app/services/message_text.dart';
import 'package:hostel_mobile_app/services/money.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

final today = DateTime(2026, 11, 24);
const hostel = Hostel(hostelId: 1, hostelName: 'Boys Hostel');

Student st(
  int id,
  String name, {
  String? room,
  String? father,
  String? fatherMobile,
  String? mother,
  String? motherMobile,
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: 'Male',
  admissionDate: DateTime(2025, 7, 1),
  roomNumber: room,
  fatherName: father,
  fatherMobile: fatherMobile,
  motherName: mother,
  motherMobile: motherMobile,
);

Invoice inv(
  int id,
  int student,
  String name,
  int year,
  double fee,
  double received,
) => Invoice(
  invoiceId: id,
  invoiceNumber: 'SBH/$year-${year + 1}/000$id',
  studentId: student,
  studentName: name,
  academicYear: year,
  roomRent: fee,
  transportAmount: 0,
  receivedAmount: received,
);

final students = [
  st(
    1,
    'Ravi',
    room: '10',
    father: 'Rakesh',
    fatherMobile: '98111 22233',
    mother: 'Sunita',
    motherMobile: '98765 43210',
  ),
  st(2, 'Amit', room: '2', mother: 'Asha', motherMobile: '97000 11122'),
  st(3, 'Karan', room: '101'), // no mobile
  st(4, 'Paid Up', room: '5'),
];
final invoices = [
  inv(1, 1, 'Ravi', 2026, 80000, 50000.5), // 29999.50 pending
  inv(2, 1, 'Ravi', 2025, 75000, 65000), // 10000 pending
  inv(3, 2, 'Amit', 2026, 70000, 0), // 70000 pending
  inv(4, 3, 'Karan', 2026, 20000, 10000), // 10000 pending
  inv(5, 4, 'Paid Up', 2026, 60000, 60000), // paid
];

class FixedBilling extends BillingRepository {
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

class FixedStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

class FakeReminders extends ReminderRepository {
  final logged = <Map<String, Object?>>[];
  final last = <int, DateTime>{2: DateTime(2026, 11, 1)};

  @override
  Future<Map<int, DateTime>> getLastReminders(int hostelId) async => last;

  @override
  Future<void> logFeeReminder(
    int studentId,
    String mobile,
    List<int> invoiceIds,
  ) async {
    logged.add({
      'student': studentId,
      'mobile': mobile,
      'invoices': invoiceIds,
    });
    last[studentId] = today;
  }
}

class FakeSettings extends SettingsRepository {
  FakeSettings([this.texts = const {}]);
  final Map<String, String> texts;
  @override
  Future<Map<String, String>> getWhatsAppTexts() async => texts;
  @override
  Future<String?> getAdminPhone() async => '99999 11111';
}

List<FeeDue> dues() => FeeReminderService.dues(
  invoices: invoices,
  students: students,
  lastReminders: {2: DateTime(2026, 11, 1)},
);

void main() {
  group('rules', () {
    test('students with pending fees, highest first, oldest year first', () {
      final d = dues();
      expect([for (final x in d) x.studentName], ['Amit', 'Ravi', 'Karan']);
      final ravi = d[1];
      expect(ravi.pendingAmount, 39999.5);
      expect([for (final i in ravi.invoices) i.academicYear], [2025, 2026]);
      expect(FeeReminderService.years(ravi, 7), '2025-2026, 2026-2027');
      expect(d[0].lastReminder, DateTime(2026, 11, 1));
      expect(FeeReminderService.summary(d), '3 students, pending ₹1,19,999.50');
    });

    test('the father first, else the mother', () {
      final d = dues();
      expect(
        (d[1].parentRelation, d[1].parentName, d[1].parentMobile),
        ('Father', 'Rakesh', '919811122233'),
      );
      expect((d[0].parentRelation, d[0].parentName), ('Mother', 'Asha'));
      expect(d[2].parentMobile, isNull);
    });

    test('search by student, room or father', () {
      List<String> names(String s) => [
        for (final x in FeeReminderService.search(dues(), s)) x.studentName,
      ];
      expect(names('rakesh'), ['Ravi']);
      expect(names('22233'), ['Ravi']);
      expect(names('101'), ['Karan']);
    });

    test('amounts written as the desktop writes them in messages', () {
      expect(MessageText.amount(85000), '85,000');
      expect(MessageText.amount(268500.5), '2,68,500.50');
      expect(MessageText.amount(999), '999');
    });

    test('fields filled, unknown ones left, contact number fallback', () {
      expect(
        MessageText.fill('Hi {ParentName}, {Unknown}!', {'ParentName': 'Raj'}),
        'Hi Raj, {Unknown}!',
      );
      expect(MessageText.contactNumber(' ', '99999 11111'), '99999 11111');
      expect(MessageText.contactNumber(null, null), 'the hostel office');
    });

    test('the desktop default reminder text', () {
      final text = FeeReminderService.message(
        due: dues()[1],
        hostelName: 'Boys Hostel',
        startMonth: 7,
        hostelPhone: '0135 2345678',
      );
      expect(
        text,
        'Dear Rakesh,\nThis is a fee reminder from Boys Hostel for Ravi for '
        'the academic year 2025-2026, 2026-2027.\nTotal fee: ₹1,55,000\n'
        'Paid: ₹1,15,000.50\nPending: ₹39,999.50\n\nTo pay the fee, please '
        'scan our UPI QR code with any UPI app (GPay, PhonePe, Paytm, BHIM). '
        'For bank transfer details, please call 0135 2345678.\n\nAfter '
        'paying, please share the payment receipt or UTR number on 0135 '
        '2345678. Thank you.',
      );
    });

    test('a text saved on the desktop is used', () {
      expect(
        FeeReminderService.message(
          due: dues()[0],
          hostelName: 'Boys Hostel',
          startMonth: 7,
          adminPhone: '99999 11111',
          template: 'Namaste {ParentName}, ₹{Pending} due. Call {HostelPhone}.',
        ),
        'Namaste Asha, ₹70,000 due. Call 99999 11111.',
      );
    });
  });

  group('Fee Reminders screen', () {
    late FakeReminders reminders;
    late List<Uri> opened;

    setUp(() {
      reminders = FakeReminders();
      opened = [];
      BillingRepository.useInstance(FixedBilling());
      StudentRepository.useInstance(FixedStudents());
      ReminderRepository.useInstance(reminders);
      SettingsRepository.useInstance(FakeSettings());
      Launcher.useForTests((uri) async {
        opened.add(uri);
        return true;
      });
    });
    tearDown(() {
      BillingRepository.useInstance(null);
      StudentRepository.useInstance(null);
      ReminderRepository.useInstance(null);
      SettingsRepository.useInstance(null);
      Launcher.useForTests(null);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: FeeRemindersScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists pending fees with the reminder details', (tester) async {
      await open(tester);
      expect(find.text('3 students, pending ₹1,19,999.50'), findsOneWidget);
      expect(find.text('Father: Rakesh, +919811122233'), findsOneWidget);
      expect(find.text('Mother: Asha, +919700011122'), findsOneWidget);
      expect(find.text('Last reminder: 01 Nov 2026'), findsOneWidget);
      expect(
        find.text(
          'Neither the father nor the mother has a valid mobile number.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('remind_3')), findsNothing);
      expect(find.text('Paid Up'), findsNothing);
    });

    testWidgets('WhatsApp: preview, open, record', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('remind_1')));
      await tester.pumpAndSettle();
      expect(find.text('Reminder to father'), findsOneWidget);
      expect(find.textContaining('Pending: ₹39,999.50'), findsOneWidget);
      expect(
        find.textContaining('please call 99999 11111'),
        findsWidgets,
        reason: 'no hostel phone, so the admin\'s',
      );

      await tester.tap(find.byKey(const Key('openWhatsApp')));
      await tester.pumpAndSettle();
      expect(opened.single.path, '/919811122233');
      expect(opened.single.queryParameters['text'], startsWith('Dear Rakesh,'));
      expect(reminders.logged.single, {
        'student': 1,
        'mobile': '919811122233',
        'invoices': [2, 1],
      });
      expect(find.text('Reminder recorded for Ravi.'), findsOneWidget);
      expect(find.text('Last reminder: 24 Nov 2026'), findsOneWidget);
    });

    testWidgets('Cancel sends nothing', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('remind_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(reminders.logged, isEmpty);
    });

    testWidgets('Record Payment opens on the oldest pending invoice', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('pay_1')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Record Payment'), findsOneWidget);
      expect(
        find.text(
          'Fee 2025-2026:  total ₹75,000.00,  paid ₹65,000.00,  '
          'pending ₹10,000.00',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a desktop-saved text is used', (tester) async {
      SettingsRepository.useInstance(
        FakeSettings({
          MessageText.feeKey: 'Namaste {ParentName}: ₹{Pending} due.',
        }),
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('remind_2')));
      await tester.pumpAndSettle();
      expect(find.text('Namaste Asha: ₹70,000 due.'), findsOneWidget);
    });
  });

  test('amounts on the cards add up (paise shown when there are any)', () {
    expect(Money.formatExact(85000), '₹85,000');
    expect(Money.formatExact(39999.5), '₹39,999.50');
  });
}
