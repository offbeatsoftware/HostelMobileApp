import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/hostel_repository.dart';
import 'package:hostel_mobile_app/main.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/hostel_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-memory database that follows the same rules as the database
/// functions in supabase/003_hostel_functions.sql.
class MemoryHostelRepository extends HostelRepository {
  MemoryHostelRepository(List<Hostel> hostels) : _rows = [...hostels];

  final List<Hostel> _rows;
  int _nextId = 100;
  final saved = <Map<String, Object?>>[];

  @override
  Future<List<Hostel>> getAll() async =>
      [..._rows]..sort((a, b) => a.hostelName.compareTo(b.hostelName));

  @override
  Future<int> save({
    int? hostelId,
    required String hostelName,
    required String address,
    required String phone,
    required String email,
  }) async {
    saved.add({
      'id': hostelId,
      'name': hostelName,
      'address': address,
      'phone': phone,
      'email': email,
    });
    if (_rows.any(
      (h) =>
          h.hostelName.toLowerCase() == hostelName.toLowerCase() &&
          h.hostelId != hostelId,
    )) {
      throw ValidationException('A hostel named "$hostelName" already exists.');
    }
    String? orNull(String s) => s.isEmpty ? null : s;
    final index = _rows.indexWhere((h) => h.hostelId == hostelId);
    final id = hostelId ?? _nextId++;
    final hostel = Hostel(
      hostelId: id,
      hostelName: hostelName,
      address: orNull(address),
      phone: orNull(phone),
      email: orNull(email),
      collegeCount: index >= 0 ? _rows[index].collegeCount : 0,
      roomCount: index >= 0 ? _rows[index].roomCount : 0,
      studentCount: index >= 0 ? _rows[index].studentCount : 0,
    );
    if (index >= 0) {
      _rows[index] = hostel;
    } else {
      _rows.add(hostel);
    }
    return id;
  }

  @override
  Future<void> delete(int hostelId) async {
    final h = _rows.firstWhere((h) => h.hostelId == hostelId);
    if (h.studentCount > 0 || h.collegeCount > 0 || h.roomCount > 0) {
      throw ValidationException(
        '"${h.hostelName}" cannot be deleted because it has '
        '${h.studentCount} student(s), ${h.collegeCount} college(s) and '
        '${h.roomCount} room(s). Delete those first.',
      );
    }
    _rows.remove(h);
  }
}

const boys = Hostel(
  hostelId: 1,
  hostelName: 'Boys Hostel',
  address: 'Suddhowala',
  phone: '98765 43210',
  collegeCount: 2,
  roomCount: 10,
  studentCount: 35,
);
const empty = Hostel(hostelId: 2, hostelName: 'Old Hostel');

void main() {
  late MemoryHostelRepository db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = MemoryHostelRepository([boys, empty]);
    HostelRepository.useInstance(db);
    AuthService.useAuth(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'a', email: 'a@b.com'),
      ),
    );
  });
  tearDown(() {
    HostelRepository.useInstance(null);
    AuthService.useAuth(null);
  });

  group('Validators (same rules as the desktop)', () {
    test('phone: digits, spaces, + - ( ), 6 to 15 digits', () {
      for (final ok in [
        '',
        '98765 43210',
        '+91-98765-43210',
        '(0135) 2345678',
      ]) {
        expect(Validators.isValidPhoneOrEmpty(ok), isTrue, reason: ok);
      }
      for (final bad in ['12345', '1234567890123456', '98765x43210', 'phone']) {
        expect(Validators.isValidPhoneOrEmpty(bad), isFalse, reason: bad);
      }
    });

    test('email', () {
      for (final ok in ['', 'office@myhostel.com', 'a.b@c.co.in']) {
        expect(Validators.isValidEmailOrEmpty(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'office',
        'office@myhostel',
        'a b@c.com',
        'a@@c.com',
      ]) {
        expect(Validators.isValidEmailOrEmpty(bad), isFalse, reason: bad);
      }
    });
  });

  group('HostelService', () {
    Future<void> expectMessage(Future<void> f, String message) => expectLater(
      f,
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', message),
      ),
    );

    test('checks the fields before saving', () async {
      await expectMessage(
        HostelService.save(hostelName: '   '),
        'Please enter the hostel name.',
      );
      await expectMessage(
        HostelService.save(hostelName: 'A', phone: 'abc'),
        'Please enter a valid phone number (digits, spaces, + and - only).',
      );
      await expectMessage(
        HostelService.save(hostelName: 'A', email: 'x@y'),
        'Please enter a valid email address, for example office@myhostel.com.',
      );
      await expectMessage(
        HostelService.save(hostelName: 'A' * 151),
        'Hostel name can be at most 150 characters.',
      );
      expect(db.saved, isEmpty);
    });

    test('removes spaces at the start and end before saving', () async {
      await HostelService.save(
        hostelName: '  New Hostel ',
        address: ' Dehradun ',
        phone: ' ',
        email: '',
      );
      expect(db.saved.single, {
        'id': null,
        'name': 'New Hostel',
        'address': 'Dehradun',
        'phone': '',
        'email': '',
      });
    });
  });

  group('Hostels screen', () {
    Future<void> openHostels(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const HostelMobileApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_Hostels')));
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSave(
      WidgetTester tester,
      Map<String, String> fields,
    ) async {
      for (final e in fields.entries) {
        await tester.enterText(find.byKey(Key(e.key)), e.value);
      }
      await tester.tap(find.byKey(const Key('saveHostel')));
      await tester.pumpAndSettle();
    }

    testWidgets('lists hostels with their details and counts', (tester) async {
      await openHostels(tester);
      expect(find.widgetWithText(AppBar, 'Hostels'), findsOneWidget);
      expect(find.text('Boys Hostel'), findsOneWidget);
      expect(find.text('98765 43210'), findsOneWidget);
      expect(find.text('2 colleges'), findsOneWidget);
      expect(find.text('10 rooms'), findsOneWidget);
      expect(find.text('35 students'), findsOneWidget);
      expect(find.text('Old Hostel'), findsOneWidget);
    });

    testWidgets('adds a hostel, and the home page shows it after', (
      tester,
    ) async {
      await openHostels(tester);
      await tester.tap(find.byKey(const Key('addHostel')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add Hostel'), findsOneWidget);

      await fillAndSave(tester, {
        'hostelName': 'Girls Hostel',
        'hostelAddress': 'Suddhowala, Dehradun',
        'hostelEmail': 'girls@shribalajihostel.com',
      });
      expect(find.text('Hostel added.'), findsOneWidget);
      expect(find.text('Girls Hostel'), findsOneWidget);
      expect(find.text('girls@shribalajihostel.com'), findsOneWidget);

      // Back on the home page the new hostel can be picked.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('changeHostel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hostelOption_100')), findsOneWidget);
    });

    testWidgets('a mistake stays on the form with its message', (tester) async {
      await openHostels(tester);
      await tester.tap(find.byKey(const Key('addHostel')));
      await tester.pumpAndSettle();

      await fillAndSave(tester, {'hostelName': 'BOYS HOSTEL'});
      expect(
        find.text('A hostel named "BOYS HOSTEL" already exists.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppBar, 'Add Hostel'), findsOneWidget);

      await fillAndSave(tester, {'hostelName': 'Third', 'hostelPhone': '12'});
      expect(
        find.text(
          'Please enter a valid phone number (digits, spaces, + and - only).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a hostel edits it', (tester) async {
      await openHostels(tester);
      await tester.tap(find.text('Old Hostel'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Edit Hostel'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Old Hostel'), findsOneWidget);

      await fillAndSave(tester, {'hostelName': 'Annexe Hostel'});
      expect(find.text('Hostel saved.'), findsOneWidget);
      expect(find.text('Annexe Hostel'), findsOneWidget);
      expect(find.text('Old Hostel'), findsNothing);
      expect(db.saved.single['id'], 2);
    });

    testWidgets('deletes an empty hostel after asking', (tester) async {
      await openHostels(tester);
      await tester.tap(find.byKey(const Key('hostelMenu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the hostel "Old Hostel"?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();
      expect(find.text('Hostel deleted.'), findsOneWidget);
      expect(find.text('Old Hostel'), findsNothing);
    });

    testWidgets('Cancel keeps the hostel', (tester) async {
      await openHostels(tester);
      await tester.tap(find.byKey(const Key('hostelMenu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Old Hostel'), findsOneWidget);
    });

    testWidgets('a hostel in use cannot be deleted', (tester) async {
      await openHostels(tester);
      await tester.tap(find.byKey(const Key('hostelMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '"Boys Hostel" cannot be deleted because it has 35 student(s), '
          '2 college(s) and 10 room(s). Delete those first.',
        ),
        findsOneWidget,
      );
      expect(find.text('Boys Hostel'), findsWidgets);
    });

    testWidgets('no hostels yet', (tester) async {
      db = MemoryHostelRepository([]);
      HostelRepository.useInstance(db);
      await openHostels(tester);
      expect(find.byKey(const Key('hostelsEmpty')), findsOneWidget);
    });
  });
}
