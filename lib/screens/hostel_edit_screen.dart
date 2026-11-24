import 'package:flutter/material.dart';

import '../models/hostel.dart';
import '../services/hostel_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Add or edit one hostel (the desktop HostelEditForm).
/// Closes with true when the hostel was saved.
class HostelEditScreen extends StatefulWidget {
  const HostelEditScreen({super.key, this.hostel});

  /// The hostel to edit, or null to add a new one.
  final Hostel? hostel;

  @override
  State<HostelEditScreen> createState() => _HostelEditScreenState();
}

class _HostelEditScreenState extends State<HostelEditScreen> {
  late final _name = TextEditingController(text: widget.hostel?.hostelName);
  late final _address = TextEditingController(text: widget.hostel?.address);
  late final _phone = TextEditingController(text: widget.hostel?.phone);
  late final _email = TextEditingController(text: widget.hostel?.email);
  String _message = '';
  bool _busy = false;

  bool get _isNew => widget.hostel == null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
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
      await HostelService.save(
        hostelId: widget.hostel?.hostelId,
        hostelName: _name.text,
        address: _address.text,
        phone: _phone.text,
        email: _email.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('The hostel could not be saved. $e');
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
      appBar: AppBar(title: Text(_isNew ? 'Add Hostel' : 'Edit Hostel')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormTextField(
              key: const Key('hostelName'),
              label: 'Hostel name',
              controller: _name,
              maxLength: 150,
              required: true,
              enabled: !_busy,
            ),
            FormTextField(
              key: const Key('hostelAddress'),
              label: 'Address',
              controller: _address,
              maxLength: 255,
              maxLines: 3,
              keyboard: TextInputType.streetAddress,
              enabled: !_busy,
            ),
            FormTextField(
              key: const Key('hostelPhone'),
              label: 'Phone',
              controller: _phone,
              maxLength: 20,
              keyboard: TextInputType.phone,
              enabled: !_busy,
            ),
            FormTextField(
              key: const Key('hostelEmail'),
              label: 'Email',
              controller: _email,
              maxLength: 150,
              keyboard: TextInputType.emailAddress,
              enabled: !_busy,
            ),
            FormMessage(_message, key: const Key('hostelMessage')),
            SaveButton(
              key: const Key('saveHostel'),
              busy: _busy,
              onPressed: _save,
            ),
            const SizedBox(height: 8),
            if (_isNew)
              const Text(
                'Single, Double and Triple sharing types are added to the new hostel.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
