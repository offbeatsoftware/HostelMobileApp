/// A hostel, with the number of colleges, rooms and students it has.
class Hostel {
  const Hostel({
    required this.hostelId,
    required this.hostelName,
    this.address,
    this.phone,
    this.email,
    this.collegeCount = 0,
    this.roomCount = 0,
    this.studentCount = 0,
  });

  final int hostelId;
  final String hostelName;
  final String? address;
  final String? phone;
  final String? email;
  final int collegeCount;
  final int roomCount;
  final int studentCount;

  /// A row of the hostel_list view (or the hostel table).
  factory Hostel.fromMap(Map<String, dynamic> map) => Hostel(
    hostelId: map['hostel_id'] as int,
    hostelName: map['hostel_name'] as String,
    address: map['address'] as String?,
    phone: map['phone'] as String?,
    email: map['email'] as String?,
    collegeCount: (map['college_count'] as int?) ?? 0,
    roomCount: (map['room_count'] as int?) ?? 0,
    studentCount: (map['student_count'] as int?) ?? 0,
  );
}
