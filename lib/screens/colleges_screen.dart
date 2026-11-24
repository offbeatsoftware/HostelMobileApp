import 'package:flutter/material.dart';

import '../data/college_repository.dart';
import '../models/college.dart';
import '../models/hostel.dart';
import '../services/college_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'college_edit_screen.dart';

/// Colleges whose students stay in the selected hostel (the desktop
/// Colleges screen): search, add, edit and delete.
class CollegesScreen extends StatefulWidget {
  const CollegesScreen({super.key, required this.hostel});

  final Hostel hostel;

  @override
  State<CollegesScreen> createState() => _CollegesScreenState();
}

class _CollegesScreenState extends State<CollegesScreen> {
  final _search = TextEditingController();
  late Future<List<College>> _colleges;

  @override
  void initState() {
    super.initState();
    _colleges = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<College>> _load() =>
      CollegeRepository.instance.getForHostel(widget.hostel.hostelId);

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _colleges = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Future<void> _edit([College? college]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CollegeEditScreen(hostel: widget.hostel, college: college),
      ),
    );
    if (saved == true && mounted) {
      showToast(context, college == null ? 'College added.' : 'College saved.');
      await _reload();
    }
  }

  Future<void> _delete(College college) async {
    if (!await confirmDelete(
          context,
          'Delete college',
          'Delete the college "${college.collegeName}"?',
        ) ||
        !mounted) {
      return;
    }
    try {
      await CollegeService.delete(college.collegeId);
      if (!mounted) return;
      showToast(context, 'College deleted.');
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The college could not be deleted. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Colleges'),
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addCollege'),
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add college'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: TextField(
              key: const Key('collegeSearch'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search college name',
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
              child: FutureBuilder<List<College>>(
                future: _colleges,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return InfoView(
                      key: const Key('collegesError'),
                      icon: Icons.cloud_off,
                      text:
                          'Could not load the colleges.\n${snapshot.error}'
                          '\n\nPull down to try again.',
                    );
                  }
                  final all = snapshot.data!;
                  if (all.isEmpty) {
                    return const InfoView(
                      key: Key('collegesEmpty'),
                      icon: Icons.school_outlined,
                      text:
                          'No colleges yet. Tap "Add college" to add the '
                          'first one.',
                    );
                  }
                  final colleges = CollegeService.filter(all, _search.text);
                  if (colleges.isEmpty) {
                    return InfoView(
                      key: const Key('collegesNoMatch'),
                      icon: Icons.search_off,
                      text:
                          'No college name contains "${_search.text.trim()}".',
                    );
                  }
                  return ListView.separated(
                    key: const Key('collegesList'),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: colleges.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _CollegeCard(
                      college: colleges[i],
                      onEdit: () => _edit(colleges[i]),
                      onDelete: () => _delete(colleges[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollegeCard extends StatelessWidget {
  const _CollegeCard({
    required this.college,
    required this.onEdit,
    required this.onDelete,
  });

  final College college;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (college.address != null) college.address!,
      if (college.phone != null) college.phone!,
    ];
    return Card(
      key: Key('college_${college.collegeId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 14),
                child: Icon(
                  Icons.school_outlined,
                  color: AppColors.terracotta,
                  size: 30,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      college.collegeName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final line in details)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          line,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    const SizedBox(height: 8),
                    CountChip(college.studentCount, 'students'),
                  ],
                ),
              ),
              EditDeleteMenu(
                key: Key('collegeMenu_${college.collegeId}'),
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
