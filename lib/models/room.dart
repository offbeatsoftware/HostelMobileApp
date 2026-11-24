/// Who a room is for. Stored as the student gender it accepts and shown as
/// Boys / Girls; a student can only be allocated to a room of their gender.
class RoomGender {
  static const male = 'Male';
  static const female = 'Female';
  static const all = [male, female];

  /// Boys or Girls.
  static String displayName(String gender) => switch (gender) {
    male => 'Boys',
    female => 'Girls',
    _ => '',
  };
}

/// A room. The number of beds comes from its sharing type; occupancy from
/// the students allocated to it now.
class Room {
  const Room({
    required this.roomId,
    required this.hostelId,
    required this.roomNumber,
    this.floor,
    required this.sharingTypeId,
    required this.gender,
    this.isActive = true,
    this.remarks,
    required this.sharingName,
    required this.capacity,
    this.occupied = 0,
  });

  final int roomId;
  final int hostelId;
  final String roomNumber;
  final String? floor;
  final int sharingTypeId;

  /// [RoomGender.male] or [RoomGender.female].
  final String gender;
  final bool isActive;
  final String? remarks;
  final String sharingName;

  /// Number of beds.
  final int capacity;

  /// Students in the room now.
  final int occupied;

  /// Free beds. An inactive room has no free beds.
  int get available => isActive ? (capacity - occupied).clamp(0, capacity) : 0;

  String get status => isActive ? 'Active' : 'Inactive';

  /// Boys or Girls.
  String get roomFor => RoomGender.displayName(gender);

  /// A row of the room_list view.
  factory Room.fromMap(Map<String, dynamic> map) => Room(
    roomId: map['room_id'] as int,
    hostelId: map['hostel_id'] as int,
    roomNumber: map['room_number'] as String,
    floor: map['floor'] as String?,
    sharingTypeId: map['sharing_type_id'] as int,
    gender: map['gender'] as String,
    isActive: map['is_active'] as bool,
    remarks: map['remarks'] as String?,
    sharingName: map['sharing_name'] as String,
    capacity: map['capacity'] as int,
    occupied: (map['occupied'] as int?) ?? 0,
  );
}
