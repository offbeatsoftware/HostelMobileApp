import 'package:flutter/material.dart';

import '../models/hostel.dart';
import '../models/room.dart';
import '../models/sharing_type.dart';
import '../services/room_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Add or edit one room (the desktop RoomEditForm).
/// Closes with true when the room was saved.
class RoomEditScreen extends StatefulWidget {
  const RoomEditScreen({
    super.key,
    required this.hostel,
    required this.sharingTypes,
    this.room,
  });

  /// The hostel a new room is added to.
  final Hostel hostel;

  /// The hostel's Single / Double / Triple sharing types.
  final List<SharingType> sharingTypes;

  /// The room to edit, or null to add a new one.
  final Room? room;

  @override
  State<RoomEditScreen> createState() => _RoomEditScreenState();
}

class _RoomEditScreenState extends State<RoomEditScreen> {
  late final _number = TextEditingController(text: widget.room?.roomNumber);
  late final _floor = TextEditingController(text: widget.room?.floor);
  late final _remarks = TextEditingController(text: widget.room?.remarks);
  // Like the desktop: the first sharing type is chosen for a new room, but
  // boys or girls must be chosen by the admin.
  late int? _sharingTypeId =
      widget.room?.sharingTypeId ??
      (widget.sharingTypes.isEmpty
          ? null
          : widget.sharingTypes.first.sharingTypeId);
  late String? _gender = widget.room?.gender;
  late bool _isActive = widget.room?.isActive ?? true;
  String _message = '';
  bool _busy = false;

  bool get _isNew => widget.room == null;

  SharingType? get _sharingType {
    for (final type in widget.sharingTypes) {
      if (type.sharingTypeId == _sharingTypeId) return type;
    }
    return null;
  }

  @override
  void dispose() {
    _number.dispose();
    _floor.dispose();
    _remarks.dispose();
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
      await RoomService.save(
        roomId: widget.room?.roomId,
        hostelId: widget.hostel.hostelId,
        roomNumber: _number.text,
        floor: _floor.text,
        sharingTypeId: _sharingTypeId,
        gender: _gender,
        isActive: _isActive,
        remarks: _remarks.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('The room could not be saved. $e');
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
    final room = widget.room;
    final type = _sharingType;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add Room' : 'Edit Room ${room!.roomNumber}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                room != null && room.occupied > 0
                    ? 'Hostel: ${widget.hostel.hostelName}. '
                          'Beds in use now: ${room.occupied} of ${room.capacity}.'
                    : 'Hostel: ${widget.hostel.hostelName}',
                key: const Key('roomInfo'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FormTextField(
                    key: const Key('roomNumber'),
                    label: 'Room number',
                    controller: _number,
                    maxLength: 20,
                    required: true,
                    keyboard: TextInputType.text,
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FormTextField(
                    key: const Key('roomFloor'),
                    label: 'Floor',
                    controller: _floor,
                    maxLength: 20,
                    enabled: !_busy,
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<int>(
              key: const Key('roomSharing'),
              initialValue: _sharingTypeId,
              decoration: const InputDecoration(
                labelText: 'Sharing type *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                for (final t in widget.sharingTypes)
                  DropdownMenuItem(
                    value: t.sharingTypeId,
                    child: Text(t.displayName),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _sharingTypeId = value),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 14),
              child: Text(
                type == null
                    ? 'This hostel has no sharing types.'
                    : '${type.beds}. The rent is agreed per student at check-in.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const Text(
              'Room for *',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const Key('roomGender'),
              segments: const [
                ButtonSegment(
                  value: RoomGender.male,
                  label: Text('Boys'),
                  icon: Icon(Icons.man),
                ),
                ButtonSegment(
                  value: RoomGender.female,
                  label: Text('Girls'),
                  icon: Icon(Icons.woman),
                ),
              ],
              emptySelectionAllowed: true,
              selected: {if (_gender != null) _gender!},
              onSelectionChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _gender = value.isEmpty ? null : value.first,
                    ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('roomActive'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Room is active'),
              subtitle: const Text('Students can be allocated to it'),
              value: _isActive,
              activeThumbColor: AppColors.terracotta,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _isActive = value),
            ),
            const SizedBox(height: 8),
            FormTextField(
              key: const Key('roomRemarks'),
              label: 'Remarks',
              controller: _remarks,
              maxLength: 255,
              maxLines: 3,
              keyboard: TextInputType.multiline,
              enabled: !_busy,
            ),
            FormMessage(_message, key: const Key('roomMessage')),
            SaveButton(
              key: const Key('saveRoom'),
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
