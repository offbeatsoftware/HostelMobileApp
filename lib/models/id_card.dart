import 'dart:typed_data';

/// Everything printed on one I-card.
class IdCard {
  const IdCard({
    required this.hostelName,
    required this.hostelPhone,
    required this.studentName,
    required this.fatherName,
    required this.collegeName,
    required this.roomText,
    required this.studentMobile,
    required this.fatherMobile,
    required this.photo,
    required this.validTill,
    required this.academicYear,
  });

  final String hostelName;
  final String hostelPhone;
  final String studentName;
  final String fatherName;
  final String collegeName;

  /// "Room 101, bed 2", or empty.
  final String roomText;
  final String studentMobile;
  final String fatherMobile;

  /// The student's photo; null prints an empty photo box.
  final Uint8List? photo;
  final DateTime validTill;

  /// "2026-2027".
  final String academicYear;
}
