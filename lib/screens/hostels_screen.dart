import 'package:flutter/material.dart';

import '../data/hostel_repository.dart';
import '../models/hostel.dart';
import '../services/hostel_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import 'hostel_edit_screen.dart';

/// Add, edit and delete hostels (the desktop Hostels screen).
class HostelsScreen extends StatefulWidget {
  const HostelsScreen({super.key});

  @override
  State<HostelsScreen> createState() => _HostelsScreenState();
}

class _HostelsScreenState extends State<HostelsScreen> {
  late Future<List<Hostel>> _hostels;

  @override
  void initState() {
    super.initState();
    _hostels = HostelRepository.instance.getAll();
  }

  Future<void> _reload() async {
    final next = HostelRepository.instance.getAll();
    setState(() {
      _hostels = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit([Hostel? hostel]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => HostelEditScreen(hostel: hostel)),
    );
    if (saved == true && mounted) {
      _toast(hostel == null ? 'Hostel added.' : 'Hostel saved.');
      await _reload();
    }
  }

  Future<void> _delete(Hostel hostel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete hostel'),
        content: Text('Delete the hostel "${hostel.hostelName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDelete'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC0392B),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await HostelService.delete(hostel.hostelId);
      if (!mounted) return;
      _toast('Hostel deleted.');
      await _reload();
    } on ValidationException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('The hostel could not be deleted. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hostels')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addHostel'),
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add hostel'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Hostel>>(
          future: _hostels,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Info(
                key: const Key('hostelsError'),
                text:
                    'Could not load the hostels.\n${snapshot.error}\n\n'
                    'Pull down to try again.',
              );
            }
            final hostels = snapshot.data!;
            if (hostels.isEmpty) {
              return const _Info(
                key: Key('hostelsEmpty'),
                text: 'No hostels yet. Tap "Add hostel" to add the first one.',
              );
            }
            return ListView.separated(
              key: const Key('hostelsList'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: hostels.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _HostelCard(
                hostel: hostels[i],
                onEdit: () => _edit(hostels[i]),
                onDelete: () => _delete(hostels[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HostelCard extends StatelessWidget {
  const _HostelCard({
    required this.hostel,
    required this.onEdit,
    required this.onDelete,
  });

  final Hostel hostel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (hostel.address != null) hostel.address!,
      if (hostel.phone != null) hostel.phone!,
      if (hostel.email != null) hostel.email!,
    ];
    return Card(
      key: Key('hostel_${hostel.hostelId}'),
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
                  Icons.apartment,
                  color: AppColors.terracotta,
                  size: 30,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostel.hostelName,
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Count('${hostel.collegeCount}', 'colleges'),
                        _Count('${hostel.roomCount}', 'rooms'),
                        _Count('${hostel.studentCount}', 'students'),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('hostelMenu_${hostel.hostelId}'),
                tooltip: 'More',
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.number, this.label);

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.contentBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$number $label',
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      ),
    );
  }
}

/// A message in the middle; scrollable so pull to refresh works.
class _Info extends StatelessWidget {
  const _Info({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.apartment, size: 56, color: AppColors.terracotta),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
