import 'package:flutter/material.dart';

import '../data/room_repository.dart';
import '../models/hostel.dart';
import '../models/room.dart';
import '../models/sharing_type.dart';
import '../services/room_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'room_edit_screen.dart';

const _danger = Color(0xFFC0392B);

/// Rooms of the selected hostel (the desktop Rooms screen): sharing (number
/// of beds), boys or girls, occupancy and free beds; add, edit and delete.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key, required this.hostel});

  final Hostel hostel;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsData {
  const _RoomsData(this.rooms, this.sharingTypes);

  final List<Room> rooms;
  final List<SharingType> sharingTypes;
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _search = TextEditingController();
  RoomFilter _filter = RoomFilter.all;
  late Future<_RoomsData> _data;

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

  Future<_RoomsData> _load() async {
    final repo = RoomRepository.instance;
    final id = widget.hostel.hostelId;
    final results = await Future.wait([
      repo.getForHostel(id),
      repo.getSharingTypes(id),
    ]);
    return _RoomsData(
      RoomService.sorted(results[0] as List<Room>),
      results[1] as List<SharingType>,
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

  Future<void> _edit(List<SharingType> types, [Room? room]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RoomEditScreen(
          hostel: widget.hostel,
          sharingTypes: types,
          room: room,
        ),
      ),
    );
    if (saved == true && mounted) {
      if (room == null) {
        // Like the desktop: show the whole list so the new room is visible.
        _search.clear();
        _filter = RoomFilter.all;
      }
      showToast(context, room == null ? 'Room added.' : 'Room saved.');
      await _reload();
    }
  }

  Future<void> _delete(Room room) async {
    if (!await confirmDelete(
          context,
          'Delete room',
          'Delete room ${room.roomNumber}?',
        ) ||
        !mounted) {
      return;
    }
    try {
      await RoomService.delete(room.roomId);
      if (!mounted) return;
      showToast(context, 'Room deleted.');
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The room could not be deleted. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RoomsData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Rooms'),
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
                  key: const Key('addRoom'),
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  onPressed: () => _edit(data.sharingTypes),
                  icon: const Icon(Icons.add),
                  label: const Text('Add room'),
                ),
          body: Column(
            children: [
              if (data != null && data.rooms.isNotEmpty)
                Container(
                  key: const Key('roomSummary'),
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    RoomService.summary(data.rooms),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('roomSearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search room number or floor',
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final f in RoomFilter.values)
                      ChoiceChip(
                        key: Key('roomFilter_${f.name}'),
                        label: Text(f.label),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selected: _filter == f,
                        selectedColor: AppColors.terracotta,
                        labelStyle: TextStyle(
                          color: _filter == f
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setState(() => _filter = f),
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

  Widget _buildList(AsyncSnapshot<_RoomsData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return InfoView(
        key: const Key('roomsError'),
        icon: Icons.cloud_off,
        text:
            'Could not load the rooms.\n${snapshot.error}\n\n'
            'Pull down to try again.',
      );
    }
    final data = snapshot.data!;
    if (data.rooms.isEmpty) {
      return const InfoView(
        key: Key('roomsEmpty'),
        icon: Icons.meeting_room_outlined,
        text: 'No rooms yet. Tap "Add room" to add the first one.',
      );
    }
    final rooms = RoomService.filter(data.rooms, _search.text, _filter);
    if (rooms.isEmpty) {
      return const InfoView(
        key: Key('roomsNoMatch'),
        icon: Icons.search_off,
        text: 'No rooms match the search and filter.',
      );
    }
    return ListView.separated(
      key: const Key('roomsList'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _RoomCard(
        room: rooms[i],
        onEdit: () => _edit(data.sharingTypes, rooms[i]),
        onDelete: () => _delete(rooms[i]),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.onEdit,
    required this.onDelete,
  });

  final Room room;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = !room.isActive;
    final full = room.isActive && room.available == 0;
    return Card(
      key: Key('room_${room.roomId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: muted ? const Color(0xFFEDE8DF) : null,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 10),
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: muted ? AppColors.tileDisabled : AppColors.terracotta,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      room.roomNumber,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (room.floor != null)
                      Text(
                        room.floor!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                      '${room.roomFor}  ·  ${room.sharingName} sharing',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: muted
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      muted
                          ? 'Inactive  ·  ${room.capacity} '
                                '${room.capacity == 1 ? 'bed' : 'beds'}'
                          : '${room.occupied} of ${room.capacity} '
                                '${room.capacity == 1 ? 'bed' : 'beds'} used  ·  '
                                '${full ? 'Full' : '${room.available} free'}',
                      key: Key('roomBeds_${room.roomId}'),
                      style: TextStyle(
                        color: muted
                            ? AppColors.textMuted
                            : (full ? _danger : AppColors.textPrimary),
                        fontWeight: full ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (room.remarks != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          room.remarks!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              EditDeleteMenu(
                key: Key('roomMenu_${room.roomId}'),
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
