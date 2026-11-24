import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/room_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/room.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/allocations_screen.dart';
import 'package:hostel_mobile_app/services/allocation_service.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/money.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

const hostel = Hostel(hostelId: 1, hostelName: 'Boys Hostel');
final today = DateTime(2026, 11, 24);
final july = DateTime(2026, 7, 1);

Room room(
  int id,
  String number,
  String gender, {
  int capacity = 2,
  int occupied = 0,
  bool active = true,
}) => Room(
  roomId: id,
  hostelId: 1,
  roomNumber: number,
  sharingTypeId: capacity,
  gender: gender,
  isActive: active,
  sharingName: const {1: 'Single', 2: 'Double', 3: 'Triple'}[capacity]!,
  capacity: capacity,
  occupied: occupied,
);

Student student(
  int id,
  String name,
  String gender, {
  String status = StudentStatus.active,
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: gender,
  admissionDate: july,
  status: status,
);

RoomAllocation alloc(
  int id,
  int studentId,
  String name,
  int roomId,
  String roomNumber,
  int bed, {
  DateTime? checkIn,
  DateTime? checkOut,
  String status = 'Current',
}) => RoomAllocation(
  allocationId: id,
  studentId: studentId,
  studentName: name,
  roomId: roomId,
  roomNumber: roomNumber,
  hostelId: 1,
  bedNumber: bed,
  checkInDate: checkIn ?? DateTime(2026, 7, 5),
  checkOutDate: checkOut,
  status: status,
);

// Rooms: 10 (boys, Double, bed 1 used), 2 (boys, Single, full),
// 101 (girls, Double, empty), 9 (boys, inactive).
final rooms = [
  room(1, '10', RoomGender.male, occupied: 1),
  room(2, '2', RoomGender.male, capacity: 1, occupied: 1),
  room(3, '101', RoomGender.female),
  room(4, '9', RoomGender.male, active: false),
];
final students = [
  student(1, 'Ravi', 'Male'),
  student(2, 'Amit', 'Male'),
  student(3, 'Neha', 'Female'),
  student(4, 'Sam', 'Other'),
  student(5, 'Gone', 'Male', status: StudentStatus.left),
  student(6, 'Karan', 'Male'),
];
final current = [
  alloc(1, 1, 'Ravi', 1, '10', 1),
  alloc(2, 2, 'Amit', 2, '2', 1),
];
final history = [
  ...current,
  alloc(
    3,
    5,
    'Gone',
    3,
    '101',
    1,
    checkIn: DateTime(2026, 7, 2),
    checkOut: DateTime(2026, 8, 1),
    status: AllocationStatus.checkedOut,
  ),
];

class FixedRooms extends RoomRepository {
  @override
  Future<List<Room>> getForHostel(int hostelId) async => rooms;
}

class FixedStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

/// Records the calls; the database rules are tested in PostgreSQL.
class FakeAllocations extends AllocationRepository {
  FakeAllocations({this.invoices = const {}});

  /// Invoices by student.
  final Map<int, List<Invoice>> invoices;
  final calls = <Map<String, Object?>>[];

  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => includeHistory ? history : current;

  @override
  Future<List<Invoice>> getInvoicesForStudent(int studentId) async =>
      invoices[studentId] ?? const [];

  @override
  Future<int> getAcademicYearStartMonth() async => 7;

  @override
  Future<void> checkIn({
    required int studentId,
    required int roomId,
    required String date,
    required String remarks,
    int? bed,
    double? roomRent,
    double? transport,
  }) async => calls.add({
    'call': 'checkIn',
    'student': studentId,
    'room': roomId,
    'date': date,
    'remarks': remarks,
    'bed': bed,
    'rent': roomRent,
    'transport': transport,
  });

  @override
  Future<void> transfer({
    required int studentId,
    required int newRoomId,
    required String date,
    required String remarks,
    int? bed,
  }) async => calls.add({
    'call': 'transfer',
    'student': studentId,
    'room': newRoomId,
    'date': date,
    'bed': bed,
  });

  @override
  Future<void> checkOut({
    required int studentId,
    required String date,
    required String remarks,
    required bool waive,
  }) async => calls.add({
    'call': 'checkOut',
    'student': studentId,
    'date': date,
    'remarks': remarks,
    'waive': waive,
  });
}

/// A check-in that really puts the student in the room.
class _CheckInAdds extends FakeAllocations {
  _CheckInAdds(this.inner, this.added);

  final FakeAllocations inner;
  final List<RoomAllocation> added;

  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => [
    ...await inner.getForHostel(hostelId, includeHistory: includeHistory),
    ...added,
  ];

  @override
  Future<List<Invoice>> getInvoicesForStudent(int studentId) =>
      inner.getInvoicesForStudent(studentId);

  @override
  Future<void> checkIn({
    required int studentId,
    required int roomId,
    required String date,
    required String remarks,
    int? bed,
    double? roomRent,
    double? transport,
  }) async {
    added.add(alloc(50, studentId, 'Karan', roomId, '10', bed ?? 2));
    await inner.checkIn(
      studentId: studentId,
      roomId: roomId,
      date: date,
      remarks: remarks,
      bed: bed,
      roomRent: roomRent,
      transport: transport,
    );
  }
}

Invoice invoice(int student, int year, double rent, double paid) => Invoice(
  invoiceId: student * 10 + year % 10,
  invoiceNumber: 'SBH/$year-${year + 1}/000$student',
  studentId: student,
  academicYear: year,
  roomRent: rent,
  transportAmount: 0,
  receivedAmount: paid,
);

void main() {
  late FakeAllocations db;

  setUp(() {
    db = FakeAllocations(
      invoices: {
        // Ravi: 2026-2027 fee with ₹30,000 pending.
        1: [invoice(1, 2026, 80000, 50000)],
        // Karan: only last year's fee.
        6: [invoice(6, 2025, 70000, 70000)],
      },
    );
    AllocationRepository.useInstance(db);
    RoomRepository.useInstance(FixedRooms());
    StudentRepository.useInstance(FixedStudents());
    AuthService.useAuth(MockFirebaseAuth(signedIn: true));
  });
  tearDown(() {
    AllocationRepository.useInstance(null);
    RoomRepository.useInstance(null);
    StudentRepository.useInstance(null);
    AuthService.useAuth(null);
  });

  group('rules', () {
    test('money in rupees with Indian grouping', () {
      expect(Money.format(4500), '₹4,500.00');
      expect(Money.format(268500), '₹2,68,500.00');
      expect(Money.format(10000000), '₹1,00,00,000.00');
      expect(Money.format(80000.5), '₹80,000.50');
      expect(Money.format(999), '₹999.00');
      expect(Money.tryParse('₹4,500'), 4500);
      expect(Money.tryParse('85000.50'), 85000.5);
      expect(Money.tryParse('abc'), isNull);
    });

    test('academic year: July to June', () {
      expect(AcademicYear.of(DateTime(2026, 7, 1), 7), 2026);
      expect(AcademicYear.of(DateTime(2027, 6, 30), 7), 2026);
      expect(AcademicYear.label(2026, 7), '2026-2027');
      expect(AcademicYear.label(2026, 1), '2026');
    });

    test('students without a room, rooms for a gender, free beds', () {
      expect(
        [
          for (final s in AllocationService.studentsWithoutRoom(
            students,
            current,
          ))
            s.studentName,
        ],
        ['Karan', 'Neha', 'Sam'],
      );
      expect(
        [
          for (final r in AllocationService.roomsFor(rooms, 'Male'))
            r.roomNumber,
        ],
        ['10'],
      );
      expect(AllocationService.freeBeds(rooms[0], current), [2]);
      expect(AllocationService.freeBeds(rooms[2], current), [1, 2]);
    });

    test('explains why there is no room', () {
      final allFull = [
        room(1, '10', RoomGender.male, occupied: 2),
        room(3, '101', RoomGender.female, occupied: 1),
        room(4, '9', RoomGender.male, active: false),
      ];
      expect(
        AllocationService.explainNoRoom(allFull, students[5]),
        "There is no free bed in a room for boys: Karan is saved as Male. "
        "Free beds in girls' rooms: 101 (1). Switched off: 9. If a gender "
        'is wrong, correct it on the Students screen (student) or the '
        'Rooms screen (room).',
      );
    });

    test('reads the fee as the desktop does', () {
      Matcher message(String m) => throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', m),
      );
      expect(
        () => AllocationService.readFee('', ''),
        message(
          'Please enter the room rent for the year agreed with the student.',
        ),
      );
      expect(
        () => AllocationService.readFee('0', ''),
        message(
          'Please enter the room rent for the year agreed with the student.',
        ),
      );
      expect(
        () => AllocationService.readFee('5000', 'x'),
        message(
          'Please enter the transport amount for the year, or leave it empty.',
        ),
      );
      expect(
        () => AllocationService.readFee('100.555', ''),
        message('The room rent can have at most two decimal places (paise).'),
      );
      expect(
        () => AllocationService.readFee('20000000', ''),
        message('The room rent cannot be more than ₹1,00,00,000.00.'),
      );
      final fee = AllocationService.readFee('₹85,000', '12000');
      expect(fee.total, 97000);
      expect(AllocationService.readFee('85000', ' ').transport, 0);
    });
  });

  group('Room Allocation screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AllocationsScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String key, String option) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('saveAllocation')));
      await tester.pumpAndSettle();
    }

    testWidgets('lists students in rooms, by room number', (tester) async {
      await open(tester);
      expect(find.text('2 students in rooms now'), findsOneWidget);
      final y2 = tester.getTopLeft(find.byKey(const Key('alloc_2'))).dy;
      final y10 = tester.getTopLeft(find.byKey(const Key('alloc_1'))).dy;
      expect(y2 < y10, isTrue, reason: 'room 2 before room 10');
      expect(find.text('Since 05 Jul 2026  ·  142 days'), findsNWidgets(2));
      expect(find.text('Bed 1'), findsNWidgets(2));
    });

    testWidgets('search and full history', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('allocSearch')), 'ami');
      await tester.pump();
      expect(find.text('Amit'), findsOneWidget);
      expect(find.text('Ravi'), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.tap(find.text('Full history'));
      await tester.pumpAndSettle();
      expect(
        find.text('02 Jul 2026 to 01 Aug 2026  ·  Checked out'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('allocMenu_3')),
        findsNothing,
        reason: 'no Transfer or Check-out on history',
      );
    });

    testWidgets('check-in with the yearly fee', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('checkIn')));
      await tester.pumpAndSettle();

      // Only active students without a room are offered.
      await tester.tap(find.byKey(const Key('allocStudent')));
      await tester.pumpAndSettle();
      expect(find.text('Gone'), findsNothing);
      expect(find.text('Ravi'), findsNothing);
      await tester.tap(find.text('Karan').last);
      await tester.pumpAndSettle();

      // Only boys' rooms with a free bed; the lowest free bed is chosen.
      await tester.tap(find.byKey(const ValueKey('allocRoom_6')));
      await tester.pumpAndSettle();
      expect(find.text('101 (Double, 2 free beds)'), findsNothing);
      expect(find.text('2 (Single, 0 free beds)'), findsNothing);
      await tester.tap(find.text('10 (Double, 1 free bed)').last);
      await tester.pumpAndSettle();
      expect(find.text('Bed 2'), findsOneWidget);

      // Karan has last year's fee only, so this year's fee is asked.
      expect(find.text('FEE FOR 2026-2027'), findsOneWidget);
      await save(tester);
      expect(
        find.text(
          'Please enter the room rent for the year agreed with the '
          'student.',
        ),
        findsOneWidget,
      );
      expect(db.calls, isEmpty);

      await tester.enterText(find.byKey(const Key('allocRent')), '85,000');
      await tester.enterText(find.byKey(const Key('allocTransport')), '12000');
      await tester.pump();
      expect(find.text('Total fee: ₹97,000.00 for 2026-2027'), findsOneWidget);
      await save(tester);

      expect(db.calls.single, {
        'call': 'checkIn',
        'student': 6,
        'room': 1,
        'date': '2026-11-24',
        'remarks': '',
        'bed': 2,
        'rent': 85000.0,
        'transport': 12000.0,
      });
      expect(find.text('Karan is in room 10, bed 2.'), findsOneWidget);
    });

    testWidgets('after a check-in the agreement PDF is offered', (
      tester,
    ) async {
      // After the check-in Karan is in room 10, bed 2.
      final after = <RoomAllocation>[];
      final adding = _CheckInAdds(db, after);
      AllocationRepository.useInstance(adding);
      await open(tester);
      await tester.tap(find.byKey(const Key('checkIn')));
      await tester.pumpAndSettle();
      await choose(tester, 'allocStudent', 'Karan');
      await tester.tap(find.byKey(const ValueKey('allocRoom_6')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 (Double, 1 free bed)').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('allocRent')), '85,000');
      await save(tester);
      expect(find.text('Karan is in room 10, bed 2.'), findsOneWidget);
      expect(
        find.textContaining('Create the residency agreement PDF now?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('makeAgreement')), findsNothing);
    });

    testWidgets('no room for the gender: the reason is shown', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('checkIn')));
      await tester.pumpAndSettle();
      await choose(tester, 'allocStudent', 'Sam');
      expect(
        find.text("Set Sam's gender on the Students screen first."),
        findsOneWidget,
      );
    });

    testWidgets('transfer: no other room for Ravi', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('allocMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      expect(find.text('10, bed 1'), findsOneWidget);
      // Room 10 itself is not offered and room 2 is full.
      await save(tester);
      expect(find.text('Please select the room.'), findsOneWidget);
      expect(db.calls, isEmpty);
    });

    testWidgets('transfer asks first, then moves', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('allocMenu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      expect(find.text('2, bed 1'), findsOneWidget);
      await choose(tester, 'allocRoom_2', '10 (Double, 1 free bed)');
      expect(find.text('Bed 2'), findsOneWidget);
      await save(tester);
      expect(
        find.text('Move Amit from room 2 to room 10 on 24 Nov 2026?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmAllocation')));
      await tester.pumpAndSettle();
      expect(db.calls.single, {
        'call': 'transfer',
        'student': 2,
        'room': 1,
        'date': '2026-11-24',
        'bed': 2,
      });
      expect(find.text('Amit moved to room 10.'), findsOneWidget);
    });

    testWidgets('check-out keeps or waives the pending fee', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('allocMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check-out'));
      await tester.pumpAndSettle();
      expect(find.text('₹30,000.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('waivePending')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('allocRemarks')),
        'Course over',
      );
      await save(tester);
      expect(
        find.text(
          "Check out Ravi from room 10 on 24 Nov 2026? The student's "
          'status will be set to Left. The pending fee will be waived.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmAllocation')));
      await tester.pumpAndSettle();

      expect(db.calls.single, {
        'call': 'checkOut',
        'student': 1,
        'date': '2026-11-24',
        'remarks': 'Course over',
        'waive': true,
      });
      expect(find.text('Ravi checked out.'), findsOneWidget);
    });

    testWidgets('a student with no pending fee: no fee question at check-out', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('allocMenu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check-out'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('allocPending')), findsNothing);
      expect(find.byKey(const Key('waivePending')), findsNothing);
    });
  });
}
