/// Values of an allocation's status.
class AllocationStatus {
  static const current = 'Current';
  static const transferred = 'Transferred';
  static const checkedOut = 'CheckedOut';
}

/// A student's stay in a room and bed. History is kept: a transfer or
/// check-out closes the allocation.
class RoomAllocation {
  const RoomAllocation({
    required this.allocationId,
    required this.studentId,
    required this.studentName,
    this.studentMobile,
    required this.roomId,
    required this.roomNumber,
    required this.hostelId,
    this.bedNumber,
    required this.checkInDate,
    this.checkOutDate,
    required this.status,
    this.remarks,
  });

  final int allocationId;
  final int studentId;
  final String studentName;
  final String? studentMobile;
  final int roomId;
  final String roomNumber;
  final int hostelId;
  final int? bedNumber;
  final DateTime checkInDate;
  final DateTime? checkOutDate;
  final String status;
  final String? remarks;

  bool get isCurrent => status == AllocationStatus.current;

  /// "101, bed 2".
  String get roomAndBed =>
      bedNumber == null ? roomNumber : '$roomNumber, bed $bedNumber';

  String get statusText => switch (status) {
    AllocationStatus.current => 'In room',
    AllocationStatus.transferred => 'Transferred',
    AllocationStatus.checkedOut => 'Checked out',
    _ => status,
  };

  /// Nights in the room so far (current) or in total (closed).
  int days(DateTime today) =>
      (checkOutDate ?? today).difference(checkInDate).inDays;

  factory RoomAllocation.fromMap(Map<String, dynamic> map) => RoomAllocation(
    allocationId: map['allocation_id'] as int,
    studentId: map['student_id'] as int,
    studentName: map['student_name'] as String,
    studentMobile: map['student_mobile'] as String?,
    roomId: map['room_id'] as int,
    roomNumber: map['room_number'] as String,
    hostelId: map['hostel_id'] as int,
    bedNumber: map['bed_number'] as int?,
    checkInDate: DateTime.parse(map['check_in_date'] as String),
    checkOutDate: map['check_out_date'] == null
        ? null
        : DateTime.parse(map['check_out_date'] as String),
    status: map['status'] as String,
    remarks: map['remarks'] as String?,
  );
}
