/// A college whose students stay in a hostel.
class College {
  const College({
    required this.collegeId,
    required this.hostelId,
    required this.collegeName,
    this.address,
    this.phone,
    this.studentCount = 0,
  });

  final int collegeId;
  final int hostelId;
  final String collegeName;
  final String? address;
  final String? phone;

  /// Number of student records linked to the college.
  final int studentCount;

  /// A row of the college_list view.
  factory College.fromMap(Map<String, dynamic> map) => College(
    collegeId: map['college_id'] as int,
    hostelId: map['hostel_id'] as int,
    collegeName: map['college_name'] as String,
    address: map['address'] as String?,
    phone: map['phone'] as String?,
    studentCount: (map['student_count'] as int?) ?? 0,
  );
}
