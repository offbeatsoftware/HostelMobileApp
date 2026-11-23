import 'package:flutter/material.dart';

import '../models/hostel.dart';
import '../services/hostel_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';

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

  Widget _field(
    String label,
    TextEditingController controller, {
    required String key,
    int maxLength = 150,
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        key: Key(key),
        controller: controller,
        enabled: !_busy,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboard,
        textCapitalization: keyboard == null
            ? TextCapitalization.words
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          counterText: '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add Hostel' : 'Edit Hostel')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(
              'Hostel name',
              _name,
              key: 'hostelName',
              required: true,
              maxLength: 150,
            ),
            _field(
              'Address',
              _address,
              key: 'hostelAddress',
              maxLength: 255,
              maxLines: 3,
              keyboard: TextInputType.streetAddress,
            ),
            _field(
              'Phone',
              _phone,
              key: 'hostelPhone',
              maxLength: 20,
              keyboard: TextInputType.phone,
            ),
            _field(
              'Email',
              _email,
              key: 'hostelEmail',
              maxLength: 150,
              keyboard: TextInputType.emailAddress,
            ),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _message,
                  key: const Key('hostelMessage'),
                  style: const TextStyle(color: Color(0xFFC0392B)),
                ),
              ),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('saveHostel'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  disabledBackgroundColor: AppColors.terracottaDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
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
