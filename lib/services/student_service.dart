import '../data/student_repository.dart';
import '../models/student.dart';
import 'agreement_signature_service.dart';
import 'date_format.dart';
import 'validators.dart';

/// What the admin typed in the student form.
class StudentInput {
  StudentInput({
    this.studentId,
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
  });

  final int? studentId;
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
}

/// Which students the list shows, besides the Active / Inactive tab.
class StudentFilter {
  const StudentFilter({
    this.search = '',
    this.college,
    this.course,
    this.className,
  });

  final String search;
  final String? college;
  final String? course;
  final String? className;

  /// Number of drop-down filters chosen (not counting the search).
  int get count => [college, course, className].where((v) => v != null).length;
}

/// Student rules, as in the desktop StudentService. The checks here give
/// quick messages; the database checks them again, together with the rules
/// that depend on the student's room and records.
class StudentService {
  /// Students of one tab, sorted by name (ignoring capitals), matching the
  /// search (student, father or mother name or mobile) and the filters.
  static List<Student> filter(
    List<Student> students,
    bool inactiveTab,
    StudentFilter f,
  ) {
    final status = inactiveTab ? StudentStatus.left : StudentStatus.active;
    final search = Validators.clean(f.search).toLowerCase();
    bool has(String? value) => (value ?? '').toLowerCase().contains(search);
    bool same(String? a, String? b) =>
        b == null || (a ?? '').toLowerCase() == b.toLowerCase();

    final shown = students.where((s) {
      if (s.status != status) return false;
      if (search.isNotEmpty &&
          !has(s.studentName) &&
          !has(s.mobile) &&
          !has(s.fatherName) &&
          !has(s.fatherMobile) &&
          !has(s.motherName) &&
          !has(s.motherMobile)) {
        return false;
      }
      return same(s.collegeName, f.college) &&
          same(s.course, f.course) &&
          same(s.className, f.className);
    }).toList();
    shown.sort(
      (a, b) =>
          a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()),
    );
    return shown;
  }

  /// The different values entered (for the filter drop-downs), sorted.
  static List<String> distinct(Iterable<String?> values) {
    final seen = <String, String>{};
    for (final v in values) {
      final clean = Validators.clean(v);
      if (clean.isNotEmpty) seen.putIfAbsent(clean.toLowerCase(), () => clean);
    }
    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// "Showing 12 of 40 active students".
  static String countText(int shown, int inTab, bool inactiveTab) =>
      'Showing $shown of $inTab ${inactiveTab ? 'inactive' : 'active'} '
      '${inTab == 1 ? 'student' : 'students'}';

  /// Validates and adds or saves a student. Only the name and gender are
  /// required; everything else entered must be valid.
  /// Throws [ValidationException] with a message for the admin.
  static Future<int> save(StudentInput input, {DateTime? today}) async {
    final c = Validators.clean;
    final name = c(input.studentName);
    final gender = c(input.gender);
    final aadhaar = Validators.cleanAadhaar(input.aadhaarNumber);
    final now = dateOnly(today ?? DateTime.now());
    final birth = input.dateOfBirth == null
        ? null
        : dateOnly(input.dateOfBirth!);
    final admission = dateOnly(input.admissionDate);

    if (name.isEmpty) {
      throw const ValidationException("Please enter the student's name.");
    }
    if (gender.isEmpty) {
      throw const ValidationException('Please select the gender.');
    }
    for (final (value, max, label) in [
      (name, 150, 'Student name'),
      (c(input.fatherName), 150, "Father's name"),
      (c(input.fatherMobile), 20, "Father's mobile"),
      (c(input.fatherEmail), 150, "Father's email"),
      (c(input.motherName), 150, "Mother's name"),
      (c(input.motherMobile), 20, "Mother's mobile"),
      (c(input.motherEmail), 150, "Mother's email"),
      (c(input.address), 255, 'Address'),
      (c(input.course), 100, 'Course'),
      (c(input.className), 50, 'Class'),
      (c(input.mobile), 20, 'Mobile'),
      (c(input.email), 150, 'Email'),
      (c(input.remarks), 255, 'Remarks'),
    ]) {
      Validators.checkLength(value, max, label);
    }
    for (final (value, isPhone, who) in [
      (c(input.mobile), true, 'the student'),
      (c(input.email), false, 'the student'),
      (c(input.fatherMobile), true, 'the father'),
      (c(input.fatherEmail), false, 'the father'),
      (c(input.motherMobile), true, 'the mother'),
      (c(input.motherEmail), false, 'the mother'),
    ]) {
      if (isPhone && !Validators.isValidPhoneOrEmpty(value)) {
        throw ValidationException(
          'Please enter a valid mobile number for $who.',
        );
      }
      if (!isPhone && !Validators.isValidEmailOrEmpty(value)) {
        throw ValidationException(
          'Please enter a valid email address for $who.',
        );
      }
    }
    if (!Student.genders.contains(gender)) {
      throw const ValidationException(
        'Please select the gender from the list.',
      );
    }
    if (!StudentStatus.all.contains(input.status)) {
      throw const ValidationException(
        'Please select the status (Active or Left).',
      );
    }
    if (birth != null && !birth.isBefore(now)) {
      throw const ValidationException('The date of birth must be in the past.');
    }
    if (birth != null && !admission.isAfter(birth)) {
      throw const ValidationException(
        'The admission date must be after the date of birth.',
      );
    }
    if (!Validators.isValidAadhaarOrEmpty(aadhaar)) {
      throw const ValidationException(
        'The Aadhaar number is not valid. It must have 12 digits; '
        'please check it for typing mistakes.',
      );
    }

    return await StudentRepository.instance.save(
      studentId: input.studentId,
      hostelId: input.hostelId,
      data: {
        'student_name': name,
        'gender': gender,
        'date_of_birth': birth == null ? null : isoDate(birth),
        'admission_date': isoDate(admission),
        'address': c(input.address),
        'college_id': input.collegeId,
        'course': c(input.course),
        'class_name': c(input.className),
        'mobile': c(input.mobile),
        'email': c(input.email),
        'father_name': c(input.fatherName),
        'father_mobile': c(input.fatherMobile),
        'father_email': c(input.fatherEmail),
        'mother_name': c(input.motherName),
        'mother_mobile': c(input.motherMobile),
        'mother_email': c(input.motherEmail),
        'aadhaar_number': aadhaar,
        'status': input.status,
        'remarks': c(input.remarks),
      },
    );
  }

  static Future<void> delete(int studentId) =>
      StudentRepository.instance.delete(studentId);

  static Future<void> makeActive(int studentId) =>
      StudentRepository.instance.makeActive(studentId);

  /// Deletes an inactive student for good, with all their fees, payments,
  /// refunds, room history, attendance and emails; the reason is required.
  static Future<void> deletePermanently(Student student, String? reason) async {
    if (student.status != StudentStatus.left) {
      throw ValidationException(
        '${student.studentName} is active. Check the student out first; only '
        'inactive students can be deleted.',
      );
    }
    final why = Validators.clean(reason);
    if (why.isEmpty) {
      throw const ValidationException(
        'Please enter the reason for deleting the student.',
      );
    }
    Validators.checkLength(why, 255, 'Reason');
    await StudentRepository.instance.deletePermanently(student.studentId, why);
    // The signatures are files; the database row went with the student.
    try {
      await AgreementSignatureService.deleteForStudent(student.studentId);
    } catch (_) {
      // The student is deleted; leftover signature files are harmless.
    }
  }
}
