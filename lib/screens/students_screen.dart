import 'package:flutter/material.dart';

import '../data/college_repository.dart';
import '../data/student_repository.dart';
import '../models/college.dart';
import '../models/hostel.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'student_edit_screen.dart';

/// Students of the selected hostel (the desktop Students screen): Active and
/// Inactive tabs, search, college / course / class filters; add, view and
/// edit, delete, and make an inactive student active again.
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key, required this.hostel});

  final Hostel hostel;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsData {
  const _StudentsData(this.students, this.colleges);

  final List<Student> students;
  final List<College> colleges;
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _search = TextEditingController();
  bool _inactiveTab = false;
  String? _college;
  String? _course;
  String? _className;
  late Future<_StudentsData> _data;

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

  Future<_StudentsData> _load() async {
    final id = widget.hostel.hostelId;
    final results = await Future.wait([
      StudentRepository.instance.getForHostel(id),
      CollegeRepository.instance.getForHostel(id),
    ]);
    return _StudentsData(
      results[0] as List<Student>,
      results[1] as List<College>,
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

  StudentFilter get _filter => StudentFilter(
    search: _search.text,
    college: _college,
    course: _course,
    className: _className,
  );

  Future<void> _edit(List<College> colleges, [Student? student]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StudentEditScreen(
          hostel: widget.hostel,
          colleges: colleges,
          student: student,
        ),
      ),
    );
    if (saved == true && mounted) {
      showToast(context, student == null ? 'Student added.' : 'Student saved.');
      await _reload();
    }
  }

  Future<void> _delete(Student s) async {
    if (!await confirmDelete(
          context,
          'Delete student',
          'Delete ${s.studentName}?',
        ) ||
        !mounted) {
      return;
    }
    await _run(
      () => StudentService.delete(s.studentId),
      'Student deleted.',
      'The student could not be deleted.',
    );
  }

  Future<void> _deletePermanently(Student s) async {
    final why = await showDialog<String>(
      context: context,
      builder: (context) => _DeletePermanentlyDialog(student: s),
    );
    if (why == null || !mounted) return;
    await _run(
      () => StudentService.deletePermanently(s, why),
      '${s.studentName} was deleted permanently.',
      'The student could not be deleted.',
    );
  }

  Future<void> _makeActive(Student s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make active'),
        content: Text(
          'Make ${s.studentName} active again? A room can then '
          'be allocated from Room Allocation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmMakeActive'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Make Active'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => StudentService.makeActive(s.studentId),
      '${s.studentName} is active again.',
      'The student could not be changed.',
    );
  }

  Future<void> _run(
    Future<void> Function() action,
    String done,
    String failed,
  ) async {
    try {
      await action();
      if (!mounted) return;
      showToast(context, done);
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, '$failed $e');
    }
  }

  Future<void> _openFilters(_StudentsData data) async {
    String? college = _college, course = _course, className = _className;
    final inTab = data.students.where(
      (s) =>
          s.status ==
          (_inactiveTab ? StudentStatus.left : StudentStatus.active),
    );
    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget box(
            String key,
            String label,
            String? value,
            List<String> options,
            ValueChanged<String?> changed,
          ) => FormDropdown<String?>(
            key: Key(key),
            label: label,
            value: value,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('All ${label.toLowerCase()}s'),
              ),
              for (final o in options)
                DropdownMenuItem<String?>(value: o, child: Text(o)),
            ],
            onChanged: (v) => setSheet(() => changed(v)),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Filter students',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  box('filterCollege', 'College', college, [
                    for (final c in data.colleges) c.collegeName,
                  ], (v) => college = v),
                  box(
                    'filterCourse',
                    'Course',
                    course,
                    StudentService.distinct(inTab.map((s) => s.course)),
                    (v) => course = v,
                  ),
                  box(
                    'filterClass',
                    'Class',
                    className,
                    StudentService.distinct(inTab.map((s) => s.className)),
                    (v) => className = v,
                  ),
                  OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const Key('clearFilters'),
                        onPressed: () =>
                            setSheet(() => college = course = className = null),
                        child: const Text('Clear filters'),
                      ),
                      FilledButton(
                        key: const Key('applyFilters'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.terracotta,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Show students'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (applied == true) {
      setState(() {
        _college = college;
        _course = course;
        _className = className;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StudentsData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final filterCount = _filter.count;
        int inTab(bool inactive) => data == null
            ? 0
            : data.students
                  .where(
                    (s) =>
                        s.status ==
                        (inactive ? StudentStatus.left : StudentStatus.active),
                  )
                  .length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Students'),
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
          // Like the desktop: students are added on the Active tab.
          floatingActionButton: data == null || _inactiveTab
              ? null
              : FloatingActionButton.extended(
                  key: const Key('addStudent'),
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  onPressed: () => _edit(data.colleges),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add student'),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    key: const Key('studentTabs'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(
                          'Active (${inTab(false)})',
                          key: const Key('tabActive'),
                        ),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(
                          'Inactive (${inTab(true)})',
                          key: const Key('tabInactive'),
                        ),
                      ),
                    ],
                    selected: {_inactiveTab},
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.terracotta,
                      selectedForegroundColor: Colors.white,
                    ),
                    onSelectionChanged: (v) =>
                        setState(() => _inactiveTab = v.first),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('studentSearch'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search name or mobile',
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
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: filterCount > 0,
                      label: Text('$filterCount'),
                      backgroundColor: AppColors.terracotta,
                      child: IconButton.outlined(
                        key: const Key('openFilters'),
                        tooltip: 'Filter by college, course or class',
                        icon: const Icon(Icons.filter_list),
                        onPressed: data == null
                            ? null
                            : () => _openFilters(data),
                      ),
                    ),
                  ],
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

  Widget _buildList(AsyncSnapshot<_StudentsData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return InfoView(
        key: const Key('studentsError'),
        icon: Icons.cloud_off,
        text:
            'Could not load the students.\n${snapshot.error}\n\n'
            'Pull down to try again.',
      );
    }
    final data = snapshot.data!;
    final inTab = data.students
        .where(
          (s) =>
              s.status ==
              (_inactiveTab ? StudentStatus.left : StudentStatus.active),
        )
        .length;
    if (inTab == 0) {
      return InfoView(
        key: const Key('studentsEmpty'),
        icon: Icons.people_outline,
        text: _inactiveTab
            ? 'No inactive students. Students who leave are shown here.'
            : 'No active students yet. Tap "Add student" to add the first one.',
      );
    }
    final students = StudentService.filter(
      data.students,
      _inactiveTab,
      _filter,
    );
    return ListView.separated(
      key: const Key('studentsList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: students.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            StudentService.countText(students.length, inTab, _inactiveTab),
            key: const Key('studentCount'),
            style: const TextStyle(color: AppColors.textMuted),
          );
        }
        final s = students[i - 1];
        return _StudentCard(
          student: s,
          onEdit: () => _edit(data.colleges, s),
          onDelete: () => _delete(s),
          onMakeActive: () => _makeActive(s),
          onDeletePermanently: () => _deletePermanently(s),
        );
      },
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.onEdit,
    required this.onDelete,
    required this.onMakeActive,
    required this.onDeletePermanently,
  });

  final Student student;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDeletePermanently;
  final VoidCallback onMakeActive;

  @override
  Widget build(BuildContext context) {
    final s = student;
    final study = [
      s.collegeName,
      s.course,
      s.className,
    ].where((v) => v != null && v.isNotEmpty).join('  ·  ');
    final father = [
      s.fatherName,
      s.fatherMobile,
    ].where((v) => v != null && v.isNotEmpty).join('  ·  ');
    return Card(
      key: Key('student_${s.studentId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: s.isActive
                    ? AppColors.terracotta
                    : AppColors.tileDisabled,
                foregroundColor: Colors.white,
                child: Text(
                  s.studentName.isEmpty ? '?' : s.studentName[0].toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.studentName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (s.roomNumber != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            key: Key('studentRoom_${s.studentId}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.terracotta,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Room ${s.roomNumber}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (s.mobile != null)
                      _line(Icons.phone_outlined, s.mobile!),
                    if (study.isNotEmpty) _line(Icons.school_outlined, study),
                    if (father.isNotEmpty)
                      _line(Icons.family_restroom, 'Father: $father'),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('studentMenu_${s.studentId}'),
                tooltip: 'More',
                onSelected: (v) => switch (v) {
                  'edit' => onEdit(),
                  'delete' => onDelete(),
                  'purge' => onDeletePermanently(),
                  _ => onMakeActive(),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('View / Edit'),
                  ),
                  if (s.isActive)
                    const PopupMenuItem(value: 'delete', child: Text('Delete'))
                  else
                    const PopupMenuItem(
                      value: 'active',
                      child: Text('Make Active'),
                    ),
                  if (!s.isActive)
                    const PopupMenuItem(
                      value: 'purge',
                      child: Text('Delete Permanently'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      ],
    ),
  );
}

/// Asks for the reason before deleting an inactive student for good
/// (required); closes with the reason, or null when cancelled.
class _DeletePermanentlyDialog extends StatefulWidget {
  const _DeletePermanentlyDialog({required this.student});

  final Student student;

  @override
  State<_DeletePermanentlyDialog> createState() =>
      _DeletePermanentlyDialogState();
}

class _DeletePermanentlyDialogState extends State<_DeletePermanentlyDialog> {
  final _reason = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _delete() {
    if (_reason.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter the reason for deleting the student.';
      });
      return;
    }
    Navigator.of(context).pop(_reason.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete student permanently'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete ${widget.student.studentName} permanently? Every record '
              'of this student is removed: invoices, payments, refunds, room '
              'history, attendance and messages. This cannot be undone. Take '
              'a backup in Supabase first if you may need the records again.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('purgeReason'),
              controller: _reason,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'For example: left in 2021, records not needed',
                counterText: '',
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: const TextStyle(color: Color(0xFFC0392B)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmPurge'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
          onPressed: _delete,
          child: const Text('Delete Permanently'),
        ),
      ],
    );
  }
}
