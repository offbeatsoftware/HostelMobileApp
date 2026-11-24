import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/admin_repository.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/email_settings_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/admin_user.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/payment.dart';
import 'package:hostel_mobile_app/models/print_data.dart';
import 'package:hostel_mobile_app/models/refund.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/invoices_screen.dart';
import 'package:hostel_mobile_app/screens/payments_screen.dart';
import 'package:hostel_mobile_app/screens/refunds_screen.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/document_data.dart';
import 'package:hostel_mobile_app/services/document_email.dart';
import 'package:hostel_mobile_app/services/document_pdf.dart';
import 'package:hostel_mobile_app/services/document_share.dart';
import 'package:hostel_mobile_app/services/money.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

const hostel = Hostel(
  hostelId: 1,
  hostelName: 'Boys Hostel',
  address: 'Suddhowala',
  phone: '0135 2222',
);
final today = DateTime(2026, 11, 24);

Student student(
  int id,
  String name, {
  String? fatherEmail,
  String? motherEmail,
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: 'Male',
  admissionDate: DateTime(2025, 7, 1),
  collegeName: 'DAV College',
  fatherName: 'Rakesh',
  fatherEmail: fatherEmail,
  motherName: 'Sunita',
  motherEmail: motherEmail,
);

final students = [
  student(1, 'Ravi', fatherEmail: 'rakesh@x.com'),
  student(2, 'Amit', motherEmail: 'asha@x.com'),
  student(3, 'Karan'), // no email
];

Invoice inv(int id, int studentId, String name, int year, double paid) =>
    Invoice(
      invoiceId: id,
      invoiceNumber: 'SBH/$year-${year + 1}/000$id',
      studentId: studentId,
      studentName: name,
      academicYear: year,
      roomRent: 80000,
      transportAmount: 12000,
      receivedAmount: paid,
      invoiceDate: DateTime(year, 7, 5),
    );

final invoices = [
  inv(1, 1, 'Ravi', 2026, 70000),
  inv(2, 2, 'Amit', 2026, 92000),
  inv(3, 3, 'Karan', 2026, 10000),
  inv(4, 1, 'Ravi', 2025, 92000),
];

Payment pay(
  int id,
  int invoiceId,
  int studentId,
  String name,
  double amount,
  DateTime date, {
  String method = 'Cash',
  String? reference,
}) => Payment(
  paymentId: id,
  receiptNumber: 'SBH/R/2026-2027/000$id',
  studentId: studentId,
  invoiceId: invoiceId,
  paymentDate: date,
  amount: amount,
  paymentMethod: method,
  reference: reference,
  studentName: name,
  invoiceNumber: invoices
      .firstWhere((i) => i.invoiceId == invoiceId)
      .invoiceNumber,
);

final payments = [
  pay(
    2,
    1,
    1,
    'Ravi',
    20000.5,
    DateTime(2026, 9, 1),
    method: 'UPI',
    reference: 'UTR777',
  ),
  pay(1, 1, 1, 'Ravi', 49999.5, DateTime(2026, 7, 10)),
  pay(3, 3, 3, 'Karan', 10000, DateTime(2026, 7, 11)),
];

final refunds = [
  Refund(
    refundId: 1,
    refundNumber: 'SBH/RF/2026-2027/0001',
    studentId: 1,
    invoiceId: 1,
    refundDate: DateTime(2026, 11, 2),
    amount: 5000,
    refundMethod: 'UPI',
    reference: 'UTR9',
    reason: 'left in November',
    invoiceNumber: 'SBH/2026-2027/0001',
    studentName: 'Ravi',
  ),
];

RoomAllocation stay(
  int id,
  int studentId,
  String room,
  DateTime from,
  DateTime? to,
) => RoomAllocation(
  allocationId: id,
  studentId: studentId,
  studentName: 'x',
  roomId: id,
  roomNumber: room,
  hostelId: 1,
  bedNumber: 2,
  checkInDate: from,
  checkOutDate: to,
  status: to == null ? AllocationStatus.current : AllocationStatus.transferred,
);

class FakeBilling extends BillingRepository {
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<List<Payment>> getPayments(int hostelId) async => payments;
  @override
  Future<List<Refund>> getRefunds(int hostelId) async => refunds;
  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

class FakeStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

class FakeAllocations extends AllocationRepository {
  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => [
    stay(1, 1, '101', DateTime(2025, 7, 1), DateTime(2026, 1, 10)),
    stay(2, 1, '205', DateTime(2026, 1, 10), null),
    stay(3, 2, '12', DateTime(2024, 7, 1), DateTime(2025, 5, 1)),
  ];
}

class FakeAdmin extends AdminRepository {
  @override
  Future<AdminUser?> getCurrent(String? firebaseUid) async => const AdminUser(
    adminUserId: 1,
    userName: 'admin',
    email: 'admin@x.com',
    phone: '99999 11111',
  );
}

class FakeEmailSettings extends EmailSettingsRepository {
  FakeEmailSettings([this.values = const {}]);
  final Map<String, String> values;
  @override
  Future<Map<String, String>> getValues() async => values;
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  setUp(() {
    BillingRepository.useInstance(FakeBilling());
    StudentRepository.useInstance(FakeStudents());
    AllocationRepository.useInstance(FakeAllocations());
    AdminRepository.useInstance(FakeAdmin());
    EmailSettingsRepository.useInstance(FakeEmailSettings());
    AuthService.useAuth(
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u')),
    );
  });
  tearDown(() {
    BillingRepository.useInstance(null);
    StudentRepository.useInstance(null);
    AllocationRepository.useInstance(null);
    AdminRepository.useInstance(null);
    EmailSettingsRepository.useInstance(null);
    AuthService.useAuth(null);
    DocumentShare.useForTests(null);
  });

  group('amounts', () {
    test('Rs. and words, as the desktop', () {
      expect(Money.rupees(125000.5), 'Rs. 1,25,000.50');
      expect(
        Money.inWords(125000.5),
        'Rupees One Lakh Twenty Five Thousand and Fifty Paise Only',
      );
      expect(Money.inWords(0), 'Rupees Zero Only');
      expect(Money.inWords(85000), 'Rupees Eighty Five Thousand Only');
      expect(Money.inWords(1500000000), 'Rupees One Hundred Fifty Crore Only');
      expect(
        Money.inWords(19.99),
        'Rupees Nineteen and Ninety Nine Paise Only',
      );
    });

    test('academic year dates', () {
      expect(AcademicYear.start(2026, 7), DateTime(2026, 7, 1));
      expect(AcademicYear.end(2026, 7), DateTime(2027, 6, 30));
      expect(AcademicYear.end(2026, 1), DateTime(2026, 12, 31));
    });
  });

  group('data', () {
    test('invoice: payments and refunds in order, the current room', () async {
      final d = await DocumentData.invoice(hostel, 1);
      expect([for (final p in d.payments) p.paymentId], [1, 2]);
      expect(d.refunds.single.refundId, 1);
      expect(d.roomText, 'Room 205, bed 2');
      expect(d.student.studentName, 'Ravi');
      // Last year he was in two rooms; the last one is printed.
      final last = await DocumentData.invoice(hostel, 4);
      expect(last.roomText, 'Room 205, bed 2');
    });

    test('a student with no stay that year has no room', () async {
      final d = await DocumentData.invoice(hostel, 2);
      expect(d.roomText, '');
    });

    test('missing records are explained', () async {
      await expectMessage(
        DocumentData.invoice(hostel, 99),
        'This invoice no longer exists.',
      );
      await expectMessage(
        DocumentData.receipt(hostel, 99),
        'This payment no longer exists.',
      );
      await expectMessage(
        DocumentData.refund(hostel, 99),
        'This refund no longer exists.',
      );
    });
  });

  group('PDF', () {
    test('file names', () {
      expect(
        DocumentPdf.invoiceFileName(invoices[0]),
        'Invoice_SBH-2026-2027-0001.pdf',
      );
      expect(
        DocumentPdf.receiptFileName(payments[0]),
        'Receipt_SBH-R-2026-2027-0002.pdf',
      );
      expect(
        DocumentPdf.refundFileName('SBH/RF/2026-2027/0001'),
        'Refund_SBH-RF-2026-2027-0001.pdf',
      );
    });

    test('join leaves out empty values', () {
      expect(
        DocumentPdf.join(['Father: ', 'Rakesh', ', ', null]),
        'Father: Rakesh',
      );
      expect(DocumentPdf.join(['Course: ', '', '   Class: ', '']), '');
      expect(DocumentPdf.join(['', 'Room 1', ', ', 'DAV']), 'Room 1, DAV');
    });

    test('invoice, receipt and refund receipt are real PDFs', () async {
      final bytes = [
        await DocumentPdf.invoice(await DocumentData.invoice(hostel, 1)),
        await DocumentPdf.receipt(await DocumentData.receipt(hostel, 2)),
        await DocumentPdf.refundReceipt(await DocumentData.refund(hostel, 1)),
      ];
      for (final b in bytes) {
        expect(latin1.decode(b.sublist(0, 4)), '%PDF');
        expect(b.length, greaterThan(1500));
      }
    });

    test('a long invoice runs onto more pages', () async {
      final d = await DocumentData.invoice(hostel, 1);
      final many = [for (var i = 0; i < 60; i++) d.payments.first];
      final bytes = await DocumentPdf.invoice(
        InvoicePrintData(
          invoice: d.invoice,
          hostel: d.hostel,
          student: d.student,
          startMonth: d.startMonth,
          roomText: d.roomText,
          payments: many,
        ),
      );
      expect(
        RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length,
        greaterThan(1),
      );
    });
  });

  group('email', () {
    test('goes to the father, else the mother, else it is refused', () async {
      expect(DocumentEmail.feeContact(students[0])!.relation, 'Father');
      final mother = DocumentEmail.feeContact(students[1])!;
      expect(
        (mother.relation, mother.name, mother.email),
        ('Mother', 'Sunita', 'asha@x.com'),
      );
      expect(DocumentEmail.feeContact(students[2]), isNull);
      await expectLater(
        DocumentEmail.invoice(await DocumentData.invoice(hostel, 3)),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Neither the father nor the mother of Karan has an email address. '
                'Add one on the Students screen.',
          ),
        ),
      );
    });

    test('invoice email fills the default text', () async {
      final e = await DocumentEmail.invoice(
        await DocumentData.invoice(hostel, 1),
      );
      expect(e.to, 'rakesh@x.com');
      expect(e.copyTo, 'admin@x.com');
      expect(e.subject, 'Invoice SBH/2026-2027/0001 for Ravi, Boys Hostel');
      expect(e.body, contains('Dear Rakesh,'));
      expect(e.body, contains('Room rent: Rs. 80,000.00'));
      expect(e.body, contains('Paid so far: Rs. 70,000.00'));
      expect(e.body, contains('Pending: Rs. 22,000.00'));
      expect(e.body, contains('2026-2027'));
      expect(e.body, endsWith('Boys Hostel\n0135 2222'));
    });

    test('the text saved in Email Settings is used', () async {
      EmailSettingsRepository.useInstance(
        FakeEmailSettings({
          'Email.Receipt.Subject': 'Receipt {ReceiptNumber}',
          'Email.Receipt.Body':
              'Hi {ParentName}, {PaidAmount} on {PaymentDate} '
              'by {PaymentMethod}. Call {AdminPhone} {Unknown}',
        }),
      );
      final e = await DocumentEmail.receipt(
        await DocumentData.receipt(hostel, 2),
      );
      expect(e.subject, 'Receipt SBH/R/2026-2027/0002');
      expect(
        e.body,
        'Hi Rakesh, Rs. 20,000.50 on 01 Sep 2026 by UPI. Call 99999 11111 {Unknown}',
      );
    });

    test('no copy when the parent is the admin', () async {
      students[0] = student(1, 'Ravi', fatherEmail: 'ADMIN@x.com');
      addTearDown(
        () => students[0] = student(1, 'Ravi', fatherEmail: 'rakesh@x.com'),
      );
      final e = await DocumentEmail.invoice(
        await DocumentData.invoice(hostel, 1),
      );
      expect(e.copyTo, '');
    });

    test('fee line, with and without transport', () {
      expect(
        DocumentEmail.feeLine(invoices[0], 7),
        '2026-2027 (invoice SBH/2026-2027/0001): room rent Rs. 80,000.00 + '
        'transport Rs. 12,000.00 = Rs. 92,000.00, paid Rs. 70,000.00, '
        'pending Rs. 22,000.00',
      );
      final plain = Invoice(
        invoiceId: 9,
        invoiceNumber: 'X/1',
        studentId: 1,
        academicYear: 2026,
        roomRent: 5000,
        transportAmount: 0,
      );
      expect(
        DocumentEmail.feeLine(plain, 7),
        '2026-2027 (invoice X/1): room rent Rs. 5,000.00, paid Rs. 0.00, '
        'pending Rs. 5,000.00',
      );
    });

    test('reminder: needs something pending and a parent email', () async {
      await expectLater(
        DocumentEmail.reminder([await DocumentData.invoice(hostel, 2)]),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Amit has no pending fee, so no reminder is needed.',
          ),
        ),
      );
      await expectLater(
        DocumentEmail.reminder([await DocumentData.invoice(hostel, 3)]),
        throwsA(isA<ValidationException>()),
      );
    });

    test('attendance email goes to the mother, else the father', () async {
      expect(DocumentEmail.attendanceContact(students[1])!.relation, 'Mother');
      final both = student(
        5,
        'Both',
        fatherEmail: 'f@x.com',
        motherEmail: 'm@x.com',
      );
      expect(DocumentEmail.attendanceContact(both)!.email, 'm@x.com');
      expect(DocumentEmail.attendanceContact(students[0])!.relation, 'Father');
      expect(DocumentEmail.attendanceContact(students[2]), isNull);
      final e = await DocumentEmail.absence(
        student: students[1],
        hostel: hostel,
        date: DateTime(2026, 11, 24),
        roomNumber: '12',
        remarks: ' gone home ',
      );
      expect(e.to, 'asha@x.com');
      expect(e.subject, 'Amit was not present at Boys Hostel on 24 Nov 2026');
      expect(e.body, contains('Amit (room 12) was not present'));
      await expectLater(
        DocumentEmail.absence(
          student: students[2],
          hostel: hostel,
          date: DateTime(2026, 11, 24),
          roomNumber: '1',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Neither the mother nor the father of Karan has an email address.',
          ),
        ),
      );
    });

    test('refund receipt email has fixed wording', () async {
      final e = await DocumentEmail.refund(
        await DocumentData.refund(hostel, 1),
      );
      expect(e.subject, 'Refund receipt SBH/RF/2026-2027/0001 for Ravi');
      expect(
        e.body,
        contains(
          'We have refunded Rs. 5,000.00 for Ravi on 02 Nov 2026 (UPI), from '
          'the hostel fee for the academic year 2026-2027 (invoice '
          'SBH/2026-2027/0001).',
        ),
      );
    });
  });

  group('screens', () {
    late List<String> shared;

    setUp(() {
      shared = [];
      DocumentShare.useForTests((files, subject, text) async {
        shared.add(
          '${files.map((f) => f.name).join('+')}|'
          '${files.every((f) => f.bytes.length > 1000)}|${subject ?? ''}|'
          '${text == null ? '' : 'text'}',
        );
      });
    });

    Future<void> open(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
      await tester.pumpAndSettle();
    }

    Future<void> menu(WidgetTester tester, String key, String item) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('invoice PDF is shared', (tester) async {
      await open(tester, InvoicesScreen(hostel: hostel, today: today));
      await menu(tester, 'invoiceMenu_1', 'Invoice PDF');
      expect(shared, ['Invoice_SBH-2026-2027-0001.pdf|true||']);
    });

    testWidgets('invoice email shows who, then shares with the text', (
      tester,
    ) async {
      await open(tester, InvoicesScreen(hostel: hostel, today: today));
      await menu(tester, 'invoiceMenu_1', 'Email Invoice');
      expect(find.byKey(const Key('emailDraft')), findsOneWidget);
      expect(find.text('rakesh@x.com'), findsOneWidget);
      expect(find.text('admin@x.com'), findsOneWidget);
      expect(
        find.text('Invoice SBH/2026-2027/0001 for Ravi, Boys Hostel'),
        findsOneWidget,
      );
      expect(shared, isEmpty);
      await tester.tap(find.byKey(const Key('shareEmail')));
      await tester.pumpAndSettle();
      expect(shared, [
        'Invoice_SBH-2026-2027-0001.pdf|true|Invoice SBH/2026-2027/0001 for Ravi, Boys Hostel|text',
      ]);
    });

    testWidgets('cancelling the email shares nothing', (tester) async {
      await open(tester, InvoicesScreen(hostel: hostel, today: today));
      await menu(tester, 'invoiceMenu_1', 'Email Invoice');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(shared, isEmpty);
    });

    testWidgets('no parent email: a message, no share', (tester) async {
      await open(tester, InvoicesScreen(hostel: hostel, today: today));
      await menu(tester, 'invoiceMenu_3', 'Email Invoice');
      expect(
        find.text(
          'Neither the father nor the mother of Karan has an email address. '
          'Add one on the Students screen.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('emailDraft')), findsNothing);
      expect(shared, isEmpty);
    });

    testWidgets('receipt PDF and email from Payments', (tester) async {
      await open(tester, PaymentsScreen(hostel: hostel, today: today));
      await menu(tester, 'paymentMenu_2', 'Receipt PDF');
      expect(
        shared.single,
        startsWith('Receipt_SBH-R-2026-2027-0002.pdf|true'),
      );
      await menu(tester, 'paymentMenu_2', 'Email Receipt');
      expect(
        find.text('Payment receipt SBH/R/2026-2027/0002 for Ravi, Boys Hostel'),
        findsOneWidget,
      );
    });

    testWidgets('refund receipt PDF and email from Refunds', (tester) async {
      await open(tester, RefundsScreen(hostel: hostel, today: today));
      await menu(tester, 'refundMenu_1', 'Receipt PDF');
      expect(
        shared.single,
        startsWith('Refund_SBH-RF-2026-2027-0001.pdf|true'),
      );
      await menu(tester, 'refundMenu_1', 'Email Receipt');
      expect(
        find.text('Refund receipt SBH/RF/2026-2027/0001 for Ravi'),
        findsOneWidget,
      );
    });
  });
}
