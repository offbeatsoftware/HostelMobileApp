import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/college_repository.dart';
import 'package:hostel_mobile_app/data/hostel_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/main.dart';
import 'package:hostel_mobile_app/models/college.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/student_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixedHostels extends HostelRepository {
  @override
  Future<List<Hostel>> getAll() async => const [
    Hostel(hostelId: 1, hostelName: 'Boys Hostel'),
  ];
}

class FixedColleges extends CollegeRepository {
  @override
  Future<List<College>> getForHostel(int hostelId) async => const [
    College(collegeId: 1, hostelId: 1, collegeName: 'DAV College'),
    College(collegeId: 2, hostelId: 1, collegeName: 'Doon University'),
  ];
}

/// An in-memory database with the main rules of
/// supabase/006_student_functions.sql.
class MemoryStudentRepository extends StudentRepository {
  MemoryStudentRepository(List<Student> students, {this.withRecords = const {}})
    : _rows = [...students];

  final List<Student> _rows;

  /// Students with room, invoice or payment records.
  final Set<int> withRecords;
  int _nextId = 100;
  final saved = <Map<String, Object?>>[];

  @override
  Future<List<Student>> getForHostel(int hostelId) async => [..._rows];

  @override
  Future<int> save({
    int? studentId,
    required int hostelId,
    required Map<String, Object?> data,
  }) async {
    saved.add({'id': studentId, ...data});
    final aadhaar = data['aadhaar_number'] as String;
    if (aadhaar.isNotEmpty &&
        _rows.any(
          (s) => s.aadhaarNumber == aadhaar && s.studentId != studentId,
        )) {
      throw const ValidationException(
        'Another student already has this Aadhaar number.',
      );
    }
    final index = _rows.indexWhere((s) => s.studentId == studentId);
    if (index >= 0 &&
        _rows[index].roomNumber != null &&
        data['status'] == StudentStatus.left) {
      final old = _rows[index];
      throw ValidationException(
        '${old.studentName} is in room ${old.roomNumber}. Use Check-out on '
        'the Room Allocation screen; it sets the status to Left.',
      );
    }
    String? text(String k) {
      final v = data[k] as String?;
      return v == null || v.isEmpty ? null : v;
    }

    final id = studentId ?? _nextId++;
    final collegeId = data['college_id'] as int?;
    final student = Student(
      studentId: id,
      hostelId: hostelId,
      studentName: data['student_name'] as String,
      gender: text('gender'),
      mobile: text('mobile'),
      collegeId: collegeId,
      collegeName: collegeId == null
          ? null
          : (collegeId == 1 ? 'DAV College' : 'Doon University'),
      course: text('course'),
      className: text('class_name'),
      fatherName: text('father_name'),
      fatherMobile: text('father_mobile'),
      aadhaarNumber: text('aadhaar_number'),
      admissionDate: DateTime.parse(data['admission_date'] as String),
      status: data['status'] as String,
      roomNumber: index >= 0 ? _rows[index].roomNumber : null,
    );
    if (index >= 0) {
      _rows[index] = student;
    } else {
      _rows.add(student);
    }
    return id;
  }

  @override
  Future<void> delete(int studentId) async {
    final s = _rows.firstWhere((s) => s.studentId == studentId);
    if (withRecords.contains(studentId)) {
      throw ValidationException(
        '${s.studentName} has room, invoice or payment records and cannot '
        'be deleted. Edit the student and set the status to Left instead.',
      );
    }
    _rows.remove(s);
  }

  final purged = <Map<String, Object?>>[];

  @override
  Future<void> deletePermanently(int studentId, String reason) async {
    purged.add({'id': studentId, 'reason': reason});
    _rows.removeWhere((s) => s.studentId == studentId);
  }

  @override
  Future<void> makeActive(int studentId) async {
    final i = _rows.indexWhere((s) => s.studentId == studentId);
    final s = _rows[i];
    _rows[i] = Student(
      studentId: s.studentId,
      hostelId: s.hostelId,
      studentName: s.studentName,
      gender: s.gender,
      admissionDate: s.admissionDate,
      status: StudentStatus.active,
    );
  }
}

final july = DateTime(2026, 7, 1);
final ravi = Student(
  studentId: 1,
  hostelId: 1,
  studentName: 'Ravi Kumar',
  gender: 'Male',
  mobile: '98765 43210',
  collegeId: 1,
  collegeName: 'DAV College',
  course: 'B.Com',
  className: '1st year',
  fatherName: 'Suresh Kumar',
  fatherMobile: '98111 22233',
  aadhaarNumber: '234567890124',
  admissionDate: july,
  roomNumber: '101',
);
final amit = Student(
  studentId: 2,
  hostelId: 1,
  studentName: 'amit Singh',
  gender: 'Male',
  collegeId: 2,
  collegeName: 'Doon University',
  course: 'BCA',
  className: '2nd year',
  motherName: 'Sunita Singh',
  motherMobile: '97000 11122',
  admissionDate: july,
);
final vikas = Student(
  studentId: 3,
  hostelId: 1,
  studentName: 'Vikas Rawat',
  gender: 'Male',
  admissionDate: july,
  status: StudentStatus.left,
);

void main() {
  late MemoryStudentRepository db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HostelRepository.useInstance(FixedHostels());
    CollegeRepository.useInstance(FixedColleges());
    db = MemoryStudentRepository([ravi, amit, vikas], withRecords: {1});
    StudentRepository.useInstance(db);
    AuthService.useAuth(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'a', email: 'a@b.com'),
      ),
    );
  });
  tearDown(() {
    HostelRepository.useInstance(null);
    CollegeRepository.useInstance(null);
    StudentRepository.useInstance(null);
    AuthService.useAuth(null);
  });

  group('rules', () {
    test('Aadhaar: 12 digits, not 0 or 1 first, Verhoeff check digit', () {
      expect(Validators.isValidAadhaarOrEmpty(''), isTrue);
      expect(Validators.isValidAadhaarOrEmpty('234567890124'), isTrue);
      expect(Validators.isValidAadhaarOrEmpty('987654321096'), isTrue);
      expect(
        Validators.isValidAadhaarOrEmpty('234567890125'),
        isFalse,
        reason: 'one wrong digit',
      );
      expect(Validators.isValidAadhaarOrEmpty('134567890124'), isFalse);
      expect(Validators.isValidAadhaarOrEmpty('23456789012'), isFalse);
      expect(Validators.cleanAadhaar(' 2345 6789-0124'), '234567890124');
      expect(ravi.aadhaarMasked, 'XXXX XXXX 0124');
    });

    test('checks the fields in the desktop order', () async {
      final today = DateTime(2026, 11, 24);
      Future<void> expectMessage(StudentInput input, String message) =>
          expectLater(
            StudentService.save(input, today: today),
            throwsA(
              isA<ValidationException>().having(
                (e) => e.message,
                'message',
                message,
              ),
            ),
          );
      StudentInput input({
        String name = 'X',
        String? gender = 'Male',
        String? mobile,
        String? fatherEmail,
        DateTime? birth,
        DateTime? admission,
        String? aadhaar,
      }) => StudentInput(
        hostelId: 1,
        studentName: name,
        gender: gender,
        mobile: mobile,
        fatherEmail: fatherEmail,
        dateOfBirth: birth,
        admissionDate: admission ?? july,
        aadhaarNumber: aadhaar,
      );

      await expectMessage(input(name: ' '), "Please enter the student's name.");
      await expectMessage(input(gender: null), 'Please select the gender.');
      await expectMessage(
        input(mobile: '12'),
        'Please enter a valid mobile number for the student.',
      );
      await expectMessage(
        input(fatherEmail: 'dad@home'),
        'Please enter a valid email address for the father.',
      );
      await expectMessage(
        input(birth: today),
        'The date of birth must be in the past.',
      );
      await expectMessage(
        input(birth: DateTime(2006, 5, 14), admission: DateTime(2006, 5, 14)),
        'The admission date must be after the date of birth.',
      );
      await expectMessage(
        input(aadhaar: '2345 6789 0125'),
        'The Aadhaar number is not valid. It must have 12 digits; please '
        'check it for typing mistakes.',
      );
      expect(db.saved, isEmpty);
    });

    test('search, filters and sorting by name', () {
      List<String> names(List<Student> s) => [for (final x in s) x.studentName];
      final all = [ravi, amit, vikas];
      expect(names(StudentService.filter(all, false, const StudentFilter())), [
        'amit Singh',
        'Ravi Kumar',
      ]);
      expect(names(StudentService.filter(all, true, const StudentFilter())), [
        'Vikas Rawat',
      ]);
      // Father's mobile, mother's name.
      expect(
        names(
          StudentService.filter(
            all,
            false,
            const StudentFilter(search: '22233'),
          ),
        ),
        ['Ravi Kumar'],
      );
      expect(
        names(
          StudentService.filter(
            all,
            false,
            const StudentFilter(search: 'sunita'),
          ),
        ),
        ['amit Singh'],
      );
      expect(
        names(
          StudentService.filter(
            all,
            false,
            const StudentFilter(college: 'dav college'),
          ),
        ),
        ['Ravi Kumar'],
      );
      expect(
        names(
          StudentService.filter(
            all,
            false,
            const StudentFilter(className: '2nd year'),
          ),
        ),
        ['amit Singh'],
      );
      expect(StudentService.distinct(['BCA', 'bca', ' B.Com ', null, '']), [
        'B.Com',
        'BCA',
      ]);
      expect(
        StudentService.countText(1, 2, false),
        'Showing 1 of 2 active students',
      );
    });
  });

  group('Students screen', () {
    Future<void> openStudents(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 8400); // every card on screen
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const HostelMobileApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_Students')));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String key, String option) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets('active tab: list, counts, room and details', (tester) async {
      await openStudents(tester);
      expect(find.text('Active (2)'), findsOneWidget);
      expect(find.text('Inactive (1)'), findsOneWidget);
      expect(find.text('Showing 2 of 2 active students'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Room 101'), findsOneWidget);
      expect(find.text('DAV College  ·  B.Com  ·  1st year'), findsOneWidget);
      expect(find.text('Father: Suresh Kumar  ·  98111 22233'), findsOneWidget);
      expect(find.text('Vikas Rawat'), findsNothing);
      expect(find.byKey(const Key('addStudent')), findsOneWidget);
    });

    testWidgets('search and the filter sheet', (tester) async {
      await openStudents(tester);
      await tester.enterText(find.byKey(const Key('studentSearch')), '43210');
      await tester.pump();
      expect(find.text('Showing 1 of 2 active students'), findsOneWidget);
      expect(find.text('amit Singh'), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('openFilters')));
      await tester.pumpAndSettle();
      await choose(tester, 'filterCourse', 'BCA');
      await tester.tap(find.byKey(const Key('applyFilters')));
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 2 active students'), findsOneWidget);
      expect(find.text('amit Singh'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsNothing);
      expect(find.text('1'), findsOneWidget); // badge: one filter
    });

    testWidgets('adds a student; gender must be chosen', (tester) async {
      await openStudents(tester);
      await tester.tap(find.byKey(const Key('addStudent')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add Student'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('studentName')), ' Neha ');
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();
      expect(find.text('Please select the gender.'), findsOneWidget);

      await choose(tester, 'studentGender', 'Female');
      await tester.enterText(
        find.byKey(const Key('studentAadhaar')),
        '9876 5432 1096',
      );
      await choose(tester, 'studentCollege', 'Doon University');
      await tester.enterText(find.byKey(const Key('studentCourse')), 'BCA');
      await tester.enterText(find.byKey(const Key('fatherName')), 'Raj Verma');
      await tester.enterText(
        find.byKey(const Key('fatherMobile')),
        '+91 98000 12345',
      );
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();

      expect(find.text('Student added.'), findsOneWidget);
      final data = db.saved.single;
      expect(data['student_name'], 'Neha');
      expect(data['gender'], 'Female');
      expect(data['aadhaar_number'], '987654321096');
      expect(data['college_id'], 2);
      expect(data['status'], 'Active');
      expect(data['date_of_birth'], isNull);
      expect(find.text('Neha'), findsOneWidget);
      expect(find.text('Active (3)'), findsOneWidget);
    });

    testWidgets('a duplicate Aadhaar number stays on the form', (tester) async {
      await openStudents(tester);
      await tester.tap(find.byKey(const Key('addStudent')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('studentName')), 'Copy');
      await choose(tester, 'studentGender', 'Male');
      await tester.enterText(
        find.byKey(const Key('studentAadhaar')),
        '234567890124',
      );
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();
      expect(
        find.text('Another student already has this Aadhaar number.'),
        findsOneWidget,
      );
    });

    testWidgets('view / edit shows the student and saves changes', (
      tester,
    ) async {
      await openStudents(tester);
      await tester.tap(find.text('Ravi Kumar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Ravi Kumar'), findsOneWidget);
      expect(find.text('Hostel: Boys Hostel  ·  Room 101'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Suresh Kumar'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('studentClass')), '2nd year');
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();
      expect(find.text('Student saved.'), findsOneWidget);
      expect(db.saved.single['id'], 1);
      expect(find.text('DAV College  ·  B.Com  ·  2nd year'), findsOneWidget);
    });

    testWidgets('a student in a room cannot be set to Left', (tester) async {
      await openStudents(tester);
      await tester.tap(find.text('Ravi Kumar'));
      await tester.pumpAndSettle();
      await choose(tester, 'studentStatus', 'Left');
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Ravi Kumar is in room 101. Use Check-out on the Room '
          'Allocation screen; it sets the status to Left.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('delete: only a student without records', (tester) async {
      await openStudents(tester);
      Future<void> delete(int id) async {
        await tester.tap(find.byKey(Key('studentMenu_$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmDelete')));
        await tester.pumpAndSettle();
      }

      await delete(1);
      expect(
        find.text(
          'Ravi Kumar has room, invoice or payment records and '
          'cannot be deleted. Edit the student and set the status to Left '
          'instead.',
        ),
        findsOneWidget,
      );
      await delete(2);
      expect(find.text('Student deleted.'), findsOneWidget);
      expect(find.text('amit Singh'), findsNothing);
    });

    testWidgets('inactive tab: no Add, and Make Active', (tester) async {
      await openStudents(tester);
      await tester.tap(find.text('Inactive (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Vikas Rawat'), findsOneWidget);
      expect(find.byKey(const Key('addStudent')), findsNothing);

      await tester.tap(find.byKey(const Key('studentMenu_3')));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      await tester.tap(find.text('Make Active'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmMakeActive')));
      await tester.pumpAndSettle();
      expect(find.text('Vikas Rawat is active again.'), findsOneWidget);
      expect(find.text('Inactive (0)'), findsOneWidget);
      expect(find.text('Active (3)'), findsOneWidget);
    });

    testWidgets('inactive tab: Delete Permanently needs a reason', (
      tester,
    ) async {
      await openStudents(tester);
      await tester.tap(find.text('Inactive (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('studentMenu_3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Permanently'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Every record of this student'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmPurge')));
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter the reason for deleting the student.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('purgeReason')), 'left 2021');
      await tester.tap(find.byKey(const Key('confirmPurge')));
      await tester.pumpAndSettle();
      expect(find.text('Vikas Rawat was deleted permanently.'), findsOneWidget);
      expect(find.text('Inactive (0)'), findsOneWidget);
    });

    testWidgets('active students have no Delete Permanently', (tester) async {
      await openStudents(tester);
      await tester.tap(find.byKey(const Key('studentMenu_1')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Permanently'), findsNothing);
    });
  });

  test('service: only inactive students, with a reason', () async {
    final db = MemoryStudentRepository([ravi, vikas]);
    StudentRepository.useInstance(db);
    addTearDown(() => StudentRepository.useInstance(null));
    await expectLater(
      StudentService.deletePermanently(ravi, 'why'),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          'Ravi Kumar is active. Check the student out first; only inactive '
              'students can be deleted.',
        ),
      ),
    );
    await expectLater(
      StudentService.deletePermanently(vikas, '  '),
      throwsA(isA<ValidationException>()),
    );
    await StudentService.deletePermanently(vikas, ' left ');
    expect(db.purged.single, {'id': 3, 'reason': 'left'});
  });
}
