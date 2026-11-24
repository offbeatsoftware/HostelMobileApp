import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/hostel_repository.dart';
import 'package:hostel_mobile_app/data/room_repository.dart';
import 'package:hostel_mobile_app/main.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/room.dart';
import 'package:hostel_mobile_app/models/sharing_type.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/natural_order.dart';
import 'package:hostel_mobile_app/services/room_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixedHostels extends HostelRepository {
  @override
  Future<List<Hostel>> getAll() async => const [
    Hostel(hostelId: 1, hostelName: 'Boys Hostel'),
  ];
}

const single = SharingType(
  sharingTypeId: 1,
  hostelId: 1,
  sharingName: 'Single',
  capacity: 1,
);
const double_ = SharingType(
  sharingTypeId: 2,
  hostelId: 1,
  sharingName: 'Double',
  capacity: 2,
);
const triple = SharingType(
  sharingTypeId: 3,
  hostelId: 1,
  sharingName: 'Triple',
  capacity: 3,
);
const types = [single, double_, triple];

/// An in-memory database with the main rules of
/// supabase/005_room_functions.sql.
class MemoryRoomRepository extends RoomRepository {
  MemoryRoomRepository(List<Room> rooms, {this.everUsed = const {}})
    : _rows = [...rooms];

  final List<Room> _rows;

  /// Rooms that have had students (cannot be deleted).
  final Set<int> everUsed;
  int _nextId = 100;
  final saved = <Map<String, Object?>>[];

  @override
  Future<List<Room>> getForHostel(int hostelId) async =>
      _rows.where((r) => r.hostelId == hostelId).toList();

  @override
  Future<List<SharingType>> getSharingTypes(int hostelId) async => types;

  @override
  Future<int> save({
    int? roomId,
    required int hostelId,
    required String roomNumber,
    required String floor,
    required int sharingTypeId,
    required String gender,
    required bool isActive,
    required String remarks,
  }) async {
    saved.add({
      'id': roomId,
      'number': roomNumber,
      'floor': floor,
      'sharing': sharingTypeId,
      'gender': gender,
      'active': isActive,
      'remarks': remarks,
    });
    if (_rows.any(
      (r) =>
          r.roomNumber.toLowerCase() == roomNumber.toLowerCase() &&
          r.roomId != roomId,
    )) {
      throw ValidationException(
        'Room number "$roomNumber" already exists in this hostel.',
      );
    }
    final index = _rows.indexWhere((r) => r.roomId == roomId);
    final type = types.firstWhere((t) => t.sharingTypeId == sharingTypeId);
    if (index >= 0) {
      final old = _rows[index];
      if (!isActive && old.occupied > 0) {
        throw ValidationException(
          'Room ${old.roomNumber} has ${old.occupied} student(s) and cannot '
          'be made inactive. Check out or transfer the students first.',
        );
      }
    }
    final id = roomId ?? _nextId++;
    final room = Room(
      roomId: id,
      hostelId: hostelId,
      roomNumber: roomNumber,
      floor: floor.isEmpty ? null : floor,
      sharingTypeId: sharingTypeId,
      gender: gender,
      isActive: isActive,
      remarks: remarks.isEmpty ? null : remarks,
      sharingName: type.sharingName,
      capacity: type.capacity,
      occupied: index >= 0 ? _rows[index].occupied : 0,
    );
    if (index >= 0) {
      _rows[index] = room;
    } else {
      _rows.add(room);
    }
    return id;
  }

  @override
  Future<void> delete(int roomId) async {
    if (everUsed.contains(roomId)) {
      throw const ValidationException(
        'This room cannot be deleted because students have stayed in it. '
        'Edit the room and mark it inactive instead.',
      );
    }
    _rows.removeWhere((r) => r.roomId == roomId);
  }
}

Room room(
  int id,
  String number, {
  String? floor,
  SharingType type = double_,
  String gender = RoomGender.male,
  bool active = true,
  int occupied = 0,
  String? remarks,
}) => Room(
  roomId: id,
  hostelId: 1,
  roomNumber: number,
  floor: floor,
  sharingTypeId: type.sharingTypeId,
  gender: gender,
  isActive: active,
  remarks: remarks,
  sharingName: type.sharingName,
  capacity: type.capacity,
  occupied: occupied,
);

final sample = [
  room(1, '10', floor: 'First', occupied: 2), // full
  room(2, '2', floor: 'Ground', type: triple, occupied: 1),
  room(3, '101A', floor: 'First', type: single, gender: RoomGender.female),
  room(4, '9', active: false, remarks: 'Being repaired'),
];

void main() {
  late MemoryRoomRepository db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HostelRepository.useInstance(FixedHostels());
    db = MemoryRoomRepository(sample, everUsed: {1});
    RoomRepository.useInstance(db);
    AuthService.useAuth(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'a', email: 'a@b.com'),
      ),
    );
  });
  tearDown(() {
    HostelRepository.useInstance(null);
    RoomRepository.useInstance(null);
    AuthService.useAuth(null);
  });

  group('rules', () {
    test('room numbers sort naturally: 2 before 10, 101 before 101A', () {
      final numbers = ['10', '2', '101A', '9', '101', 'G1', 'g02']
        ..sort(naturalCompare);
      expect(numbers, ['2', '9', '10', '101', '101A', 'G1', 'g02']);
    });

    test('free beds: an inactive room has none', () {
      expect(sample[0].available, 0);
      expect(sample[1].available, 2);
      expect(sample[3].available, 0);
    });

    test('summary counts active rooms only', () {
      expect(
        RoomService.summary(sample),
        '3 active rooms, 6 beds, 3 occupied, 3 free',
      );
    });

    test('search by number or floor, and filters', () {
      List<String> numbers(List<Room> r) => [for (final x in r) x.roomNumber];
      expect(numbers(RoomService.filter(sample, 'first', RoomFilter.all)), [
        '10',
        '101A',
      ]);
      expect(numbers(RoomService.filter(sample, '10', RoomFilter.all)), [
        '10',
        '101A',
      ]);
      expect(numbers(RoomService.filter(sample, '', RoomFilter.inactive)), [
        '9',
      ]);
      expect(numbers(RoomService.filter(sample, '', RoomFilter.freeBeds)), [
        '2',
        '101A',
      ]);
      expect(numbers(RoomService.filter(sample, '', RoomFilter.active)), [
        '10',
        '2',
        '101A',
      ]);
    });

    test('checks the fields before saving', () async {
      Future<void> expectMessage(Future<void> f, String message) => expectLater(
        f,
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            message,
          ),
        ),
      );
      await expectMessage(
        RoomService.save(
          hostelId: 1,
          roomNumber: ' ',
          sharingTypeId: 2,
          gender: 'Male',
        ),
        'Please enter the room number.',
      );
      await expectMessage(
        RoomService.save(hostelId: 1, roomNumber: '5', gender: 'Male'),
        'Please select the sharing type.',
      );
      await expectMessage(
        RoomService.save(hostelId: 1, roomNumber: '5', sharingTypeId: 2),
        'Please select whether the room is for boys or girls.',
      );
      expect(db.saved, isEmpty);
    });
  });

  group('Rooms screen', () {
    Future<void> openRooms(WidgetTester tester) async {
      tester.view.physicalSize = const Size(
        1080,
        5400,
      ); // tall: every card on screen
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const HostelMobileApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_Rooms')));
      await tester.pumpAndSettle();
    }

    List<String> shownNumbers(WidgetTester tester) => [
      for (final r in sample)
        if (find.byKey(Key('room_${r.roomId}')).evaluate().isNotEmpty)
          r.roomNumber,
    ];

    testWidgets('lists rooms in natural order with beds and summary', (
      tester,
    ) async {
      await openRooms(tester);
      expect(find.widgetWithText(AppBar, 'Rooms'), findsOneWidget);
      expect(
        find.text('3 active rooms, 6 beds, 3 occupied, 3 free'),
        findsOneWidget,
      );
      final y = {
        for (final r in sample)
          r.roomNumber: tester
              .getTopLeft(find.byKey(Key('room_${r.roomId}')))
              .dy,
      };
      expect(
        y['2']! < y['9']! && y['9']! < y['10']! && y['10']! < y['101A']!,
        isTrue,
      );
      expect(find.text('2 of 2 beds used  ·  Full'), findsOneWidget);
      expect(find.text('1 of 3 beds used  ·  2 free'), findsOneWidget);
      expect(find.text('Inactive  ·  2 beds'), findsOneWidget);
      expect(find.text('Girls  ·  Single sharing'), findsOneWidget);
      expect(find.text('Being repaired'), findsOneWidget);
    });

    testWidgets('search and filter chips', (tester) async {
      await openRooms(tester);
      await tester.tap(find.byKey(const Key('roomFilter_freeBeds')));
      await tester.pump();
      expect(shownNumbers(tester), ['2', '101A']);

      await tester.enterText(find.byKey(const Key('roomSearch')), 'ground');
      await tester.pump();
      expect(shownNumbers(tester), ['2']);

      await tester.tap(find.byKey(const Key('roomFilter_inactive')));
      await tester.pump();
      expect(find.byKey(const Key('roomsNoMatch')), findsOneWidget);
    });

    testWidgets('adds a room: sharing type preset, boys or girls required', (
      tester,
    ) async {
      await openRooms(tester);
      await tester.tap(find.byKey(const Key('addRoom')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add Room'), findsOneWidget);
      expect(find.text('Single (1 bed)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('roomNumber')), ' 205 ');
      await tester.enterText(find.byKey(const Key('roomFloor')), 'Second');
      await tester.tap(find.byKey(const Key('saveRoom')));
      await tester.pumpAndSettle();
      expect(
        find.text('Please select whether the room is for boys or girls.'),
        findsOneWidget,
      );

      // Choose Triple and Girls.
      await tester.tap(find.byKey(const Key('roomSharing')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Triple (3 beds)').last);
      await tester.pumpAndSettle();
      expect(
        find.text('3 beds. The rent is agreed per student at check-in.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Girls'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveRoom')));
      await tester.pumpAndSettle();

      expect(find.text('Room added.'), findsOneWidget);
      expect(db.saved.single, {
        'id': null,
        'number': '205',
        'floor': 'Second',
        'sharing': 3,
        'gender': 'Female',
        'active': true,
        'remarks': '',
      });
      expect(find.text('Girls  ·  Triple sharing'), findsOneWidget);
    });

    testWidgets('a duplicate room number stays on the form', (tester) async {
      await openRooms(tester);
      await tester.tap(find.byKey(const Key('addRoom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('roomNumber')), '101a');
      await tester.tap(find.text('Boys'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveRoom')));
      await tester.pumpAndSettle();
      expect(
        find.text('Room number "101a" already exists in this hostel.'),
        findsOneWidget,
      );
    });

    testWidgets('edit shows the room as it is, and saves changes', (
      tester,
    ) async {
      await openRooms(tester);
      await tester.tap(find.byKey(const Key('room_2')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Edit Room 2'), findsOneWidget);
      expect(
        find.text('Hostel: Boys Hostel. Beds in use now: 1 of 3.'),
        findsOneWidget,
      );
      expect(find.text('Triple (3 beds)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('roomRemarks')), 'Balcony');
      await tester.tap(find.byKey(const Key('saveRoom')));
      await tester.pumpAndSettle();
      expect(find.text('Room saved.'), findsOneWidget);
      expect(db.saved.single['gender'], 'Male');
      expect(db.saved.single['sharing'], 3);
      expect(find.text('Balcony'), findsOneWidget);
    });

    testWidgets('an occupied room cannot be made inactive', (tester) async {
      await openRooms(tester);
      await tester.tap(find.byKey(const Key('room_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('roomActive')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveRoom')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Room 2 has 1 student(s) and cannot be made inactive. '
          'Check out or transfer the students first.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('delete: a never used room goes, a used room stays', (
      tester,
    ) async {
      await openRooms(tester);
      Future<void> deleteRoom(int id) async {
        await tester.tap(find.byKey(Key('roomMenu_$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmDelete')));
        await tester.pumpAndSettle();
      }

      await deleteRoom(3);
      expect(find.text('Room deleted.'), findsOneWidget);
      expect(find.byKey(const Key('room_3')), findsNothing);

      await deleteRoom(1);
      expect(
        find.text(
          'This room cannot be deleted because students have stayed '
          'in it. Edit the room and mark it inactive instead.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('room_1')), findsOneWidget);
    });

    testWidgets('no rooms yet', (tester) async {
      RoomRepository.useInstance(MemoryRoomRepository([]));
      await openRooms(tester);
      expect(find.byKey(const Key('roomsEmpty')), findsOneWidget);
      expect(find.byKey(const Key('roomSummary')), findsNothing);
    });
  });
}
