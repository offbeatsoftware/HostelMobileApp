import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/payment.dart';
import 'package:hostel_mobile_app/models/refund.dart';
import 'package:hostel_mobile_app/screens/payments_screen.dart';
import 'package:hostel_mobile_app/screens/refunds_screen.dart';
import 'package:hostel_mobile_app/services/billing_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

const hostel = Hostel(hostelId: 1, hostelName: 'Boys Hostel');
final today = DateTime(2026, 11, 24);

Invoice inv(
  int id,
  String name,
  int year,
  double rent,
  double received, {
  double refunded = 0,
}) => Invoice(
  invoiceId: id,
  invoiceNumber: 'SBH/$year-${year + 1}/000$id',
  studentId: id,
  studentName: name,
  academicYear: year,
  roomRent: rent,
  transportAmount: 0,
  receivedAmount: received,
  refundedAmount: refunded,
);

final invoices = [
  inv(1, 'Ravi', 2026, 80000, 50000), // 50000 refundable
  inv(2, 'Amit', 2026, 70000, 0), // nothing paid
  inv(3, 'Karan', 2025, 60000, 60000, refunded: 20000), // 40000 refundable
  inv(4, 'Zoya', 2025, 30000, 20000, refunded: 20000), // nothing left
];

Refund refund(int id, String student, double amount, {String? reference}) =>
    Refund(
      refundId: id,
      refundNumber: 'SBH/RF/2026-2027/000$id',
      studentId: id,
      invoiceId: id,
      refundDate: DateTime(2026, 11, id),
      amount: amount,
      refundMethod: reference == null ? PaymentMethod.cash : PaymentMethod.upi,
      reference: reference,
      reason: 'left in November',
      invoiceNumber: 'SBH/2026-2027/000$id',
      studentName: student,
    );

class FakeBilling extends BillingRepository {
  final calls = <Map<String, Object?>>[];
  final deleted = <Map<String, Object?>>[];
  ValidationException? failWith;
  var refunds = [
    refund(2, 'Karan', 20000, reference: 'UTR9'),
    refund(1, 'Ravi', 5000),
  ];
  var failLoad = false;

  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<List<Payment>> getPayments(int hostelId) async => [];
  @override
  Future<List<Refund>> getRefunds(int hostelId) async {
    if (failLoad) throw Exception('offline');
    return refunds;
  }

  @override
  Future<int> getAcademicYearStartMonth() async => 7;

  @override
  Future<String> recordRefund({
    required int invoiceId,
    required String date,
    required double amount,
    required String method,
    required String reference,
    required String reason,
  }) async {
    if (failWith != null) throw failWith!;
    calls.add({
      'invoice': invoiceId,
      'date': date,
      'amount': amount,
      'method': method,
      'reference': reference,
      'reason': reason,
    });
    return 'SBH/RF/2026-2027/0003';
  }

  @override
  Future<void> deleteRefund(int refundId, String reason) async {
    deleted.add({'id': refundId, 'reason': reason});
    refunds = refunds.where((r) => r.refundId != refundId).toList();
  }
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

Future<String> record(
  Invoice? invoice, {
  String amount = '5000',
  String method = PaymentMethod.cash,
  String reference = '',
  String reason = 'left the hostel',
  DateTime? date,
}) => BillingService.recordRefund(
  invoice: invoice,
  date: date ?? today,
  today: today,
  amountText: amount,
  method: method,
  reference: reference,
  reason: reason,
);

void main() {
  late FakeBilling db;

  setUp(() {
    db = FakeBilling();
    BillingRepository.useInstance(db);
  });
  tearDown(() => BillingRepository.useInstance(null));

  group('BillingService refunds', () {
    test('only fees with money paid can be refunded from', () {
      final list = BillingService.refundableInvoices(invoices);
      expect([for (final i in list) i.studentName], ['Karan', 'Ravi']);
    });

    test('search and summary', () {
      expect(BillingService.filterRefunds(db.refunds, 'utr9').length, 1);
      expect(BillingService.filterRefunds(db.refunds, 'RAVI').length, 1);
      expect(BillingService.filterRefunds(db.refunds, 'november').length, 2);
      expect(
        BillingService.refundSummary(db.refunds),
        '2 refunds, ₹25,000.00 paid back',
      );
      expect(
        BillingService.refundSummary([db.refunds.first]),
        '1 refund, ₹20,000.00 paid back',
      );
    });

    test('a valid refund is sent to the database', () async {
      final number = await record(
        invoices[0],
        amount: ' 5,000.50 ',
        method: PaymentMethod.upi,
        reference: ' UTR1 ',
        reason: '  left  ',
      );
      expect(number, 'SBH/RF/2026-2027/0003');
      expect(db.calls.single, {
        'invoice': 1,
        'date': '2026-11-24',
        'amount': 5000.5,
        'method': 'UPI',
        'reference': 'UTR1',
        'reason': 'left',
      });
    });

    test('the desktop messages', () async {
      await expectMessage(
        record(null),
        'Please select the fee to refund from.',
      );
      await expectMessage(
        record(invoices[0], amount: 'abc'),
        'Please enter the amount as a number, for example 5000.',
      );
      await expectMessage(
        record(invoices[0], date: DateTime(2026, 11, 25)),
        'The refund date cannot be in the future.',
      );
      await expectMessage(
        record(invoices[0], amount: '0'),
        'Please enter an amount greater than zero.',
      );
      await expectMessage(
        record(invoices[0], amount: '10.005'),
        'The amount can have at most two decimal places (paise).',
      );
      await expectMessage(
        record(invoices[0], method: 'Card'),
        'Please select how the money was paid back.',
      );
      await expectMessage(
        record(invoices[0], method: PaymentMethod.cheque),
        'Please enter the cheque number.',
      );
      await expectMessage(
        record(invoices[0], reason: ' '),
        'Please enter the reason for the refund, for example '
        '"left the hostel in December".',
      );
      await expectMessage(
        record(invoices[1]),
        'Nothing is paid on invoice SBH/2026-2027/0002, so nothing can be '
        'refunded.',
      );
      await expectMessage(
        record(invoices[2], amount: '40000.01'),
        'The refund cannot be more than ₹40,000.00, the amount paid on invoice '
        'SBH/2025-2026/0003 after earlier refunds.',
      );
      expect(db.calls, isEmpty);
    });

    test('delete needs a reason', () async {
      await expectMessage(
        BillingService.deleteRefund(db.refunds.first, '  '),
        'Please enter the reason, for example "entered twice by mistake".',
      );
      await BillingService.deleteRefund(db.refunds.first, ' typed twice ');
      expect(db.deleted.single, {'id': 2, 'reason': 'typed twice'});
    });
  });

  group('Refunds screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RefundsScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the refunds with a summary and search', (tester) async {
      await open(tester);
      expect(find.text('2 refunds, ₹25,000.00 paid back'), findsOneWidget);
      expect(
        find.text('SBH/RF/2026-2027/0002  ·  02 Nov 2026'),
        findsOneWidget,
      );
      expect(
        find.text('UPI  ·  UTR9  ·  invoice SBH/2026-2027/0002'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('refundSearch')), 'ravi');
      await tester.pump();
      expect(find.text('1 refund, ₹5,000.00 paid back'), findsOneWidget);
      expect(find.byKey(const Key('refund_2')), findsNothing);
    });

    testWidgets('empty and error states', (tester) async {
      db.refunds = [];
      await open(tester);
      expect(find.byKey(const Key('refundsEmpty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      db.failLoad = true;
      await open(tester);
      expect(find.byKey(const Key('refundsError')), findsOneWidget);
    });

    testWidgets('records a refund after asking', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('newRefund')));
      await tester.pumpAndSettle();
      // Only fees with money paid are offered.
      await tester.tap(find.byKey(const Key('refundInvoice')));
      await tester.pumpAndSettle();
      expect(find.text('Zoya  ·  SBH/2025-2026/0004'), findsNothing);
      expect(find.text('Amit  ·  SBH/2026-2027/0002'), findsNothing);
      await tester.tap(find.text('Ravi  ·  SBH/2026-2027/0001').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Can refund up to ₹50,000.00'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('refundAmount')), '5000');
      await tester.enterText(
        find.byKey(const Key('refundReason')),
        'left the hostel',
      );
      await tester.tap(find.byKey(const Key('saveRefund')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmRefund')), findsOneWidget);
      expect(
        find.textContaining('Refund ₹5,000.00 from invoice'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmRefund')));
      await tester.pumpAndSettle();
      expect(
        find.text('Refund recorded: SBH/RF/2026-2027/0003.'),
        findsOneWidget,
      );
      expect(db.calls.single['invoice'], 1);
      expect(db.calls.single['method'], 'Cash');
    });

    testWidgets('shows what is wrong in the form', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('newRefund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveRefund')));
      await tester.pumpAndSettle();
      expect(
        find.text('Please select the fee to refund from.'),
        findsOneWidget,
      );
    });

    testWidgets('delete asks for a reason', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('refundMenu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeleteRefund')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Please enter the reason, for example "entered twice by mistake".',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('deleteRefundReason')),
        'entered twice',
      );
      await tester.tap(find.byKey(const Key('confirmDeleteRefund')));
      await tester.pumpAndSettle();
      expect(
        find.text('Refund SBH/RF/2026-2027/0002 deleted.'),
        findsOneWidget,
      );
      expect(db.deleted.single['reason'], 'entered twice');
      expect(find.byKey(const Key('refund_2')), findsNothing);
    });

    testWidgets('the Payments screen opens Refunds', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PaymentsScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openRefunds')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Refunds'), findsOneWidget);
      expect(find.byKey(const Key('refundsList')), findsOneWidget);
    });
  });
}
