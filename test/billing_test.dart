import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/payment.dart';
import 'package:hostel_mobile_app/screens/invoices_screen.dart';
import 'package:hostel_mobile_app/screens/payments_screen.dart';
import 'package:hostel_mobile_app/services/billing_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

const hostel = Hostel(hostelId: 1, hostelName: 'Boys Hostel');
final today = DateTime(2026, 11, 24);

Invoice inv(
  int id,
  String number,
  int student,
  String name,
  int year,
  double rent, {
  double transport = 0,
  double received = 0,
  double waived = 0,
}) => Invoice(
  invoiceId: id,
  invoiceNumber: number,
  studentId: student,
  studentName: name,
  academicYear: year,
  roomRent: rent,
  transportAmount: transport,
  receivedAmount: received,
  waivedAmount: waived,
  invoiceDate: DateTime(year, 7, 5),
);

final invoices = [
  inv(
    1,
    'SBH/2026-2027/0001',
    1,
    'Ravi',
    2026,
    80000,
    transport: 12000,
    received: 50000,
  ), // partly paid, 42000 pending
  inv(2, 'SBH/2026-2027/0002', 2, 'Amit', 2026, 70000), // unpaid
  inv(
    3,
    'SBH/2026-2027/0003',
    3,
    'Karan',
    2026,
    60000,
    received: 60000,
  ), // paid
  inv(
    4,
    'SBH/2025-2026/0004',
    1,
    'Ravi',
    2025,
    75000,
    received: 75000,
  ), // last year, paid
];

final payments = [
  Payment(
    paymentId: 11,
    receiptNumber: 'SBH/R/2026-2027/0002',
    studentId: 1,
    invoiceId: 1,
    paymentDate: DateTime(2026, 9, 1),
    amount: 20000,
    paymentMethod: PaymentMethod.upi,
    reference: 'UPI777',
    studentName: 'Ravi',
    invoiceNumber: 'SBH/2026-2027/0001',
  ),
  Payment(
    paymentId: 10,
    receiptNumber: 'SBH/R/2026-2027/0001',
    studentId: 3,
    invoiceId: 3,
    paymentDate: DateTime(2026, 7, 10),
    amount: 60000,
    paymentMethod: PaymentMethod.cash,
    studentName: 'Karan',
    invoiceNumber: 'SBH/2026-2027/0003',
    remarks: 'Full year',
  ),
];

/// Records the calls; the database rules are tested in PostgreSQL.
class FakeBilling extends BillingRepository {
  final calls = <Map<String, Object?>>[];
  ValidationException? failWith;

  void _call(Map<String, Object?> c) {
    calls.add(c);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<List<Payment>> getPayments(int hostelId) async => payments;
  @override
  Future<List<PaymentChange>> getChanges(int hostelId) async => [
    PaymentChange(
      paymentChangeId: 1,
      receiptNumber: 'SBH/R/2026-2027/0002',
      studentName: 'Ravi',
      changeType: 'Edited',
      changedDate: DateTime(2026, 9, 2, 10, 5),
      details: 'Amount ₹2,000.00 to ₹20,000.00',
      reason: 'wrong amount typed',
    ),
  ];
  @override
  Future<int> getAcademicYearStartMonth() async => 7;

  @override
  Future<void> updateFee({
    required int invoiceId,
    required double roomRent,
    required double transport,
    required String remarks,
  }) async => _call({
    'call': 'updateFee',
    'invoice': invoiceId,
    'rent': roomRent,
    'transport': transport,
    'remarks': remarks,
  });

  @override
  Future<void> deleteInvoice(int invoiceId) async =>
      _call({'call': 'deleteInvoice', 'invoice': invoiceId});

  @override
  Future<int> createYearFees(int year, Map<int, (double, double)> fees) async {
    _call({'call': 'createYearFees', 'year': year, 'fees': fees});
    return fees.length;
  }

  @override
  Future<String> recordPayment({
    required int invoiceId,
    required String date,
    required double amount,
    required String method,
    required String reference,
    required String remarks,
  }) async {
    _call({
      'call': 'record',
      'invoice': invoiceId,
      'date': date,
      'amount': amount,
      'method': method,
      'reference': reference,
      'remarks': remarks,
    });
    return 'SBH/R/2026-2027/0003';
  }

  @override
  Future<void> editPayment({
    required int paymentId,
    required String date,
    required double amount,
    required String method,
    required String reference,
    required String remarks,
    required String reason,
  }) async => _call({
    'call': 'edit',
    'payment': paymentId,
    'date': date,
    'amount': amount,
    'method': method,
    'reference': reference,
    'reason': reason,
  });

  @override
  Future<void> deletePayment(int paymentId, String reason) async =>
      _call({'call': 'deletePayment', 'payment': paymentId, 'reason': reason});
}

class FakeAllocations extends AllocationRepository {
  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => [
    for (final (id, name, room) in [
      (1, 'Ravi', '10'),
      (2, 'Amit', '2'),
      (5, 'Neha', '101'),
    ])
      RoomAllocation(
        allocationId: id,
        studentId: id,
        studentName: name,
        roomId: id,
        roomNumber: room,
        hostelId: 1,
        bedNumber: 1,
        checkInDate: DateTime(2025, 7, 5),
        status: AllocationStatus.current,
      ),
  ];
}

void main() {
  late FakeBilling db;

  setUp(() {
    db = FakeBilling();
    BillingRepository.useInstance(db);
    AllocationRepository.useInstance(FakeAllocations());
  });
  tearDown(() {
    BillingRepository.useInstance(null);
    AllocationRepository.useInstance(null);
  });

  group('rules', () {
    test('invoice amounts and status', () {
      expect(invoices[0].totalAmount, 92000);
      expect(invoices[0].pendingAmount, 42000);
      expect(invoices[0].status, InvoiceStatus.partlyPaid);
      expect(invoices[1].status, InvoiceStatus.unpaid);
      expect(invoices[2].status, InvoiceStatus.paid);
      final waivedAndRefunded = Invoice(
        invoiceId: 9,
        invoiceNumber: 'X',
        studentId: 9,
        academicYear: 2026,
        roomRent: 100000,
        transportAmount: 0,
        waivedAmount: 10000,
        receivedAmount: 60000,
        refundedAmount: 5000,
      );
      expect(waivedAndRefunded.totalAmount, 85000);
      expect(waivedAndRefunded.paidAmount, 55000);
      expect(waivedAndRefunded.pendingAmount, 30000);
    });

    test('invoice search, status and year filters, summary', () {
      List<String> nums(List<Invoice> l) => [
        for (final i in l) i.invoiceNumber,
      ];
      expect(
        nums(BillingService.filterInvoices(invoices, 'ravi', null, null)),
        ['SBH/2026-2027/0001', 'SBH/2025-2026/0004'],
      );
      expect(
        nums(
          BillingService.filterInvoices(
            invoices,
            null,
            InvoiceStatus.paid,
            2026,
          ),
        ),
        ['SBH/2026-2027/0003'],
      );
      expect(BillingService.years(invoices), [2026, 2025]);
      expect(
        BillingService.invoiceSummary(
          BillingService.filterInvoices(invoices, null, null, 2026),
        ),
        '3 invoices, total ₹2,22,000.00, paid ₹1,10,000.00, pending ₹1,12,000.00',
      );
    });

    test('new year fees: students in a room without the year\'s fee', () async {
      final current = await FakeAllocations().getForHostel(1);
      final c = BillingService.newYearCandidates(current, invoices, 2027);
      expect([for (final x in c) x.studentName], ['Amit', 'Neha', 'Ravi']);
      expect(c[2].lastYear!.roomRent, 80000);
      expect(c[1].lastYear, isNull);
      expect(
        [
          for (final x in BillingService.newYearCandidates(
            current,
            invoices,
            2026,
          ))
            x.studentName,
        ],
        ['Neha'],
      );
      // Next year from three months before it starts (1 Apr for July).
      expect(BillingService.defaultNewYear(DateTime(2027, 3, 31), 7), 2026);
      expect(BillingService.defaultNewYear(DateTime(2027, 4, 1), 7), 2027);
    });

    test('new year fees: rows are read as on the desktop', () {
      final c = [
        NewYearCandidate(1, 'Ravi', '10, bed 1', null),
        NewYearCandidate(2, 'Amit', '2, bed 1', null),
      ];
      Matcher message(String m) => throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', m),
      );
      expect(
        () => BillingService.readYearFees(c, {}),
        message('Please enter the room rent for at least one student.'),
      );
      expect(
        () => BillingService.readYearFees(c, {2: ('abc', '')}),
        message('Please enter a valid room rent for Amit.'),
      );
      expect(
        () => BillingService.readYearFees(c, {1: ('80000', 'x')}),
        message(
          'Please enter a valid transport amount for Ravi, or leave '
          'it empty.',
        ),
      );
      expect(
        BillingService.readYearFees(c, {1: ('85,000', '2000'), 2: ('', '')}),
        {1: (85000.0, 2000.0)},
      );
    });

    test('payment search, method filter and invoices with pending', () {
      expect(
        [
          for (final p in BillingService.filterPayments(
            payments,
            'upi777',
            null,
          ))
            p.receiptNumber,
        ],
        ['SBH/R/2026-2027/0002'],
      );
      expect(
        BillingService.filterPayments(
          payments,
          null,
          PaymentMethod.cash,
        ).single.studentName,
        'Karan',
      );
      expect(
        BillingService.paymentSummary(payments),
        '2 payments, received ₹80,000.00',
      );
      expect(
        [
          for (final i in BillingService.invoicesWithPending(invoices))
            i.studentName,
        ],
        ['Amit', 'Ravi'],
      );
    });

    test('payments are checked as on the desktop', () async {
      Future<void> expectMessage(Future<void> f, String m) => expectLater(
        f,
        throwsA(
          isA<ValidationException>().having((e) => e.message, 'message', m),
        ),
      );
      Future<void> record(
        String amount,
        String method, {
        String? ref,
        DateTime? date,
      }) => BillingService.recordPayment(
        invoice: invoices[0],
        date: date ?? today,
        today: today,
        amountText: amount,
        method: method,
        reference: ref,
      );
      await expectMessage(
        BillingService.recordPayment(
          invoice: null,
          date: today,
          today: today,
          amountText: '1',
          method: 'Cash',
        ),
        'Please select the invoice.',
      );
      await expectMessage(
        record('abc', 'Cash'),
        'Please enter the amount as a number, for example 25000.',
      );
      await expectMessage(
        record('0', 'Cash'),
        'Please enter an amount greater than zero.',
      );
      await expectMessage(
        record('10', 'Cash', date: DateTime(2026, 11, 25)),
        'The payment date cannot be in the future.',
      );
      await expectMessage(
        record('10', PaymentMethod.cheque),
        'Please enter the cheque number.',
      );
      await expectMessage(
        record('10', PaymentMethod.upi, ref: ' '),
        'Please enter the upi transaction id.',
      );
      await expectMessage(
        record('42000.01', 'Cash'),
        'The amount cannot be more than the pending amount of ₹42,000.00. '
        'Advance or extra payments are not accepted.',
      );
      expect(db.calls, isEmpty);
    });
  });

  group('Invoices screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: InvoicesScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists invoices with amounts, status and summary', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.text(
          '4 invoices, total ₹2,97,000.00, paid ₹1,85,000.00, '
          'pending ₹1,12,000.00',
        ),
        findsOneWidget,
      );
      expect(find.text('SBH/2026-2027/0001  ·  2026-2027'), findsOneWidget);
      expect(find.text('₹42,000.00'), findsOneWidget);
      expect(find.text('Partly paid'), findsWidgets);
      await tester.tap(find.byKey(const Key('invoiceStatus_Unpaid')));
      await tester.pump();
      expect(find.text('Amit'), findsOneWidget);
      expect(find.text('Ravi'), findsNothing);
    });

    testWidgets('record payment from an invoice, amount suggested', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('invoice_1')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Record Payment'), findsOneWidget);
      expect(
        find.text(
          'Fee 2026-2027:  total ₹92,000.00,  paid ₹50,000.00,  '
          'pending ₹42,000.00',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, '42000.00'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('payAmount')), '12,000');
      await tester.tap(find.byKey(const Key('payMethod')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      expect(find.text('UPI transaction id *'), findsOneWidget);
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter the upi transaction id.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('payReference')), 'T123');
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect(db.calls.single, {
        'call': 'record',
        'invoice': 1,
        'date': '2026-11-24',
        'amount': 12000.0,
        'method': 'UPI',
        'reference': 'T123',
        'remarks': '',
      });
      expect(
        find.text('Payment recorded: receipt SBH/R/2026-2027/0003.'),
        findsOneWidget,
      );
    });

    testWidgets('edit fee: total and pending shown while typing', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('invoiceMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Fee'));
      await tester.pumpAndSettle();
      expect(find.text('₹50,000.00'), findsOneWidget); // paid so far
      await tester.enterText(find.byKey(const Key('feeRent')), '85000');
      await tester.pump();
      expect(
        find.text('Total fee: ₹97,000.00   (pending ₹47,000.00)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('saveFee')));
      await tester.pumpAndSettle();
      expect(db.calls.single, {
        'call': 'updateFee',
        'invoice': 1,
        'rent': 85000.0,
        'transport': 12000.0,
        'remarks': '',
      });
      expect(find.text('Fee saved.'), findsOneWidget);
    });

    testWidgets('delete: the database refusal is shown', (tester) async {
      db.failWith = const ValidationException(
        'Invoice SBH/2026-2027/0001 has payments or emails and cannot be '
        'deleted. Use Edit Fee to change it.',
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('invoiceMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be deleted'), findsOneWidget);
    });

    testWidgets('new year fees for the students in rooms', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('newYearFees')));
      await tester.pumpAndSettle();
      // 24 Nov 2026 is before 1 Apr 2027, so 2026-2027 is chosen: only Neha.
      expect(
        find.text(
          '1 students without a fee for 2026-2027. Type the room '
          'rent and transport for each student staying on. Leave a row '
          'empty to skip the student.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('newYear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2027-2028').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 students without a fee for 2027-2028'),
        findsOneWidget,
      );
      expect(
        find.text('Last year: rent ₹80,000.00, transport ₹12,000.00'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('newRent_1')), '85000');
      await tester.enterText(find.byKey(const Key('newTransport_1')), '12000');
      await tester.enterText(find.byKey(const Key('newRent_5')), '70000');
      await tester.tap(find.byKey(const Key('createYearFees')));
      await tester.pumpAndSettle();
      expect(
        find.text('Create the 2027-2028 fee for 2 student(s)?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmYearFees')));
      await tester.pumpAndSettle();
      expect(db.calls.single, {
        'call': 'createYearFees',
        'year': 2027,
        'fees': {1: (85000.0, 12000.0), 5: (70000.0, 0.0)},
      });
      expect(
        find.text('Created the 2027-2028 fee for 2 student(s).'),
        findsOneWidget,
      );
    });
  });

  group('Payments screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PaymentsScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists payments, filters by method', (tester) async {
      await open(tester);
      expect(find.text('2 payments, received ₹80,000.00'), findsOneWidget);
      expect(find.text('SBH/R/2026-2027/0002  ·  01 Sep 2026'), findsOneWidget);
      expect(
        find.text('UPI  ·  UPI777  ·  invoice SBH/2026-2027/0001'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('paymentMethod_Cash')));
      await tester.pump();
      expect(find.text('1 payment, received ₹60,000.00'), findsOneWidget);
    });

    testWidgets('record from Payments: only invoices with pending', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('recordPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payInvoice')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Karan'), findsNothing);
      await tester.tap(find.textContaining('Amit').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '70000.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect(db.calls.single['invoice'], 2);
      expect(db.calls.single['amount'], 70000.0);
      expect(db.calls.single['method'], 'Cash');
    });

    testWidgets('edit with a reason', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('payment_10')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Edit Payment'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('payAmount')), '59000');
      await tester.enterText(
        find.byKey(const Key('payReason')),
        'wrong amount typed',
      );
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect(db.calls.single, {
        'call': 'edit',
        'payment': 10,
        'date': '2026-07-10',
        'amount': 59000.0,
        'method': 'Cash',
        'reference': '',
        'reason': 'wrong amount typed',
      });
      expect(find.text('Payment SBH/R/2026-2027/0001 saved.'), findsOneWidget);
    });

    testWidgets('delete with a reason', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('paymentMenu_11')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('deleteReason')),
        'entered twice',
      );
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();
      expect(db.calls.single, {
        'call': 'deletePayment',
        'payment': 11,
        'reason': 'entered twice',
      });
      expect(
        find.text('Payment SBH/R/2026-2027/0002 deleted.'),
        findsOneWidget,
      );
    });

    testWidgets('change history', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('changeHistory')));
      await tester.pumpAndSettle();
      expect(find.text('Amount ₹2,000.00 to ₹20,000.00'), findsOneWidget);
      expect(find.text('Reason: wrong amount typed'), findsOneWidget);
      expect(find.text('02 Sep 2026 10:05'), findsOneWidget);
    });
  });
}
