import 'package:flutter/material.dart';

import '../data/allocation_repository.dart';
import '../data/room_repository.dart';
import '../data/student_repository.dart';
import '../models/allocation.dart';
import '../models/hostel.dart';
import '../models/room.dart';
import '../models/student.dart';
import '../services/allocation_service.dart';
import '../services/date_format.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'agreement_actions.dart';
import 'allocation_form_screen.dart';

/// Room Allocation (the desktop screen): who is in which room and bed;
/// check-in with the yearly fee, transfer and check-out; full history.
class AllocationsScreen extends StatefulWidget {
  const AllocationsScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;

  /// Today's date; only the automated tests set it.
  final DateTime? today;

  @override
  State<AllocationsScreen> createState() => _AllocationsScreenState();
}

class _Data {
  const _Data(this.allocations, this.rooms, this.students);

  /// Current ones only, or the full history.
  final List<RoomAllocation> allocations;
  final List<Room> rooms;
  final List<Student> students;

  List<RoomAllocation> get current =>
      allocations.where((a) => a.isCurrent).toList();
}

class _AllocationsScreenState extends State<AllocationsScreen> {
  final _search = TextEditingController();
  bool _history = false;
  late Future<_Data> _data;

  DateTime get _today => dateOnly(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final id = widget.hostel.hostelId;
    final results = await Future.wait([
      AllocationRepository.instance.getForHostel(id, includeHistory: _history),
      RoomRepository.instance.getForHostel(id),
      StudentRepository.instance.getForHostel(id),
    ]);
    return _Data(
      AllocationService.sorted(results[0] as List<RoomAllocation>),
      results[1] as List<Room>,
      results[2] as List<Student>,
    );
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Future<void> _open(
    _Data data,
    AllocationAction action, [
    RoomAllocation? current,
  ]) async {
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AllocationFormScreen(
          action: action,
          hostel: widget.hostel,
          rooms: data.rooms,
          students: data.students,
          allocations: data.current,
          current: current,
          today: widget.today,
        ),
      ),
    );
    if (done != null && mounted) {
      showToast(context, done);
      final before = {for (final a in data.current) a.studentId};
      await _reload();
      if (action == AllocationAction.checkIn) await _offerAgreement(before);
    }
  }

  /// After a check-in: offers the residency agreement PDF of the student
  /// who is now in a room.
  Future<void> _offerAgreement(Set<int> before) async {
    _Data fresh;
    try {
      fresh = await _data;
    } catch (_) {
      return;
    }
    final added = fresh.current
        .where((a) => !before.contains(a.studentId))
        .firstOrNull;
    if (added == null || !mounted) return;
    final student = fresh.students
        .where((s) => s.studentId == added.studentId)
        .firstOrNull;
    if (student == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          '${added.studentName} is in room ${added.roomAndBed}.\n\n'
          'Create the residency agreement PDF now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const Key('makeAgreement'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create PDF'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AgreementActions.pdf(
        context,
        widget.hostel,
        student,
        today: widget.today,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Data>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Room Allocation'),
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
          floatingActionButton: data == null
              ? null
              : FloatingActionButton.extended(
                  key: const Key('checkIn'),
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  onPressed: () => _open(data, AllocationAction.checkIn),
                  icon: const Icon(Icons.login),
                  label: const Text('Check-in'),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    key: const Key('allocShow'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('In rooms now')),
                      ButtonSegment(value: true, label: Text('Full history')),
                    ],
                    selected: {_history},
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.terracotta,
                      selectedForegroundColor: Colors.white,
                    ),
                    onSelectionChanged: (v) {
                      _history = v.first;
                      _reload();
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: TextField(
                  key: const Key('allocSearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search student or room',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_search.clear),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: _buildList(snapshot),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(AsyncSnapshot<_Data> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return InfoView(
        key: const Key('allocError'),
        icon: Icons.cloud_off,
        text:
            'Could not load the room allocation.\n${snapshot.error}\n\n'
            'Pull down to try again.',
      );
    }
    final data = snapshot.data!;
    if (data.allocations.isEmpty) {
      return const InfoView(
        key: Key('allocEmpty'),
        icon: Icons.bed_outlined,
        text:
            'No student is in a room yet. Tap "Check-in" to put a student '
            'in a room.',
      );
    }
    final shown = AllocationService.search(data.allocations, _search.text);
    final count = data.current.length;
    return ListView.separated(
      key: const Key('allocList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: shown.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            '$count ${count == 1 ? 'student' : 'students'} in rooms now'
            '${_history ? '  ·  ${data.allocations.length} records' : ''}',
            key: const Key('allocCount'),
            style: const TextStyle(color: AppColors.textMuted),
          );
        }
        final a = shown[i - 1];
        return _AllocationCard(
          allocation: a,
          today: _today,
          onTransfer: () => _open(data, AllocationAction.transfer, a),
          onCheckOut: () => _open(data, AllocationAction.checkOut, a),
        );
      },
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({
    required this.allocation,
    required this.today,
    required this.onTransfer,
    required this.onCheckOut,
  });

  final RoomAllocation allocation;
  final DateTime today;
  final VoidCallback onTransfer;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    final a = allocation;
    final days = a.days(today);
    final when = a.isCurrent
        ? 'Since ${formatDate(a.checkInDate)}  ·  $days ${days == 1 ? 'day' : 'days'}'
        : '${formatDate(a.checkInDate)} to ${formatDate(a.checkOutDate!)}'
              '  ·  ${a.statusText}';
    return Card(
      key: Key('alloc_${a.allocationId}'),
      margin: EdgeInsets.zero,
      color: a.isCurrent ? null : const Color(0xFFEDE8DF),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 8),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: a.isCurrent
                    ? AppColors.terracotta
                    : AppColors.tileDisabled,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    a.roomNumber,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (a.bedNumber != null)
                    Text(
                      'Bed ${a.bedNumber}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.studentName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (a.studentMobile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        a.studentMobile!,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      when,
                      key: Key('allocWhen_${a.allocationId}'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (a.remarks != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        a.remarks!,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (a.isCurrent)
              PopupMenuButton<String>(
                key: Key('allocMenu_${a.allocationId}'),
                tooltip: 'More',
                onSelected: (v) =>
                    v == 'transfer' ? onTransfer() : onCheckOut(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'transfer', child: Text('Transfer')),
                  PopupMenuItem(value: 'checkout', child: Text('Check-out')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
