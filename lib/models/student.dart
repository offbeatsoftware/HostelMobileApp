/// Values of a student's status.
class StudentStatus {
  static const active = 'Active';
  static const left = 'Left';
  static const all = [active, left];
}

/// A hostel student with their father's and mother's details.
class Student {
  const Student({
    required this.studentId,
    required this.hostelId,
    required this.studentName,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.collegeId,
    this.course,
    this.className,
    this.mobile,
    this.email,
    this.fatherName,
    this.fatherMobile,
    this.fatherEmail,
    this.motherName,
    this.motherMobile,
    this.motherEmail,
    this.aadhaarNumber,
    required this.admissionDate,
    this.status = StudentStatus.active,
    this.remarks,
    this.collegeName,
    this.roomNumber,
  });

  /// The genders a student can have; the gender decides the rooms.
  static const genders = ['Male', 'Female', 'Other'];

  final int studentId;
  final int hostelId;
  final String studentName;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? address;
  final int? collegeId;
  final String? course;
  final String? className;
  final String? mobile;
  final String? email;
  final String? fatherName;
  final String? fatherMobile;
  final String? fatherEmail;
  final String? motherName;
  final String? motherMobile;
  final String? motherEmail;
  final String? aadhaarNumber;
  final DateTime admissionDate;
  final String status;
  final String? remarks;

  /// Read only: the college's name and the room the student is in now.
  final String? collegeName;
  final String? roomNumber;

  bool get isActive => status == StudentStatus.active;

  /// "XXXX XXXX 0124": only the last four digits are shown in lists.
  String get aadhaarMasked {
    final a = aadhaarNumber ?? '';
    return a.length == 12 ? 'XXXX XXXX ${a.substring(8)}' : '';
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  /// A row of the student_list view.
  factory Student.fromMap(Map<String, dynamic> map) => Student(
    studentId: map['student_id'] as int,
    hostelId: map['hostel_id'] as int,
    studentName: map['student_name'] as String,
    dateOfBirth: _date(map['date_of_birth']),
    gender: map['gender'] as String?,
    address: map['address'] as String?,
    collegeId: map['college_id'] as int?,
    course: map['course'] as String?,
    className: map['class_name'] as String?,
    mobile: map['mobile'] as String?,
    email: map['email'] as String?,
    fatherName: map['father_name'] as String?,
    fatherMobile: map['father_mobile'] as String?,
    fatherEmail: map['father_email'] as String?,
    motherName: map['mother_name'] as String?,
    motherMobile: map['mother_mobile'] as String?,
    motherEmail: map['mother_email'] as String?,
    aadhaarNumber: map['aadhaar_number'] as String?,
    admissionDate: _date(map['admission_date'])!,
    status: map['status'] as String,
    remarks: map['remarks'] as String?,
    collegeName: map['college_name'] as String?,
    roomNumber: map['room_number'] as String?,
  );
}
