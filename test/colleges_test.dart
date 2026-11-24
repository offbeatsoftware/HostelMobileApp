import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/college_repository.dart';
import 'package:hostel_mobile_app/data/hostel_repository.dart';
import 'package:hostel_mobile_app/main.dart';
import 'package:hostel_mobile_app/models/college.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/college_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixedHostels extends HostelRepository {
  @override
  Future<List<Hostel>> getAll() async => const [
    Hostel(hostelId: 1, hostelName: 'Boys Hostel'),
    Hostel(hostelId: 2, hostelName: 'Girls Hostel'),
  ];
}

/// An in-memory database with the same rules as
/// supabase/004_college_functions.sql.
class MemoryCollegeRepository extends CollegeRepository {
  MemoryCollegeRepository(List<College> colleges) : _rows = [...colleges];

  final List<College> _rows;
  int _nextId = 100;
  final saved = <Map<String, Object?>>[];

  @override
  Future<List<College>> getForHostel(int hostelId) async =>
      _rows.where((c) => c.hostelId == hostelId).toList()
        ..sort((a, b) => a.collegeName.compareTo(b.collegeName));

  @override
  Future<int> save({
    int? collegeId,
    required int hostelId,
    required String collegeName,
    required String address,
    required String phone,
  }) async {
    saved.add({
      'id': collegeId,
      'hostel': hostelId,
      'name': collegeName,
      'address': address,
      'phone': phone,
    });
    final index = _rows.indexWhere((c) => c.collegeId == collegeId);
    final hostel = index >= 0 ? _rows[index].hostelId : hostelId;
    if (_rows.any(
      (c) =>
          c.hostelId == hostel &&
          c.collegeName.toLowerCase() == collegeName.toLowerCase() &&
          c.collegeId != collegeId,
    )) {
      throw ValidationException(
        'A college named "$collegeName" already exists in this hostel.',
      );
    }
    String? orNull(String s) => s.isEmpty ? null : s;
    final id = collegeId ?? _nextId++;
    final college = College(
      collegeId: id,
      hostelId: hostel,
      collegeName: collegeName,
      address: orNull(address),
      phone: orNull(phone),
      studentCount: index >= 0 ? _rows[index].studentCount : 0,
    );
    if (index >= 0) {
      _rows[index] = college;
    } else {
      _rows.add(college);
    }
    return id;
  }

  @override
  Future<void> delete(int collegeId) async {
    final c = _rows.firstWhere((c) => c.collegeId == collegeId);
    if (c.studentCount > 0) {
      throw ValidationException(
        'This college cannot be deleted because '
        '${c.studentCount} student record(s) are linked to it.',
      );
    }
    _rows.remove(c);
  }
}

const dav = College(
  collegeId: 1,
  hostelId: 1,
  collegeName: 'DAV College',
  address: 'Dehradun',
  phone: '0135 2345678',
  studentCount: 12,
);
const doon = College(collegeId: 2, hostelId: 1, collegeName: 'Doon University');
const girlsCollege = College(
  collegeId: 3,
  hostelId: 2,
  collegeName: 'MKP College',
);

void main() {
  late MemoryCollegeRepository db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HostelRepository.useInstance(FixedHostels());
    db = MemoryCollegeRepository([dav, doon, girlsCollege]);
    CollegeRepository.useInstance(db);
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
    AuthService.useAuth(null);
  });

  group('CollegeService', () {
    Future<void> expectMessage(Future<void> f, String message) => expectLater(
      f,
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', message),
      ),
    );

    test('checks the fields before saving', () async {
      await expectMessage(
        CollegeService.save(hostelId: 1, collegeName: ' '),
        'Please enter the college name.',
      );
      await expectMessage(
        CollegeService.save(hostelId: 1, collegeName: 'X', phone: '12'),
        'Please enter a valid phone number (digits, spaces, + and - only).',
      );
      await expectMessage(
        CollegeService.save(hostelId: 1, collegeName: 'X' * 151),
        'College name can be at most 150 characters.',
      );
      expect(db.saved, isEmpty);
    });

    test('search ignores capitals and spaces around the text', () {
      final all = [dav, doon];
      expect(CollegeService.filter(all, '').length, 2);
      expect(
        CollegeService.filter(all, '  dav ').single.collegeName,
        'DAV College',
      );
      expect(
        CollegeService.filter(all, 'UNIVERSITY').single.collegeName,
        'Doon University',
      );
      expect(CollegeService.filter(all, 'xyz'), isEmpty);
    });
  });

  group('Colleges screen', () {
    Future<void> openColleges(WidgetTester tester, {int? hostelId}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (hostelId != null) {
        SharedPreferences.setMockInitialValues({'selectedHostelId': hostelId});
      }
      await tester.pumpWidget(const HostelMobileApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_Colleges')));
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSave(
      WidgetTester tester,
      Map<String, String> fields,
    ) async {
      for (final e in fields.entries) {
        await tester.enterText(find.byKey(Key(e.key)), e.value);
      }
      await tester.tap(find.byKey(const Key('saveCollege')));
      await tester.pumpAndSettle();
    }

    testWidgets("shows only the selected hostel's colleges", (tester) async {
      await openColleges(tester);
      expect(find.widgetWithText(AppBar, 'Colleges'), findsOneWidget);
      expect(find.text('Boys Hostel'), findsOneWidget);
      expect(find.text('DAV College'), findsOneWidget);
      expect(find.text('0135 2345678'), findsOneWidget);
      expect(find.text('12 students'), findsOneWidget);
      expect(find.text('Doon University'), findsOneWidget);
      expect(find.text('MKP College'), findsNothing);
    });

    testWidgets('follows the hostel chosen on the home page', (tester) async {
      await openColleges(tester, hostelId: 2);
      expect(find.text('Girls Hostel'), findsOneWidget);
      expect(find.text('MKP College'), findsOneWidget);
      expect(find.text('DAV College'), findsNothing);
    });

    testWidgets('search filters by name', (tester) async {
      await openColleges(tester);
      await tester.enterText(find.byKey(const Key('collegeSearch')), 'doon');
      await tester.pump();
      expect(find.text('Doon University'), findsOneWidget);
      expect(find.text('DAV College'), findsNothing);

      await tester.enterText(find.byKey(const Key('collegeSearch')), 'xyz');
      await tester.pump();
      expect(find.byKey(const Key('collegesNoMatch')), findsOneWidget);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('DAV College'), findsOneWidget);
      expect(find.text('Doon University'), findsOneWidget);
    });

    testWidgets('adds a college to the selected hostel', (tester) async {
      await openColleges(tester);
      await tester.tap(find.byKey(const Key('addCollege')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add College'), findsOneWidget);
      expect(find.text('Hostel: Boys Hostel'), findsOneWidget);

      await fillAndSave(tester, {
        'collegeName': ' Graphic Era University ',
        'collegeAddress': 'Clement Town',
        'collegePhone': '+91 135 2643421',
      });
      expect(find.text('College added.'), findsOneWidget);
      expect(find.text('Graphic Era University'), findsOneWidget);
      expect(db.saved.single, {
        'id': null,
        'hostel': 1,
        'name': 'Graphic Era University',
        'address': 'Clement Town',
        'phone': '+91 135 2643421',
      });
    });

    testWidgets('a duplicate name stays on the form with its message', (
      tester,
    ) async {
      await openColleges(tester);
      await tester.tap(find.byKey(const Key('addCollege')));
      await tester.pumpAndSettle();
      await fillAndSave(tester, {'collegeName': 'dav college'});
      expect(
        find.text(
          'A college named "dav college" already exists in this hostel.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppBar, 'Add College'), findsOneWidget);
    });

    testWidgets('the same name is allowed in another hostel', (tester) async {
      await openColleges(tester, hostelId: 2);
      await tester.tap(find.byKey(const Key('addCollege')));
      await tester.pumpAndSettle();
      await fillAndSave(tester, {'collegeName': 'DAV College'});
      expect(find.text('College added.'), findsOneWidget);
    });

    testWidgets('tapping a college edits it', (tester) async {
      await openColleges(tester);
      await tester.tap(find.text('Doon University'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Edit College'), findsOneWidget);
      await fillAndSave(tester, {'collegeName': 'Doon University (DU)'});
      expect(find.text('College saved.'), findsOneWidget);
      expect(find.text('Doon University (DU)'), findsOneWidget);
      expect(db.saved.single['id'], 2);
    });

    testWidgets('deletes a college without students after asking', (
      tester,
    ) async {
      await openColleges(tester);
      await tester.tap(find.byKey(const Key('collegeMenu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text('Delete the college "Doon University"?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();
      expect(find.text('College deleted.'), findsOneWidget);
      expect(find.text('Doon University'), findsNothing);
    });

    testWidgets('a college with students cannot be deleted', (tester) async {
      await openColleges(tester);
      await tester.tap(find.byKey(const Key('collegeMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This college cannot be deleted because 12 student '
          'record(s) are linked to it.',
        ),
        findsOneWidget,
      );
      expect(find.text('DAV College'), findsOneWidget);
    });

    testWidgets('no colleges yet', (tester) async {
      CollegeRepository.useInstance(MemoryCollegeRepository([]));
      await openColleges(tester);
      expect(find.byKey(const Key('collegesEmpty')), findsOneWidget);
    });
  });
}
