import 'package:flutter/material.dart';

import '../data/allocation_repository.dart';
import '../data/attendance_repository.dart';
import '../data/settings_repository.dart';
import '../data/student_repository.dart';
import '../models/allocation.dart';
import '../models/attendance.dart';
import '../models/hostel.dart';
import '../models/student.dart';
import '../services/attendance_service.dart';
import '../services/date_format.dart';
import '../services/document_email.dart';
import '../services/launcher.dart';
import '../services/message_text.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'document_actions.dart';

const _danger = Color(0xFFC0392B);
const _success = Color(0xFF198754);

/// Night attendance of the selected hostel (the desktop Attendance screen):
/// choose the date, mark who is absent, save; then send WhatsApp messages to
/// the parents of the absent students. Earlier dates can be corrected.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late DateTime _date = _today;
  late Future<List<AttendanceEntry>> _sheet = _load(_date);
  List<AttendanceEntry> _entries = [];
  final _remarks = <int, TextEditingController>{};
  bool _dirty = false;
  String _template = MessageText.defaultAttendanceText;
  String? _adminPhone;
  List<Student> _students = [];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _remarks.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<List<AttendanceEntry>> _load(DateTime date) async {
    final id = widget.hostel.hostelId;
    final iso = isoDate(date);
    final attendance = AttendanceRepository.instance;
    final r = await Future.wait([
      StudentRepository.instance.getForHostel(id),
      AllocationRepository.instance.getForHostel(id, includeHistory: true),
      attendance.getForDate(id, iso),
      attendance.getMessaged(id, AttendanceService.historySubject(date)),
      SettingsRepository.instance.getWhatsAppTexts(),
      SettingsRepository.instance.getAdminPhone(),
    ]);
    _template =
        (r[4] as Map<String, String>)[MessageText.attendanceKey] ??
        MessageText.defaultAttendanceText;
    _adminPhone = r[5] as String?;
    _students = r[0] as List<Student>;
    final entries = AttendanceService.buildSheet(
      date: date,
      students: r[0] as List<Student>,
      allocations: r[1] as List<RoomAllocation>,
      saved: r[2] as List<SavedAttendance>,
      messaged: r[3] as Set<int>,
    );
    for (final c in _remarks.values) {
      c.dispose();
    }
    _remarks
      ..clear()
      ..addAll({
        for (final e in entries)
          e.studentId: TextEditingController(text: e.remarks),
      });
    _entries = entries;
    _dirty = false;
    // The bottom buttons depend on the sheet, so redraw the whole screen.
    if (mounted) setState(() {});
    return entries;
  }

  Future<bool> _discardChanges() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          'The attendance of ${formatDate(_date)} has not been '
          'saved. Discard the changes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            key: const Key('discardChanges'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _goTo(DateTime date) async {
    final day = dateOnly(date);
    if (day.isAfter(_today) || day == _date) return;
    if (!await _discardChanges() || !mounted) return;
    setState(() {
      _date = day;
      _sheet = _load(day);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: _today,
      helpText: 'ATTENDANCE DATE',
    );
    if (picked != null) await _goTo(picked);
  }

  void _setPresent(AttendanceEntry e, bool present) => setState(() {
    e.isPresent = present;
    _dirty = true;
  });

  void _allPresent() => setState(() {
    for (final e in _entries.where((e) => !e.isPresent)) {
      e.isPresent = true;
      _dirty = true;
    }
  });

  Future<void> _save() async {
    if (_busy || _entries.isEmpty) return;
    FocusScope.of(context).unfocus();
    for (final e in _entries) {
      e.remarks = Validators.clean(_remarks[e.studentId]?.text);
    }
    setState(() => _busy = true);
    try {
      final absent = await AttendanceRepository.instance.save(
        widget.hostel.hostelId,
        isoDate(_date),
        _entries,
      );
      if (!mounted) return;
      showToast(
        context,
        'Attendance of ${formatDate(_date)} saved: '
        '${_entries.length - absent} present, $absent absent.',
      );
      setState(() {
        _busy = false;
        _sheet = _load(_date);
      });
    } on ValidationException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('The attendance could not be saved. $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(context, message);
  }

  Student? _student(int id) =>
      _students.where((s) => s.studentId == id).firstOrNull;

  Future<void> _email(AttendanceEntry e) async {
    final s = _student(e.studentId);
    if (s == null) return;
    await DocumentActions.absenceEmail(
      context,
      widget.hostel,
      s,
      _date,
      e.roomNumber,
      e.remarks,
    );
  }

  Future<void> _whatsApp(AttendanceEntry e) async {
    if (e.messaged) {
      final again = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            '${e.parentName} was already sent a message about '
            '${e.studentName} for ${formatDate(_date)}. Send it again?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('sendAgain'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send again'),
            ),
          ],
        ),
      );
      if (again != true) return;
    }
    final text = AttendanceService.message(
      parentName: e.parentName!,
      studentName: e.studentName,
      hostelName: widget.hostel.hostelName,
      date: _date,
      hostelPhone: widget.hostel.phone,
      adminPhone: _adminPhone,
      template: _template,
    );
    final opened = await Launcher.open(
      AttendanceService.whatsAppLink(e.parentMobile!, text),
    );
    if (!mounted) return;
    if (!opened) {
      showToast(context, 'WhatsApp could not be opened on this phone.');
      return;
    }
    try {
      await AttendanceRepository.instance.logAbsenceMessage(
        e.studentId,
        e.parentMobile!,
        isoDate(_date),
      );
      if (mounted) setState(() => e.messaged = true);
    } catch (err) {
      if (mounted) showToast(context, 'The message was not recorded. $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _discardChanges() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.hostel.hostelName,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            _dateBar(),
            Expanded(
              child: FutureBuilder<List<AttendanceEntry>>(
                future: _sheet,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return InfoView(
                      key: const Key('attendanceError'),
                      icon: Icons.cloud_off,
                      text:
                          'The attendance could not be loaded.\n'
                          '${snapshot.error}',
                    );
                  }
                  if (_entries.isEmpty) {
                    return InfoView(
                      key: const Key('attendanceEmpty'),
                      icon: Icons.bed_outlined,
                      text:
                          'No student was in a room of this hostel on '
                          '${formatDate(_date)}.',
                    );
                  }
                  return _sheetList();
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: _entries.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('allPresent'),
                          onPressed: _busy ? null : _allPresent,
                          child: const Text('Mark All Present'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: const Key('saveAttendance'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.terracotta,
                          ),
                          onPressed: _busy ? null : _save,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save Attendance'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _dateBar() {
    final isToday = _date == _today;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('previousDay'),
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goTo(_date.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: TextButton.icon(
              key: const Key('attendanceDate'),
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                formatDate(_date),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('nextDay'),
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday
                ? null
                : () => _goTo(_date.add(const Duration(days: 1))),
          ),
          TextButton(
            key: const Key('todayButton'),
            onPressed: isToday ? null : () => _goTo(_today),
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }

  Widget _sheetList() {
    final saved = _entries.any((e) => e.isSaved);
    final good = !_dirty && saved;
    final absentSaved = _entries
        .where((e) => e.isSaved && !e.isPresent)
        .toList();
    return ListView(
      key: const Key('attendanceList'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Row(
          children: [
            Icon(
              good ? Icons.check_circle : Icons.info_outline,
              size: 18,
              color: good ? _success : _danger,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                AttendanceService.status(_entries, dirty: _dirty),
                key: const Key('attendanceStatus'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: good ? _success : _danger,
                ),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 10),
          child: Text(
            'Everyone starts as present. Switch off the students '
            'who are absent, then save.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
        for (final e in _entries) _studentRow(e),
        if (saved) ...[
          const FormSection('Absent students'),
          if (absentSaved.isEmpty)
            const Text(
              'No absent students saved for this date.',
              key: Key('noAbsent'),
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            for (final e in absentSaved) _absentRow(e),
        ],
      ],
    );
  }

  Widget _studentRow(AttendanceEntry e) {
    return Card(
      key: Key('att_${e.studentId}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: e.isPresent ? null : const Color(0xFFFBE3DF),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Column(
          children: [
            InkWell(
              onTap: () => _setPresent(e, !e.isPresent),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      e.roomAndBed,
                      maxLines: 2,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.studentName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    e.isPresent ? 'Present' : 'Absent',
                    style: TextStyle(
                      color: e.isPresent ? _success : _danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Switch(
                    key: Key('present_${e.studentId}'),
                    value: e.isPresent,
                    activeThumbColor: _success,
                    onChanged: _busy ? null : (v) => _setPresent(e, v),
                  ),
                ],
              ),
            ),
            if (!e.isPresent)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 6, 6),
                child: TextField(
                  key: Key('remarks_${e.studentId}'),
                  controller: _remarks[e.studentId],
                  maxLength: 255,
                  enabled: !_busy,
                  onChanged: (_) => _dirty = true,
                  decoration: const InputDecoration(
                    hintText: 'Remarks (for example: gone home)',
                    isDense: true,
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasEmail(AttendanceEntry e) {
    final s = _student(e.studentId);
    return s != null && DocumentEmail.attendanceContact(s) != null;
  }

  Widget _absentRow(AttendanceEntry e) {
    final hasMobile = e.parentMobile != null;
    return Card(
      key: Key('absent_${e.studentId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.studentName}  ·  Room ${e.roomNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    hasMobile
                        ? '${e.parentRelation}: ${e.parentName}, +${e.parentMobile}'
                        : 'Neither the mother nor the father has a valid mobile number.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  if (e.messaged)
                    const Text(
                      'Message sent',
                      style: TextStyle(color: _success, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (_hasEmail(e))
              IconButton(
                key: Key('email_${e.studentId}'),
                tooltip: 'Email the parent',
                onPressed: () => _email(e),
                icon: const Icon(Icons.email_outlined),
              ),
            if (hasMobile)
              FilledButton.icon(
                key: Key('whatsapp_${e.studentId}'),
                style: FilledButton.styleFrom(
                  backgroundColor: e.messaged
                      ? AppColors.tileDisabled
                      : _success,
                ),
                onPressed: () => _whatsApp(e),
                icon: const Icon(Icons.chat, size: 18),
                label: Text(e.messaged ? 'Again' : 'WhatsApp'),
              ),
          ],
        ),
      ),
    );
  }
}
