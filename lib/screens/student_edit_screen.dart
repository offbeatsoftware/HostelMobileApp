import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/college.dart';
import '../models/hostel.dart';
import '../models/student.dart';
import '../services/date_format.dart';
import '../services/document_share.dart';
import '../services/student_file_service.dart';
import '../services/student_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/student_avatar.dart';

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

  // The photo and Aadhaar card chosen in this form; they are uploaded when
  // the student is saved.
  Uint8List? _newPhoto;
  bool _removePhoto = false;
  AadhaarFile? _newAadhaar;
  bool _removeAadhaar = false;

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
      final id = await StudentService.save(
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
      final problem = await _saveFiles(id);
      if (problem != null && mounted) await _filesFailed(problem);
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('The student could not be saved. $e');
    }
  }

  /// Uploads the photo and Aadhaar card; returns why it failed, or null.
  /// The student is already saved, so a failure is reported without keeping
  /// the form open (saving again would add the student twice).
  Future<String?> _saveFiles(int studentId) async {
    final changes = StudentFileChanges(
      newPhoto: _newPhoto,
      removePhoto: _removePhoto,
      newAadhaar: _newAadhaar,
      removeAadhaar: _removeAadhaar,
    );
    if (changes.isEmpty) return null;
    try {
      await StudentFileService.apply(studentId, s, changes);
      return null;
    } catch (e, stack) {
      debugPrint('Saving the student files failed: $e\n$stack');
      return StudentFileService.describeError(e);
    }
  }

  /// Tells the admin the student was saved but the files were not. A dialog,
  /// because the list screen shows its own message as soon as this one
  /// closes, which would hide a toast.
  Future<void> _filesFailed(String why) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('The photo was not saved'),
      content: SingleChildScrollView(
        child: Text(
          'The student was saved, but the photo or Aadhaar card could not '
          'be uploaded. Open the student and add it again.\n\n$why',
          key: const Key('fileProblem'),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('fileProblemOk'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  /// Runs a file choice; a refused file is shown as the form's message.
  Future<void> _choose(Future<void> Function() pick) async {
    if (_busy) return;
    try {
      await pick();
      if (mounted) setState(() => _message = '');
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('The file could not be chosen. $e');
    }
  }

  Future<void> _pickPhoto(ImageSource source) => _choose(() async {
    final photo = await StudentFileService.pickPhoto(source);
    if (photo == null) return;
    setState(() {
      _newPhoto = photo;
      _removePhoto = false;
    });
  });

  Future<void> _pickScan(ImageSource source) => _choose(() async {
    final scan = await StudentFileService.pickAadhaarImage(source);
    if (scan == null) return;
    setState(() {
      _newAadhaar = scan;
      _removeAadhaar = false;
    });
  });

  Future<void> _pickPdf() => _choose(() async {
    final scan = await StudentFileService.pickAadhaarPdf();
    if (scan == null) return;
    setState(() {
      _newAadhaar = scan;
      _removeAadhaar = false;
    });
  });

  Future<void> _viewAadhaar() async {
    final pending = _newAadhaar;
    final name = s?.aadhaarCardPath;
    final bytes = pending?.bytes ?? await StudentFileService.load(name);
    if (bytes == null) {
      if (mounted) showToast(context, 'The Aadhaar card could not be opened.');
      return;
    }
    final isPdf =
        pending?.isPdf ?? (name?.toLowerCase().endsWith('.pdf') ?? false);
    if (isPdf) {
      // The phone's own PDF viewer, through the share sheet.
      await DocumentShare.pdf(bytes, 'Aadhaar_${s?.studentId ?? 'new'}.pdf');
    } else if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PictureViewScreen(title: 'Aadhaar card', bytes: bytes),
        ),
      );
    }
  }

  bool get _hasPhoto =>
      _newPhoto != null || (!_removePhoto && s?.photoPath != null);

  bool get _hasAadhaar =>
      _newAadhaar != null || (!_removeAadhaar && s?.aadhaarCardPath != null);

  Widget _photoSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FormSection('Photo'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_newPhoto != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _newPhoto!,
                key: const Key('newPhotoPreview'),
                width: 84,
                height: 105,
                fit: BoxFit.cover,
              ),
            )
          else
            StudentAvatar(
              name: _name.text,
              photoPath: _removePhoto ? null : s?.photoPath,
              size: 96,
              onTap: (bytes) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PictureViewScreen(title: _name.text, bytes: bytes),
                ),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: const Key('takePhoto'),
                  onPressed: _busy
                      ? null
                      : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Take photo'),
                ),
                OutlinedButton.icon(
                  key: const Key('choosePhoto'),
                  onPressed: _busy
                      ? null
                      : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Choose from gallery'),
                ),
                if (_hasPhoto)
                  TextButton(
                    key: const Key('removePhoto'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _newPhoto = null;
                            _removePhoto = s?.photoPath != null;
                          }),
                    child: const Text('Remove photo'),
                  ),
              ],
            ),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 14),
        child: Text(
          'The photo is cropped to passport size and saved when you save the '
          'student. It is printed on the agreement and I-cards.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _aadhaarSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FormSection('Aadhaar card'),
      Text(
        _newAadhaar != null
            ? (_newAadhaar!.isPdf
                  ? 'A PDF is chosen (saved when you save the student).'
                  : 'A picture is chosen (saved when you save the student).')
            : _hasAadhaar
            ? 'The Aadhaar card is saved.'
            : 'No Aadhaar card saved.',
        key: const Key('aadhaarState'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          OutlinedButton(
            key: const Key('takeScan'),
            onPressed: _busy ? null : () => _pickScan(ImageSource.camera),
            child: const Text('Take photo'),
          ),
          OutlinedButton(
            key: const Key('chooseScan'),
            onPressed: _busy ? null : () => _pickScan(ImageSource.gallery),
            child: const Text('Choose image'),
          ),
          OutlinedButton(
            key: const Key('choosePdf'),
            onPressed: _busy ? null : _pickPdf,
            child: const Text('Choose PDF'),
          ),
          if (_hasAadhaar)
            OutlinedButton(
              key: const Key('viewAadhaar'),
              onPressed: _busy ? null : _viewAadhaar,
              child: const Text('View'),
            ),
          if (_hasAadhaar)
            TextButton(
              key: const Key('removeAadhaar'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _newAadhaar = null;
                      _removeAadhaar = s?.aadhaarCardPath != null;
                    }),
              child: const Text('Remove'),
            ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 14),
        child: Text(
          'A picture or a PDF, at most 5 MB. Only the signed in admin can '
          'open it.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    ],
  );

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
            _photoSection(),
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
            _aadhaarSection(),
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
