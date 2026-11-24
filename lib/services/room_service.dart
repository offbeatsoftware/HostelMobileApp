import '../data/room_repository.dart';
import '../models/room.dart';
import 'natural_order.dart';
import 'validators.dart';

/// Which rooms the list shows (the desktop filter box).
enum RoomFilter {
  all('All'),
  active('Active'),
  inactive('Inactive'),
  freeBeds('Free beds');

  const RoomFilter(this.label);

  final String label;
}

/// Room rules, as in the desktop RoomService. The checks here give quick
/// messages; the database checks everything again, including the rules that
/// depend on the students in the room.
class RoomService {
  /// Rooms sorted by room number, 2 before 10.
  static List<Room> sorted(List<Room> rooms) =>
      [...rooms]..sort((a, b) => naturalCompare(a.roomNumber, b.roomNumber));

  /// Rooms whose number or floor contains [text] (ignoring capitals) and
  /// that match [filter].
  static List<Room> filter(List<Room> rooms, String? text, RoomFilter filter) {
    final search = Validators.clean(text).toLowerCase();
    return rooms.where((room) {
      if (search.isNotEmpty &&
          !room.roomNumber.toLowerCase().contains(search) &&
          !(room.floor ?? '').toLowerCase().contains(search)) {
        return false;
      }
      return switch (filter) {
        RoomFilter.all => true,
        RoomFilter.active => room.isActive,
        RoomFilter.inactive => !room.isActive,
        RoomFilter.freeBeds => room.available > 0,
      };
    }).toList();
  }

  /// "12 active rooms, 30 beds, 25 occupied, 5 free" (active rooms only).
  static String summary(List<Room> rooms) {
    final active = rooms.where((r) => r.isActive).toList();
    int sum(int Function(Room) f) => active.fold(0, (t, r) => t + f(r));
    return '${active.length} active ${active.length == 1 ? 'room' : 'rooms'}, '
        '${sum((r) => r.capacity)} beds, ${sum((r) => r.occupied)} occupied, '
        '${sum((r) => r.available)} free';
  }

  /// Validates and adds a room to [hostelId] (roomId null) or saves changes.
  /// Throws [ValidationException] with a message for the admin.
  static Future<int> save({
    int? roomId,
    required int hostelId,
    required String roomNumber,
    String? floor,
    int? sharingTypeId,
    String? gender,
    bool isActive = true,
    String? remarks,
  }) async {
    final number = Validators.clean(roomNumber);
    final cleanFloor = Validators.clean(floor);
    final cleanRemarks = Validators.clean(remarks);

    if (number.isEmpty) {
      throw const ValidationException('Please enter the room number.');
    }
    Validators.checkLength(number, 20, 'Room number');
    Validators.checkLength(cleanFloor, 20, 'Floor');
    Validators.checkLength(cleanRemarks, 255, 'Remarks');
    if (sharingTypeId == null) {
      throw const ValidationException('Please select the sharing type.');
    }
    if (gender == null || !RoomGender.all.contains(gender)) {
      throw const ValidationException(
        'Please select whether the room is for boys or girls.',
      );
    }

    return await RoomRepository.instance.save(
      roomId: roomId,
      hostelId: hostelId,
      roomNumber: number,
      floor: cleanFloor,
      sharingTypeId: sharingTypeId,
      gender: gender,
      isActive: isActive,
      remarks: cleanRemarks,
    );
  }

  static Future<void> delete(int roomId) =>
      RoomRepository.instance.delete(roomId);
}
