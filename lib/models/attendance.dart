/// One student's line on the night's attendance sheet.
class AttendanceEntry {
  AttendanceEntry({
    required this.studentId,
    required this.studentName,
    required this.roomNumber,
    this.bedNumber,
    this.parentName,
    this.parentRelation,
    this.parentMobile,
    this.isPresent = true,
    this.remarks = '',
    this.isSaved = false,
    this.messaged = false,
  });

  final int studentId;
  final String studentName;
  final String roomNumber;
  final int? bedNumber;

  /// Who is told about an absence: the mother, else the father.
  final String? parentName;
  final String? parentRelation;

  /// The parent's mobile as WhatsApp needs it (91 and ten digits), or null.
  final String? parentMobile;

  /// Changed by the admin before saving.
  bool isPresent;
  String remarks;

  /// True when the night's record has been saved.
  final bool isSaved;

  /// True when the parent was already sent a WhatsApp message for the night.
  bool messaged;

  /// "101, bed 2".
  String get roomAndBed =>
      bedNumber == null ? roomNumber : '$roomNumber, bed $bedNumber';
}

/// A saved attendance record (the student's details come from the sheet).
class SavedAttendance {
  const SavedAttendance(this.studentId, this.isPresent, this.remarks);

  final int studentId;
  final bool isPresent;
  final String? remarks;

  factory SavedAttendance.fromMap(Map<String, dynamic> map) => SavedAttendance(
    map['student_id'] as int,
    map['is_present'] as bool,
    map['remarks'] as String?,
  );
}
