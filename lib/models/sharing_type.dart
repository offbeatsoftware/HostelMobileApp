/// Single, Double or Triple: how many students fit in a room.
class SharingType {
  const SharingType({
    required this.sharingTypeId,
    required this.hostelId,
    required this.sharingName,
    required this.capacity,
  });

  final int sharingTypeId;
  final int hostelId;
  final String sharingName;
  final int capacity;

  /// "1 bed" or "3 beds".
  String get beds => '$capacity ${capacity == 1 ? 'bed' : 'beds'}';

  /// For drop-downs, for example "Double (2 beds)".
  String get displayName => '$sharingName ($beds)';

  factory SharingType.fromMap(Map<String, dynamic> map) => SharingType(
    sharingTypeId: map['sharing_type_id'] as int,
    hostelId: map['hostel_id'] as int,
    sharingName: map['sharing_name'] as String,
    capacity: map['capacity'] as int,
  );
}
