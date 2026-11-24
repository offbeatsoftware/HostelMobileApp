import 'package:flutter/material.dart';

import '../models/college.dart';
import '../models/hostel.dart';
import '../models/student.dart';
import '../services/date_format.dart';
import '../services/student_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Add or view / edit one student (the desktop StudentEditForm): the
/// student, college and stay, and the father and mother.
/// Closes with true when the student was saved.
class StudentEditScreen extends StatefulWidget {
  const StudentEditScreen({
    super.key,
    required this.hostel,
    required this.colleges,
    this.student,
    this.today,
  });

  /// The hostel a new student is added to.
  final Hostel hostel;

  /// The hostel's colleges, for the College drop-down.
  final List<College> colleges;

  /// The student to edit, or null to add a new one.
  final Student? student;

  /// Today's date; only the automated tests set it.
  final DateTime? today;

  @override
  State<StudentEditScreen> createState() => _StudentEditScreenState();
}

class _StudentEditScreenState extends State<StudentEditScreen> {
  late final Student? s = widget.student;
  late final _name = TextEditingController(text: s?.studentName);
  late final _mobile = TextEditingController(text: s?.mobile);
  late final _email = TextEditingController(text: s?.email);
  late final _address = TextEditingController(text: s?.address);
  late final _aadhaar = TextEditingController(text: s?.aadhaarNumber);
  late final _course = TextEditingController(text: s?.course);
  late final _class = TextEditingController(text: s?.className);
  late final _remarks = TextEditingController(text: s?.remarks);
  late final _fatherName = TextEditingController(text: s?.fatherName);
  late final _fatherMobile = TextEditingController(text: s?.fatherMobile);
  late final _fatherEmail = TextEditingController(text: s?.fatherEmail);
  late final _motherName = TextEditingController(text: s?.motherName);
  late final _motherMobile = TextEditingController(text: s?.motherMobile);
  late final _motherEmail = TextEditingController(text: s?.motherEmail);

  // The gender is chosen by the admin (no default), as on the desktop.
  late String? _gender = s?.gender;
  late int? _collegeId = s?.collegeId;
  late String _status = s?.status ?? StudentStatus.active;
  late DateTime? _birth = s?.dateOfBirth;
  late DateTime _admission =
      s?.admissionDate ?? dateOnly(widget.today ?? DateTime.now());

  String _message = '';
  bool _busy = false;

  bool get _isNew => s == null;

  List<TextEditingController> get _controllers => [
    _name,
    _mobile,
    _email,
    _address,
    _aadhaar,
    _course,
    _class,
    _remarks,
    _fatherName,
    _fatherMobile,
    _fatherEmail,
    _motherName,
    _motherMobile,
    _motherEmail,
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await StudentService.save(
        StudentInput(
          studentId: s?.studentId,
          hostelId: widget.hostel.hostelId,
          studentName: _name.text,
          dateOfBirth: _birth,
          gender: _gender,
          address: _address.text,
          collegeId: _collegeId,
          course: _course.text,
          className: _class.text,
          mobile: _mobile.text,
          email: _email.text,
          fatherName: _fatherName.text,
          fatherMobile: _fatherMobile.text,
          fatherEmail: _fatherEmail.text,
          motherName: _motherName.text,
          motherMobile: _motherMobile.text,
          motherEmail: _motherEmail.text,
          aadhaarNumber: _aadhaar.text,
          admissionDate: _admission,
          status: _status,
          remarks: _remarks.text,
        ),
        today: widget.today,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('The student could not be saved. $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  Widget _text(
    String key,
    String label,
    TextEditingController controller,
    int maxLength, {
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
  }) => FormTextField(
    key: Key(key),
    label: label,
    controller: controller,
    maxLength: maxLength,
    required: required,
    keyboard: keyboard,
    maxLines: maxLines,
    enabled: !_busy,
  );

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(widget.today ?? DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNew ? 'Add Student' : s!.studentName,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              [
                'Hostel: ${widget.hostel.hostelName}',
                if (s?.roomNumber != null) 'Room ${s!.roomNumber}',
              ].join('  ·  '),
              key: const Key('studentInfo'),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const FormSection('Student'),
            _text('studentName', 'Student name', _name, 150, required: true),
            FormDropdown<String>(
              key: const Key('studentGender'),
              label: 'Gender',
              required: true,
              value: _gender,
              enabled: !_busy,
              items: [
                for (final g in Student.genders)
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            DateField(
              key: const Key('studentBirth'),
              label: 'Date of birth',
              value: _birth,
              optional: true,
              enabled: !_busy,
              firstDate: DateTime(1950),
              lastDate: today,
              initialPickerDate: DateTime(
                today.year - 18,
                today.month,
                today.day,
              ),
              onChanged: (v) => setState(() => _birth = v),
            ),
            _text(
              'studentMobile',
              'Mobile',
              _mobile,
              20,
              keyboard: TextInputType.phone,
            ),
            _text(
              'studentEmail',
              'Email',
              _email,
              150,
              keyboard: TextInputType.emailAddress,
            ),
            _text(
              'studentAddress',
              'Address',
              _address,
              255,
              keyboard: TextInputType.streetAddress,
              maxLines: 3,
            ),
            _text(
              'studentAadhaar',
              'Aadhaar number',
              _aadhaar,
              14,
              keyboard: TextInputType.number,
            ),
            const FormSection('College and stay'),
            FormDropdown<int?>(
              key: const Key('studentCollege'),
              label: 'College',
              value: _collegeId,
              enabled: !_busy,
              items: [
                // The college is optional (client decision).
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('(not entered)'),
                ),
                for (final c in widget.colleges)
                  DropdownMenuItem<int?>(
                    value: c.collegeId,
                    child: Text(c.collegeName),
                  ),
              ],
              onChanged: (v) => setState(() => _collegeId = v),
            ),
            _text('studentCourse', 'Course', _course, 100),
            _text('studentClass', 'Class', _class, 50),
            DateField(
              key: const Key('studentAdmission'),
              label: 'Admission date',
              value: _admission,
              required: true,
              enabled: !_busy,
              firstDate: DateTime(2000),
              lastDate: DateTime(today.year + 1, 12, 31),
              onChanged: (v) => setState(() => _admission = v ?? _admission),
            ),
            FormDropdown<String>(
              key: const Key('studentStatus'),
              label: 'Status',
              required: true,
              value: _status,
              enabled: !_busy,
              items: const [
                DropdownMenuItem(
                  value: StudentStatus.active,
                  child: Text('Active'),
                ),
                DropdownMenuItem(
                  value: StudentStatus.left,
                  child: Text('Left'),
                ),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            _text(
              'studentRemarks',
              'Remarks',
              _remarks,
              255,
              keyboard: TextInputType.multiline,
              maxLines: 3,
            ),
            const FormSection('Father and mother'),
            _text('fatherName', "Father's name", _fatherName, 150),
            _text(
              'fatherMobile',
              "Father's mobile",
              _fatherMobile,
              20,
              keyboard: TextInputType.phone,
            ),
            _text(
              'fatherEmail',
              "Father's email",
              _fatherEmail,
              150,
              keyboard: TextInputType.emailAddress,
            ),
            _text('motherName', "Mother's name", _motherName, 150),
            _text(
              'motherMobile',
              "Mother's mobile",
              _motherMobile,
              20,
              keyboard: TextInputType.phone,
            ),
            _text(
              'motherEmail',
              "Mother's email",
              _motherEmail,
              150,
              keyboard: TextInputType.emailAddress,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                "Invoices, receipts and fee reminders go to the father's email "
                "(the mother's when the father has none). Attendance messages "
                "go to the mother (the father when the mother has none).",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            FormMessage(_message, key: const Key('studentMessage')),
            SaveButton(
              key: const Key('saveStudent'),
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
