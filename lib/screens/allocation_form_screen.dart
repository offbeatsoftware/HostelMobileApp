import 'package:flutter/material.dart';

import '../data/allocation_repository.dart';
import '../models/allocation.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/room.dart';
import '../models/student.dart';
import '../services/allocation_service.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

enum AllocationAction { checkIn, transfer, checkOut }

/// Check-in, transfer or check-out of one student (the desktop
/// AllocationForm). Closes with a message when it was saved.
class AllocationFormScreen extends StatefulWidget {
  const AllocationFormScreen({
    super.key,
    required this.action,
    required this.hostel,
    required this.rooms,
    required this.students,
    required this.allocations,
    this.current,
    this.today,
  });

  final AllocationAction action;
  final Hostel hostel;

  /// The hostel's rooms with occupancy.
  final List<Room> rooms;

  /// The hostel's students.
  final List<Student> students;

  /// The hostel's current allocations (beds taken).
  final List<RoomAllocation> allocations;

  /// The student's current allocation, for transfer and check-out.
  final RoomAllocation? current;

  /// Today's date; only the automated tests set it.
  final DateTime? today;

  @override
  State<AllocationFormScreen> createState() => _AllocationFormScreenState();
}

class _AllocationFormScreenState extends State<AllocationFormScreen> {
  final _remarks = TextEditingController();
  final _rent = TextEditingController();
  final _transport = TextEditingController();
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late DateTime _date = _today;
  Student? _student;
  Room? _room;
  int? _bed;
  bool _waive = false;

  /// The academic year's start month and the student's invoices, loaded
  /// when a student is known.
  int? _startMonth;
  List<Invoice>? _invoices;
  String _message = '';
  bool _busy = false;

  AllocationAction get _action => widget.action;

  @override
  void initState() {
    super.initState();
    _rent.addListener(() => setState(() {}));
    _transport.addListener(() => setState(() {}));
    if (widget.current != null) {
      _student = widget.students
          .where((s) => s.studentId == widget.current!.studentId)
          .firstOrNull;
      _loadStudentFees(widget.current!.studentId);
    }
  }

  @override
  void dispose() {
    _remarks.dispose();
    _rent.dispose();
    _transport.dispose();
    super.dispose();
  }

  Future<void> _loadStudentFees(int studentId) async {
    setState(() => _invoices = null);
    try {
      final repo = AllocationRepository.instance;
      final results = await Future.wait([
        repo.getAcademicYearStartMonth(),
        repo.getInvoicesForStudent(studentId),
      ]);
      if (!mounted || (_student != null && _student!.studentId != studentId)) {
        return;
      }
      setState(() {
        _startMonth = results[0] as int;
        _invoices = results[1] as List<Invoice>;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'The fees could not be loaded. $e');
      }
    }
  }

  List<Room> get _roomChoices => AllocationService.roomsFor(
    widget.rooms,
    _student?.gender,
    exceptRoomId: widget.current?.roomId,
  );

  int? get _year =>
      _startMonth == null ? null : AcademicYear.of(_date, _startMonth!);

  Invoice? get _existingFee => _invoices == null || _year == null
      ? null
      : AllocationService.feeForYear(_invoices!, _year!);

  void _chooseStudent(Student? s) {
    setState(() {
      _student = s;
      _room = null;
      _bed = null;
      _message = '';
      if (s != null) {
        if (!RoomGender.all.contains(s.gender)) {
          _message =
              "Set ${s.studentName}'s gender on the Students screen first.";
        } else if (_roomChoices.isEmpty) {
          _message = AllocationService.explainNoRoom(widget.rooms, s);
        }
      }
    });
    if (s != null) _loadStudentFees(s.studentId);
  }

  void _chooseRoom(Room? r) {
    setState(() {
      _room = r;
      final beds = r == null
          ? const <int>[]
          : AllocationService.freeBeds(r, widget.allocations);
      _bed = beds.isEmpty ? null : beds.first;
    });
  }

  Future<bool> _confirm(String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmAllocation'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _message = '');
    final current = widget.current;
    try {
      late final String done;
      switch (_action) {
        case AllocationAction.checkIn:
          YearFee? fee;
          if (_student != null && _room != null) {
            if (_invoices == null) {
              throw const ValidationException(
                'Please wait while the fee for the year is loaded.',
              );
            }
            if (_existingFee == null) {
              fee = AllocationService.readFee(_rent.text, _transport.text);
            }
          }
          setState(() => _busy = true);
          await AllocationService.checkIn(
            student: _student,
            room: _room,
            date: _date,
            today: _today,
            remarks: _remarks.text,
            bed: _bed,
            fee: fee,
          );
          done =
              '${_student!.studentName} is in room ${_room!.roomNumber}'
              '${_bed == null ? '' : ', bed $_bed'}.';
        case AllocationAction.transfer:
          if (_room == null) {
            throw const ValidationException('Please select the room.');
          }
          if (!await _confirm(
            'Move ${current!.studentName} from room '
            '${current.roomNumber} to room ${_room!.roomNumber} on '
            '${formatDate(_date)}?',
          )) {
            return;
          }
          setState(() => _busy = true);
          await AllocationService.transfer(
            current: current,
            newRoom: _room,
            date: _date,
            today: _today,
            remarks: _remarks.text,
            bed: _bed,
          );
          done = '${current.studentName} moved to room ${_room!.roomNumber}.';
        case AllocationAction.checkOut:
          if (!await _confirm(
            'Check out ${current!.studentName} from room '
            '${current.roomNumber} on ${formatDate(_date)}? The student\'s '
            'status will be set to Left.'
            '${_waive ? ' The pending fee will be waived.' : ''}',
          )) {
            return;
          }
          setState(() => _busy = true);
          await AllocationService.checkOut(
            current: current,
            date: _date,
            today: _today,
            remarks: _remarks.text,
            waivePending: _waive,
          );
          done = '${current.studentName} checked out.';
      }
      if (mounted) Navigator.of(context).pop(done);
    } on ValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('It could not be saved. $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  Widget _info(String label, String value, {Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value, key: key),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final title = switch (_action) {
      AllocationAction.checkIn => 'Check-in',
      AllocationAction.transfer => 'Transfer',
      AllocationAction.checkOut => 'Check-out',
    };
    final dateLabel = switch (_action) {
      AllocationAction.checkIn => 'Check-in date',
      AllocationAction.transfer => 'Transfer date',
      AllocationAction.checkOut => 'Check-out date',
    };
    final freeBeds = _room == null
        ? const <int>[]
        : AllocationService.freeBeds(_room!, widget.allocations);
    final candidates = AllocationService.studentsWithoutRoom(
      widget.students,
      widget.allocations,
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_action == AllocationAction.checkIn)
              FormDropdown<int>(
                key: const Key('allocStudent'),
                label: 'Student',
                required: true,
                value: _student?.studentId,
                enabled: !_busy,
                items: [
                  for (final s in candidates)
                    DropdownMenuItem(
                      value: s.studentId,
                      child: Text(s.studentName),
                    ),
                ],
                onChanged: (id) => _chooseStudent(
                  candidates.where((s) => s.studentId == id).firstOrNull,
                ),
              )
            else ...[
              _info('Student', current!.studentName),
              _info(
                'Current room',
                current.roomAndBed,
                key: const Key('allocCurrentRoom'),
              ),
            ],
            if (_action != AllocationAction.checkOut) ...[
              FormDropdown<int>(
                key: ValueKey('allocRoom_${_student?.studentId}'),
                label: _action == AllocationAction.transfer
                    ? 'New room'
                    : 'Room',
                required: true,
                value: _room?.roomId,
                enabled: !_busy && _student != null,
                items: [
                  for (final r in _roomChoices)
                    DropdownMenuItem(
                      value: r.roomId,
                      child: Text(
                        '${r.roomNumber} (${r.sharingName}, '
                        '${r.available} free ${r.available == 1 ? 'bed' : 'beds'})',
                      ),
                    ),
                ],
                onChanged: (id) => _chooseRoom(
                  _roomChoices.where((r) => r.roomId == id).firstOrNull,
                ),
              ),
              FormDropdown<int>(
                key: ValueKey('allocBed_${_room?.roomId}'),
                label: 'Bed',
                required: true,
                value: _bed,
                enabled: !_busy && _room != null,
                items: [
                  for (final b in freeBeds)
                    DropdownMenuItem(value: b, child: Text('Bed $b')),
                ],
                onChanged: (b) => setState(() => _bed = b),
              ),
            ],
            DateField(
              key: const Key('allocDate'),
              label: dateLabel,
              value: _date,
              required: true,
              enabled: !_busy,
              firstDate: DateTime(2000),
              lastDate: _today,
              onChanged: (d) => setState(() => _date = d ?? _date),
            ),
            FormTextField(
              key: const Key('allocRemarks'),
              label: 'Remarks',
              controller: _remarks,
              maxLength: 255,
              maxLines: 2,
              keyboard: TextInputType.multiline,
              enabled: !_busy,
            ),
            if (_action == AllocationAction.checkIn && _student != null)
              _buildFee(),
            if (_action == AllocationAction.checkOut) _buildPending(),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(switch (_action) {
                AllocationAction.transfer =>
                  'The student leaves the current room and enters the new room on this date.',
                AllocationAction.checkOut =>
                  "The student's status will be set to Left.",
                AllocationAction.checkIn =>
                  "Only active rooms for the student's gender with a free bed "
                      'are listed. The fee is for the academic year of the '
                      'check-in date; the student can pay it in any number '
                      'of payments.',
              }, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
            FormMessage(_message, key: const Key('allocMessage')),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('saveAllocation'),
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
                    : Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFee() {
    if (_invoices == null || _startMonth == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: LinearProgressIndicator(),
      );
    }
    final yearText = AcademicYear.label(_year!, _startMonth!);
    final existing = _existingFee;
    if (existing != null) {
      return _info(
        'Fee for $yearText',
        '${Money.format(existing.totalAmount)} (already set, invoice '
            '${existing.invoiceNumber})',
        key: const Key('allocExistingFee'),
      );
    }
    final rent = Money.tryParse(_rent.text);
    final transport = _transport.text.trim().isEmpty
        ? 0.0
        : Money.tryParse(_transport.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSection('Fee for $yearText'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FormTextField(
                key: const Key('allocRent'),
                label: 'Room rent / year',
                controller: _rent,
                maxLength: 15,
                required: true,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                enabled: !_busy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FormTextField(
                key: const Key('allocTransport'),
                label: 'Transport / year',
                controller: _transport,
                maxLength: 15,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                enabled: !_busy,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            rent != null && transport != null
                ? 'Total fee: ${Money.format(rent + transport)} for $yearText'
                : 'Total fee: enter the room rent (transport: 0 or empty if none)',
            key: const Key('allocFeeTotal'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildPending() {
    if (_invoices == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: LinearProgressIndicator(),
      );
    }
    final pending = AllocationService.pendingFee(_invoices!);
    if (pending <= 0) return const SizedBox.shrink();
    // Check-out is allowed with a fee pending (client decision): keep it to
    // collect later, or waive the rest.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _info(
          'Fee pending',
          Money.format(pending),
          key: const Key('allocPending'),
        ),
        RadioGroup<bool>(
          groupValue: _waive,
          onChanged: (v) => setState(() => _waive = v ?? false),
          child: const Column(
            children: [
              RadioListTile<bool>(
                key: Key('keepPending'),
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text('Keep it pending'),
                subtitle: Text('It can still be collected and reminded'),
              ),
              RadioListTile<bool>(
                key: Key('waivePending'),
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text('Waive it'),
                subtitle: Text('The fee is reduced to what was paid'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
