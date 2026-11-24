import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/college_repository.dart';
import 'package:hostel_mobile_app/data/room_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/college.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/payment.dart';
import 'package:hostel_mobile_app/models/report_table.dart';
import 'package:hostel_mobile_app/models/room.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/reports_screen.dart';
import 'package:hostel_mobile_app/services/report_export.dart';
import 'package:hostel_mobile_app/services/report_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

final today = DateTime(2026, 11, 24);
final now = DateTime(2026, 11, 24, 10, 30);
const hostel = Hostel(hostelId: 1, hostelName: 'Shri Balaji Hostel');

Student st(
  int id,
  String name, {
  int? college,
  String? collegeName,
  String? room,
  String status = StudentStatus.active,
  String? father,
  String? fatherMobile,
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: 'Male',
  admissionDate: DateTime(2025, 7, 1),
  collegeId: college,
  collegeName: collegeName,
  roomNumber: room,
  status: status,
  fatherName: father,
  fatherMobile: fatherMobile,
);

Invoice inv(
  int id,
  int student,
  String name,
  int year,
  double fee,
  double paid,
) => Invoice(
  invoiceId: id,
  invoiceNumber: 'SBH/$year-${year + 1}/000$id',
  studentId: student,
  studentName: name,
  academicYear: year,
  roomRent: fee,
  transportAmount: 0,
  receivedAmount: paid,
);

Payment pay(int id, DateTime date, double amount, String method, String name) =>
    Payment(
      paymentId: id,
      receiptNumber: 'SBH/R/2026-2027/000$id',
      studentId: 1,
      invoiceId: 1,
      paymentDate: date,
      amount: amount,
      paymentMethod: method,
      studentName: name,
      invoiceNumber: 'SBH/2026-2027/0001',
    );

Room room(
  int id,
  String number,
  int capacity,
  int occupied, {
  bool active = true,
}) => Room(
  roomId: id,
  hostelId: 1,
  roomNumber: number,
  sharingTypeId: 1,
  gender: 'Male',
  sharingName: '$capacity Sharing',
  capacity: capacity,
  occupied: occupied,
  isActive: active,
);

RoomAllocation alloc(int id, int student, String name, int roomId) =>
    RoomAllocation(
      allocationId: id,
      studentId: student,
      studentName: name,
      roomId: roomId,
      roomNumber: '$roomId',
      hostelId: 1,
      checkInDate: DateTime(2026, 7, 1),
      status: AllocationStatus.current,
    );

final colleges = [
  const College(collegeId: 1, hostelId: 1, collegeName: 'Govt College'),
  const College(collegeId: 2, hostelId: 1, collegeName: 'DAV College'),
];
final students = [
  st(
    1,
    'Ravi',
    college: 1,
    collegeName: 'Govt College',
    room: '10',
    father: 'Rakesh',
    fatherMobile: '9811122233',
  ),
  st(2, 'amit', college: 2, collegeName: 'DAV College', room: '2'),
  st(
    3,
    'Karan',
    college: 1,
    collegeName: 'Govt College',
    status: StudentStatus.left,
  ),
];
final rooms = [
  room(1, '10', 3, 1),
  room(2, '2', 2, 1),
  room(3, '1A', 2, 0, active: false),
];
final allocations = [alloc(1, 1, 'Ravi', 1), alloc(2, 2, 'amit', 2)];
final invoices = [
  inv(1, 1, 'Ravi', 2026, 80000, 50000), // 30000 pending
  inv(2, 1, 'Ravi', 2025, 75000, 65000), // 10000 pending
  inv(3, 2, 'amit', 2026, 70000, 70000), // paid
  inv(4, 3, 'Karan', 2025, 20000, 0), // 20000 pending, left
];
final payments = [
  pay(1, DateTime(2026, 11, 2), 20000, PaymentMethod.cash, 'Ravi'),
  pay(2, DateTime(2026, 11, 2), 30000, PaymentMethod.upi, 'amit'),
  pay(3, DateTime(2026, 11, 20), 40000, PaymentMethod.upi, 'amit'),
  pay(4, DateTime(2026, 10, 30), 5000, PaymentMethod.cash, 'Ravi'),
];

final data = ReportData(
  students: students,
  colleges: colleges,
  rooms: rooms,
  allocations: allocations,
  payments: payments,
  invoices: invoices,
  startMonth: 7,
);

List<String> col(ReportTable t, int i) => [
  for (final r in t.rows) ReportService.format(r.values[i]),
];

class FixedStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

class FixedColleges extends CollegeRepository {
  @override
  Future<List<College>> getForHostel(int hostelId) async => colleges;
}

class FixedRooms extends RoomRepository {
  @override
  Future<List<Room>> getForHostel(int hostelId) async => rooms;
}

class FixedAllocations extends AllocationRepository {
  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => allocations;
}

class FixedBilling extends BillingRepository {
  FixedBilling({this.fail = false});
  final bool fail;
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<List<Payment>> getPayments(int hostelId) async {
    if (fail) throw Exception('offline');
    return payments;
  }

  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

void main() {
  group('reports', () {
    test('student list: active students by name, then a count', () {
      final t = ReportService.studentList(
        hostel,
        data,
        now,
        status: StudentStatus.active,
      );
      expect(t.title, 'Student List');
      expect(t.subtitles, [
        'Shri Balaji Hostel',
        'Active students',
        'Printed on 24 Nov 2026 10:30',
      ]);
      expect(col(t, 0), ['amit', 'Ravi', '2 students']);
      expect(t.rows.last.style, ReportRowStyle.total);
      expect(t.fileName, 'Students_Shri-Balaji-Hostel_2026-11-24');

      final govt = ReportService.studentList(hostel, data, now, collegeId: 1);
      expect(govt.subtitles[1], 'All students, Govt College');
      expect(col(govt, 0), ['Karan', 'Ravi', '2 students']);
    });

    test('room occupancy: natural room order, beds of active rooms', () {
      final t = ReportService.roomOccupancy(hostel, data, now);
      expect(col(t, 0), ['1A', '2', '10', '3 rooms']);
      expect(col(t, 7), ['', 'amit', 'Ravi', '']);
      // Beds count active rooms only; free beds of an inactive room are 0.
      expect(t.rows.last.values.sublist(4, 7), [5, 2, 3]);
    });

    test('payments: day totals, method totals and the total', () {
      final t = ReportService.paymentsReceived(
        hostel,
        data,
        now,
        DateTime(2026, 11, 1),
        today,
      );
      expect(t.subtitles[1], '01 Nov 2026 to 24 Nov 2026, all payment methods');
      expect(col(t, 1), [
        'SBH/R/2026-2027/0001',
        'SBH/R/2026-2027/0002',
        'Total for 02 Nov 2026 (2 payments)',
        'SBH/R/2026-2027/0003',
        'Total for 20 Nov 2026 (1 payment)',
        'Cash total (1 payment)',
        'UPI total (2 payments)',
        'Total received (3 payments)',
      ]);
      expect(t.rows.last.values.last, 90000.0);
      expect(ReportService.format(t.rows.last.values.last), '₹90,000.00');
      expect(
        t.fileName,
        'Payments_Shri-Balaji-Hostel_2026-11-01_to_2026-11-24',
      );

      final upi = ReportService.paymentsReceived(
        hostel,
        data,
        now,
        DateTime(2026, 11, 1),
        today,
        method: PaymentMethod.upi,
      );
      expect(upi.rows.last.values.last, 70000.0);
      expect(upi.subtitles[1], '01 Nov 2026 to 24 Nov 2026, UPI');
    });

    test('payments: From after To is refused with the desktop message', () {
      expect(
        () => ReportService.paymentsReceived(
          hostel,
          data,
          now,
          today,
          DateTime(2026, 11, 1),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'The From date must be on or before the To date.',
          ),
        ),
      );
    });

    test('fees: one academic year or all, with totals', () {
      final t = ReportService.invoices(hostel, data, now, year: 2026);
      expect(t.subtitles[1], 'Academic year 2026-2027, all invoices');
      expect(col(t, 2).take(2), ['amit', 'Ravi']);
      expect(col(t, 0).last, '2 invoices');
      expect(t.rows.last.values[7], 30000.0);
      expect(t.fileName, 'Fees_Shri-Balaji-Hostel_2026-2027');

      final unpaid = ReportService.invoices(
        hostel,
        data,
        now,
        status: InvoiceStatus.unpaid,
      );
      expect(unpaid.subtitles[1], 'All academic years, unpaid');
      expect(col(unpaid, 2), ['Karan', '']);
    });

    test('pending fees: a line per student, then the invoices', () {
      final t = ReportService.pendingDues(hostel, data, now);
      expect(col(t, 0), [
        'Ravi',
        '    SBH/2025-2026/0002',
        '    SBH/2026-2027/0001',
        'Karan (left)',
        '    SBH/2025-2026/0004',
        '2 students',
      ]);
      expect(t.rows.first.style, ReportRowStyle.group);
      expect(t.rows.last.values.last, 60000.0);
    });

    test('PDF shows Rs., CSV has plain amounts', () async {
      expect(ReportService.format(1234567.5, pdf: true), 'Rs. 12,34,567.50');
      final t = ReportService.paymentsReceived(
        hostel,
        data,
        now,
        DateTime(2026, 11, 1),
        today,
      );
      final csv = ReportExport.csv(t);
      final lines = csv.split('\r\n');
      expect(lines.first, 'Payments Received');
      expect(lines[4], '');
      expect(
        lines[5],
        'Date,Receipt no.,Student,Invoice no.,Paid by,Reference,Amount',
      );
      expect(
        lines[6],
        '02 Nov 2026,SBH/R/2026-2027/0001,Ravi,SBH/2026-2027/0001,Cash,,20000.00',
      );
      expect(csv, contains(',Total received (3 payments),,,,,90000.00\r\n'));
      final pdf = await ReportExport.pdf(t);
      expect(utf8.decode(pdf.sublist(0, 4), allowMalformed: true), '%PDF');
    });
  });

  group('screen', () {
    late List<String> shared;

    setUp(() {
      StudentRepository.useInstance(FixedStudents());
      CollegeRepository.useInstance(FixedColleges());
      RoomRepository.useInstance(FixedRooms());
      AllocationRepository.useInstance(FixedAllocations());
      BillingRepository.useInstance(FixedBilling());
      shared = [];
      Future<void> keep(Uint8List bytes, String name) async =>
          shared.add('$name ${bytes.length > 3}');
      ReportExport.useForTests(sharePdf: keep, shareCsv: keep);
    });

    tearDown(() {
      StudentRepository.useInstance(null);
      CollegeRepository.useInstance(null);
      RoomRepository.useInstance(null);
      AllocationRepository.useInstance(null);
      BillingRepository.useInstance(null);
      ReportExport.useForTests();
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ReportsScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the active students, as the desktop', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('reportTitle')), findsOneWidget);
      expect(find.text('Student List'), findsOneWidget);
      expect(find.text('Active students'), findsOneWidget);
      expect(find.text('2 students'), findsOneWidget);
      expect(find.text('Karan'), findsNothing);
    });

    testWidgets('payments default to this month; fees to this year', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('report_payments')));
      await tester.pumpAndSettle();
      expect(
        find.text('01 Nov 2026 to 24 Nov 2026, all payment methods'),
        findsOneWidget,
      );
      expect(find.text('Total received (3 payments)'), findsOneWidget);
      expect(find.text('₹90,000.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report_fees')));
      await tester.pumpAndSettle();
      expect(
        find.text('Academic year 2026-2027, all invoices'),
        findsOneWidget,
      );
      expect(find.text('2 invoices'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report_pending')));
      await tester.pumpAndSettle();
      expect(find.text('Karan (left)'), findsOneWidget);
    });

    testWidgets('shares the shown report as PDF and as Excel', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('report_rooms')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sharePdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shareExcel')));
      await tester.pumpAndSettle();
      expect(shared, [
        'Rooms_Shri-Balaji-Hostel_2026-11-24.pdf true',
        'Rooms_Shri-Balaji-Hostel_2026-11-24.csv true',
      ]);
    });

    testWidgets('a load error is shown', (tester) async {
      BillingRepository.useInstance(FixedBilling(fail: true));
      await open(tester);
      expect(find.byKey(const Key('reportsError')), findsOneWidget);
    });
  });
}
