import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/room_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/payment.dart';
import 'package:hostel_mobile_app/models/refund.dart';
import 'package:hostel_mobile_app/models/room.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/dashboard_screen.dart';
import 'package:hostel_mobile_app/services/dashboard_service.dart';
import 'package:hostel_mobile_app/services/money.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

final today = DateTime(2026, 11, 24);

Student st(int id, String name, {String status = StudentStatus.active}) =>
    Student(
      studentId: id,
      hostelId: 1,
      studentName: name,
      gender: 'Male',
      admissionDate: DateTime(2026, 7, 1),
      status: status,
    );

Room rm(int id, int capacity, int occupied, {bool active = true}) => Room(
  roomId: id,
  hostelId: 1,
  roomNumber: '$id',
  sharingTypeId: capacity,
  gender: 'Male',
  isActive: active,
  sharingName: 'X',
  capacity: capacity,
  occupied: occupied,
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
  invoiceNumber: 'SBH/$id',
  studentId: student,
  studentName: name,
  academicYear: year,
  roomRent: fee,
  transportAmount: 0,
  receivedAmount: received,
);

Payment pay(int id, DateTime date, double amount, String name) => Payment(
  paymentId: id,
  receiptNumber: 'R$id',
  studentId: 1,
  invoiceId: 1,
  paymentDate: date,
  amount: amount,
  paymentMethod: 'Cash',
  studentName: name,
);

RoomAllocation al(int id, String name, DateTime checkIn, String room) =>
    RoomAllocation(
      allocationId: id,
      studentId: id,
      studentName: name,
      roomId: 1,
      roomNumber: room,
      hostelId: 1,
      checkInDate: checkIn,
      status: AllocationStatus.current,
    );

final students = [
  st(1, 'Ravi'),
  st(2, 'Amit'),
  st(3, 'Karan'),
  st(4, 'Gone', status: StudentStatus.left),
];
final rooms = [rm(1, 2, 2), rm(2, 3, 1), rm(3, 2, 0, active: false)];
final invoices = [
  inv(1, 1, 'Ravi', 2026, 80000, 50000), // 30000 pending
  inv(2, 2, 'Amit', 2026, 70000, 0), // 70000 pending
  inv(3, 3, 'Karan', 2026, 60000, 60000), // paid
  inv(4, 1, 'Ravi', 2025, 75000, 65000), // 10000 pending from last year
];
final payments = [
  pay(1, DateTime(2026, 7, 10), 60000, 'Karan'),
  pay(2, DateTime(2026, 8, 5), 30000, 'Ravi'),
  pay(3, DateTime(2026, 11, 2), 20000, 'Ravi'),
  pay(4, DateTime(2026, 6, 30), 65000, 'Ravi'), // last academic year
];
final refunds = [
  Refund(
    refundId: 1,
    refundNumber: 'RF1',
    studentId: 3,
    invoiceId: 3,
    refundDate: DateTime(2026, 11, 20),
    amount: 5000,
  ),
];
final allocations = [
  al(1, 'Ravi', DateTime(2026, 7, 5), '1'),
  al(2, 'Amit', DateTime(2026, 8, 1), '1'),
  al(3, 'Karan', DateTime(2026, 7, 2), '2'),
];

DashboardData compute() => DashboardService.compute(
  today: today,
  startMonth: 7,
  students: students,
  rooms: rooms,
  invoices: invoices,
  payments: payments,
  refunds: refunds,
  allocations: allocations,
);

class FixedStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

class FixedRooms extends RoomRepository {
  @override
  Future<List<Room>> getForHostel(int hostelId) async => rooms;
}

class FixedBilling extends BillingRepository {
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<List<Payment>> getPayments(int hostelId) async => payments;
  @override
  Future<List<Refund>> getRefunds(int hostelId) async => refunds;
  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

class FixedAllocations extends AllocationRepository {
  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => allocations;
}

void main() {
  test('figures as the desktop calculates them', () {
    final d = compute();
    expect(d.academicYear, '2026-2027');
    expect(d.activeStudents, 3);
    expect(d.leftStudents, 1);
    expect(d.totalBeds, 5, reason: 'active rooms only');
    expect(d.occupiedBeds, 3);
    expect(d.freeBeds, 2);
    expect(d.invoicedThisYear, 210000);
    // November: 20000 paid less 5000 refunded.
    expect(d.receivedThisMonth, 15000);
    // Since 1 July: 60000 + 30000 + 20000 - 5000 (not June's 65000).
    expect(d.receivedThisYear, 105000);
    // Pending over all invoices: Amit 70000, Ravi 30000 + 10000.
    expect(d.pendingAmount, 110000);
    expect(d.pendingStudents, 2);
    expect([for (final x in d.highestPending) x.studentName], ['Amit', 'Ravi']);
    expect(d.highestPending[1].pendingAmount, 40000);
    expect([for (final p in d.latestPayments) p.paymentId], [3, 2, 1, 4]);
    expect(
      [for (final a in d.recentCheckIns) a.studentName],
      ['Amit', 'Ravi', 'Karan'],
    );
    expect(d.paymentsPerMonth.length, 12);
    expect(d.paymentsPerMonth.first.month, DateTime(2026, 7, 1));
    expect(d.paymentsPerMonth.last.month, DateTime(2027, 6, 1));
    expect(
      [for (final m in d.paymentsPerMonth.take(6)) m.amount],
      [60000, 30000, 0, 0, 15000, 0],
    );
  });

  test('a month with more refunded than paid shows zero, not negative', () {
    final d = DashboardService.compute(
      today: today,
      startMonth: 7,
      students: const [],
      rooms: const [],
      invoices: const [],
      payments: const [],
      refunds: refunds,
      allocations: const [],
    );
    expect(d.paymentsPerMonth[4].amount, 0);
    expect(d.receivedThisMonth, -5000, reason: 'the tile shows the net');
  });

  test('whole rupees and short chart amounts', () {
    expect(Money.formatWhole(268500.4), '₹2,68,500');
    expect(Money.compact(850), '₹850');
    expect(Money.compact(45000), '₹45K');
    expect(Money.compact(120000), '₹1.2L');
    expect(Money.compact(25000000), '₹2.5Cr');
  });

  testWidgets('dashboard screen: tiles, chart and lists', (tester) async {
    StudentRepository.useInstance(FixedStudents());
    RoomRepository.useInstance(FixedRooms());
    BillingRepository.useInstance(FixedBilling());
    AllocationRepository.useInstance(FixedAllocations());
    addTearDown(() {
      StudentRepository.useInstance(null);
      RoomRepository.useInstance(null);
      BillingRepository.useInstance(null);
      AllocationRepository.useInstance(null);
    });
    tester.view.physicalSize = const Size(1080, 5400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardScreen(
          hostel: const Hostel(hostelId: 1, hostelName: 'Boys Hostel'),
          today: today,
        ),
      ),
    );
    await tester.pumpAndSettle();

    String value(String tile) =>
        tester.widget<Text>(find.byKey(Key('tileValue_$tile'))).data!;
    String note(String tile) =>
        tester.widget<Text>(find.byKey(Key('tileNote_$tile'))).data!;
    expect(value('Students'), '3');
    expect(note('Students'), 'active, 1 left');
    expect(value('Beds occupied'), '3 / 5');
    expect(note('Beds occupied'), '2 free');
    expect(value('Fees'), '₹2,10,000');
    expect(note('Fees'), 'for 2026-2027');
    expect(value('Received'), '₹15,000');
    expect(note('Received'), 'in November 2026');
    expect(value('Year to date'), '₹1,05,000');
    expect(note('Year to date'), 'received since 1 Jul');
    expect(value('Pending'), '₹1,10,000');
    expect(note('Pending'), '2 students');

    // Tap the August bar for its exact amount; tap again to clear.
    await tester.tap(find.byKey(const Key('bar_1')));
    await tester.pump();
    expect(find.text('Aug 2026: ₹30,000.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bar_1')));
    await tester.pump();
    expect(find.text('Tap a bar to see the amount.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chartTable')));
    await tester.pump();
    expect(find.text('Jul 2026'), findsOneWidget);
    expect(find.text('₹60,000.00'), findsOneWidget);

    expect(find.text('Highest pending fees'), findsOneWidget);
    expect(find.text('₹70,000'), findsOneWidget);
    expect(find.text('02 Nov   Ravi'), findsOneWidget);
    expect(find.text('01 Aug   Amit'), findsOneWidget);
  });
}
