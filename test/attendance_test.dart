import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/attendance_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/attendance.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/attendance_screen.dart';
import 'package:hostel_mobile_app/services/attendance_service.dart';
import 'package:hostel_mobile_app/services/launcher.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

final today = DateTime(2026, 11, 24);
const hostel = Hostel(
  hostelId: 1,
  hostelName: 'Boys Hostel',
  phone: '0135 2345678',
);

Student st(
  int id,
  String name, {
  String? mother,
  String? motherMobile,
  String? father,
  String? fatherMobile,
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: 'Male',
  admissionDate: DateTime(2026, 7, 1),
  motherName: mother,
  motherMobile: motherMobile,
  fatherName: father,
  fatherMobile: fatherMobile,
);

RoomAllocation al(
  int id,
  int student,
  String room,
  int bed,
  DateTime inDate, {
  DateTime? outDate,
  String status = AllocationStatus.current,
}) => RoomAllocation(
  allocationId: id,
  studentId: student,
  studentName: '',
  roomId: 1,
  roomNumber: room,
  hostelId: 1,
  bedNumber: bed,
  checkInDate: inDate,
  checkOutDate: outDate,
  status: status,
);

final students = [
  st(1, 'Ravi', mother: 'Sunita', motherMobile: '98765 43210'),
  st(2, 'Amit', father: 'Raj', fatherMobile: '+91 98111 22233'),
  st(3, 'Karan', motherMobile: '12345'), // no usable mobile
  st(4, 'Vikas', mother: 'Asha', motherMobile: '09876543210'),
];
final allocations = [
  al(1, 1, '10', 1, DateTime(2026, 7, 5)),
  al(2, 2, '2', 1, DateTime(2026, 7, 5)),
  // Karan moved from 10 to 101 on 20 Nov.
  al(
    3,
    3,
    '10',
    2,
    DateTime(2026, 7, 5),
    outDate: DateTime(2026, 11, 20),
    status: AllocationStatus.transferred,
  ),
  al(4, 3, '101', 1, DateTime(2026, 11, 20)),
  // Vikas checked out on 24 Nov: not on that night's sheet.
  al(
    5,
    4,
    '2',
    2,
    DateTime(2026, 7, 5),
    outDate: DateTime(2026, 11, 24),
    status: AllocationStatus.checkedOut,
  ),
];

class FixedStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

class FixedAllocations extends AllocationRepository {
  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => allocations;
}

class FakeAttendance extends AttendanceRepository {
  final saved = <String, List<SavedAttendance>>{};
  final messaged = <String, Set<int>>{};
  final calls = <Map<String, Object?>>[];

  @override
  Future<List<SavedAttendance>> getForDate(int hostelId, String date) async =>
      saved[date] ?? const [];

  @override
  Future<Set<int>> getMessaged(int hostelId, String subject) async =>
      messaged[subject] ?? {};

  @override
  Future<int> save(
    int hostelId,
    String date,
    List<AttendanceEntry> entries,
  ) async {
    calls.add({
      'call': 'save',
      'date': date,
      'entries': [
        for (final e in entries) (e.studentId, e.isPresent, e.remarks),
      ],
    });
    saved[date] = [
      for (final e in entries)
        SavedAttendance(e.studentId, e.isPresent, e.remarks),
    ];
    return entries.where((e) => !e.isPresent).length;
  }

  @override
  Future<void> logAbsenceMessage(
    int studentId,
    String mobile,
    String date,
  ) async {
    calls.add({
      'call': 'log',
      'student': studentId,
      'mobile': mobile,
      'date': date,
    });
  }
}

void main() {
  group('rules', () {
    test('who is on the night\'s sheet, in room order', () {
      List<String> names(DateTime d) => [
        for (final e in AttendanceService.buildSheet(
          date: d,
          students: students,
          allocations: allocations,
          saved: const [],
          messaged: const {},
        ))
          '${e.roomAndBed} ${e.studentName}',
      ];
      // 24 Nov: Karan in his new room; Vikas checked out that day.
      expect(names(today), [
        '2, bed 1 Amit',
        '10, bed 1 Ravi',
        '101, bed 1 Karan',
      ]);
      // 19 Nov: Karan still in 10; Vikas still in.
      expect(names(DateTime(2026, 11, 19)), [
        '2, bed 1 Amit',
        '2, bed 2 Vikas',
        '10, bed 1 Ravi',
        '10, bed 2 Karan',
      ]);
      expect(names(DateTime(2026, 7, 4)), isEmpty);
    });

    test('saved records and status', () {
      final sheet = AttendanceService.buildSheet(
        date: today,
        students: students,
        allocations: allocations,
        saved: const [SavedAttendance(1, false, 'Home')],
        messaged: const {1},
      );
      final ravi = sheet.firstWhere((e) => e.studentId == 1);
      expect(ravi.isPresent, isFalse);
      expect(ravi.remarks, 'Home');
      expect(ravi.messaged, isTrue);
      expect(
        AttendanceService.status(sheet, dirty: false),
        'Saved: 2 present, 1 absent',
      );
      expect(
        AttendanceService.status(sheet, dirty: true),
        'Not saved yet: 2 present, 1 absent',
      );
    });

    test('WhatsApp numbers as on the desktop', () {
      expect(AttendanceService.toWhatsAppNumber('98765 43210'), '919876543210');
      expect(AttendanceService.toWhatsAppNumber('09876543210'), '919876543210');
      expect(
        AttendanceService.toWhatsAppNumber('+91 98765-43210'),
        '919876543210',
      );
      expect(AttendanceService.toWhatsAppNumber('12345'), isNull);
      expect(
        AttendanceService.toWhatsAppNumber('0135 2345678'),
        isNull,
        reason: 'a landline',
      );
      expect(
        AttendanceService.toWhatsAppNumber('+44 7700 900123'),
        '447700900123',
      );
    });

    test('the mother first, else the father', () {
      expect(AttendanceService.recipient(students[0]), (
        'Sunita',
        '919876543210',
        'Mother',
      ));
      expect(AttendanceService.recipient(students[1]), (
        'Raj',
        '919811122233',
        'Father',
      ));
      expect(AttendanceService.recipient(students[2]), isNull);
    });

    test('the desktop message and the WhatsApp link', () {
      final text = AttendanceService.message(
        parentName: 'Sunita',
        studentName: 'Ravi',
        hostelName: 'Boys Hostel',
        date: today,
        hostelPhone: '0135 2345678',
      );
      expect(
        text,
        'Dear Sunita,\nThis is to inform you that Ravi was absent from Boys '
        'Hostel on 24 Nov 2026.\nFor any question, please call 0135 2345678. '
        'Thank you.',
      );
      final link = AttendanceService.whatsAppLink('919876543210', text);
      expect(link.host, 'wa.me');
      expect(link.path, '/919876543210');
      expect(link.queryParameters['text'], text);
      expect(AttendanceService.historySubject(today), 'attendance 24 Nov 2026');
    });
  });

  group('Attendance screen', () {
    late FakeAttendance db;
    late List<Uri> opened;

    setUp(() {
      db = FakeAttendance();
      opened = [];
      StudentRepository.useInstance(FixedStudents());
      AllocationRepository.useInstance(FixedAllocations());
      AttendanceRepository.useInstance(db);
      Launcher.useForTests((uri) async {
        opened.add(uri);
        return true;
      });
    });
    tearDown(() {
      StudentRepository.useInstance(null);
      AllocationRepository.useInstance(null);
      AttendanceRepository.useInstance(null);
      Launcher.useForTests(null);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SizedBox()),
          routes: {
            '/att': (_) => AttendanceScreen(hostel: hostel, today: today),
          },
        ),
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/att');
      await tester.pumpAndSettle();
    }

    testWidgets('mark absent, save, then WhatsApp the parent', (tester) async {
      await open(tester);
      expect(find.text('24 Nov 2026'), findsOneWidget);
      expect(find.text('Not marked yet: 3 present, 0 absent'), findsOneWidget);
      // The buttons are there straight away, before anything is changed.
      expect(find.byKey(const Key('saveAttendance')), findsOneWidget);
      expect(find.byKey(const Key('allPresent')), findsOneWidget);

      await tester.tap(find.byKey(const Key('present_1')));
      await tester.pump();
      expect(find.text('Not saved yet: 2 present, 1 absent'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('remarks_1')), ' gone home ');
      await tester.tap(find.byKey(const Key('saveAttendance')));
      await tester.pumpAndSettle();

      expect(db.calls.single, {
        'call': 'save',
        'date': '2026-11-24',
        'entries': [(2, true, ''), (1, false, 'gone home'), (3, true, '')],
      });
      expect(find.text('Saved: 2 present, 1 absent'), findsOneWidget);
      expect(find.text('Mother: Sunita, +919876543210'), findsOneWidget);

      await tester.tap(find.byKey(const Key('whatsapp_1')));
      await tester.pumpAndSettle();
      expect(opened.single.path, '/919876543210');
      expect(
        opened.single.queryParameters['text'],
        contains('Ravi was absent from Boys Hostel on 24 Nov 2026'),
      );
      expect(db.calls.last, {
        'call': 'log',
        'student': 1,
        'mobile': '919876543210',
        'date': '2026-11-24',
      });
      expect(find.text('Message sent'), findsOneWidget);

      // A second message asks first.
      await tester.tap(find.byKey(const Key('whatsapp_1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('was already sent a message'), findsOneWidget);
    });

    testWidgets('Mark All Present undoes the absences', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('present_1')));
      await tester.tap(find.byKey(const Key('present_2')));
      await tester.pump();
      expect(find.text('Not saved yet: 1 present, 2 absent'), findsOneWidget);
      await tester.tap(find.byKey(const Key('allPresent')));
      await tester.pump();
      expect(find.text('Not saved yet: 3 present, 0 absent'), findsOneWidget);
    });

    testWidgets('earlier dates, no future dates, unsaved changes asked', (
      tester,
    ) async {
      await open(tester);
      final next = tester.widget<IconButton>(find.byKey(const Key('nextDay')));
      expect(next.onPressed, isNull, reason: 'no future dates');

      await tester.tap(find.byKey(const Key('previousDay')));
      await tester.pumpAndSettle();
      expect(find.text('23 Nov 2026'), findsOneWidget);
      // Vikas was still in on the 23rd.
      expect(find.text('Vikas'), findsOneWidget);

      await tester.tap(find.byKey(const Key('present_4')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('todayButton')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The attendance of 23 Nov 2026 has not been saved. '
          'Discard the changes?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('23 Nov 2026'), findsOneWidget);

      // Back also asks.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Discard the changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discardChanges')));
      await tester.pumpAndSettle();
      expect(find.byType(AttendanceScreen), findsNothing);
    });

    testWidgets('a student whose parents have no mobile', (tester) async {
      db.saved['2026-11-24'] = const [SavedAttendance(3, false, null)];
      await open(tester);
      expect(find.text('Saved: 2 present, 1 absent'), findsOneWidget);
      expect(
        find.text(
          'Neither the mother nor the father has a valid mobile number.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('whatsapp_3')), findsNothing);
    });
  });
}
