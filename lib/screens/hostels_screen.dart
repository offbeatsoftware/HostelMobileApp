import 'package:flutter/material.dart';

import '../data/hostel_repository.dart';
import '../models/hostel.dart';
import '../services/hostel_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
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

  Future<void> _edit([Hostel? hostel]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => HostelEditScreen(hostel: hostel)),
    );
    if (saved == true && mounted) {
      showToast(context, hostel == null ? 'Hostel added.' : 'Hostel saved.');
      await _reload();
    }
  }

  Future<void> _delete(Hostel hostel) async {
    if (!await confirmDelete(
          context,
          'Delete hostel',
          'Delete the hostel "${hostel.hostelName}"?',
        ) ||
        !mounted) {
      return;
    }
    try {
      await HostelService.delete(hostel.hostelId);
      if (!mounted) return;
      showToast(context, 'Hostel deleted.');
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The hostel could not be deleted. $e');
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
              return InfoView(
                key: const Key('hostelsError'),
                icon: Icons.cloud_off,
                text:
                    'Could not load the hostels.\n${snapshot.error}\n\n'
                    'Pull down to try again.',
              );
            }
            final hostels = snapshot.data!;
            if (hostels.isEmpty) {
              return const InfoView(
                key: Key('hostelsEmpty'),
                icon: Icons.apartment,
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
                        CountChip(hostel.collegeCount, 'colleges'),
                        CountChip(hostel.roomCount, 'rooms'),
                        CountChip(hostel.studentCount, 'students'),
                      ],
                    ),
                  ],
                ),
              ),
              EditDeleteMenu(
                key: Key('hostelMenu_${hostel.hostelId}'),
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
