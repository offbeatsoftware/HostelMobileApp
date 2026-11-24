import 'package:flutter/material.dart';

import '../models/college.dart';
import '../models/hostel.dart';
import '../services/college_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Add or edit one college (the desktop CollegeEditForm).
/// Closes with true when the college was saved.
class CollegeEditScreen extends StatefulWidget {
  const CollegeEditScreen({super.key, required this.hostel, this.college});

  /// The hostel a new college is added to.
  final Hostel hostel;

  /// The college to edit, or null to add a new one.
  final College? college;

  @override
  State<CollegeEditScreen> createState() => _CollegeEditScreenState();
}

class _CollegeEditScreenState extends State<CollegeEditScreen> {
  late final _name = TextEditingController(text: widget.college?.collegeName);
  late final _address = TextEditingController(text: widget.college?.address);
  late final _phone = TextEditingController(text: widget.college?.phone);
  String _message = '';
  bool _busy = false;

  bool get _isNew => widget.college == null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
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
      await CollegeService.save(
        collegeId: widget.college?.collegeId,
        hostelId: widget.hostel.hostelId,
        collegeName: _name.text,
        address: _address.text,
        phone: _phone.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('The college could not be saved. $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add College' : 'Edit College')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Hostel: ${widget.hostel.hostelName}',
                key: const Key('collegeHostel'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
            FormTextField(
              key: const Key('collegeName'),
              label: 'College name',
              controller: _name,
              maxLength: 150,
              required: true,
              enabled: !_busy,
            ),
            FormTextField(
              key: const Key('collegeAddress'),
              label: 'Address',
              controller: _address,
              maxLength: 255,
              maxLines: 3,
              keyboard: TextInputType.streetAddress,
              enabled: !_busy,
            ),
            FormTextField(
              key: const Key('collegePhone'),
              label: 'Phone',
              controller: _phone,
              maxLength: 20,
              keyboard: TextInputType.phone,
              enabled: !_busy,
            ),
            FormMessage(_message, key: const Key('collegeMessage')),
            SaveButton(
              key: const Key('saveCollege'),
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
