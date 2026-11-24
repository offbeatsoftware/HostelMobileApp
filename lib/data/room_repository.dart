import 'package:flutter/foundation.dart';

import '../models/room.dart';
import '../models/sharing_type.dart';
import 'database.dart';

/// Reads and changes rooms in the Supabase database, using the functions in
/// supabase/005_room_functions.sql.
class RoomRepository {
  static RoomRepository? _testInstance;

  /// The repository the screens use.
  static RoomRepository get instance => _testInstance ?? RoomRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(RoomRepository? repository) =>
      _testInstance = repository;

  /// The hostel's rooms with beds and occupancy (in any order).
  Future<List<Room>> getForHostel(int hostelId) async {
    final rows = await Database.client
        .from('room_list')
        .select()
        .eq('hostel_id', hostelId);
    return rows.map(Room.fromMap).toList();
  }

  /// The hostel's sharing types, smallest first.
  Future<List<SharingType>> getSharingTypes(int hostelId) async {
    final rows = await Database.client
        .from('sharing_type')
        .select()
        .eq('hostel_id', hostelId)
        .order('capacity');
    return rows.map(SharingType.fromMap).toList();
  }

  /// Adds a room to the hostel (roomId null) or saves changes to an existing
  /// room, which stays in its hostel. Returns its id.
  Future<int> save({
    int? roomId,
    required int hostelId,
    required String roomNumber,
    required String floor,
    required int sharingTypeId,
    required String gender,
    required bool isActive,
    required String remarks,
  }) => Database.run(
    () async =>
        await Database.client.rpc(
              'save_room',
              params: {
                'p_room_id': roomId,
                'p_hostel_id': hostelId,
                'p_room_number': roomNumber,
                'p_floor': floor,
                'p_sharing_type_id': sharingTypeId,
                'p_gender': gender,
                'p_is_active': isActive,
                'p_remarks': remarks,
              },
            )
            as int,
  );

  /// Deletes a room that has never had a student.
  Future<void> delete(int roomId) => Database.run(() async {
    await Database.client.rpc('delete_room', params: {'p_room_id': roomId});
  });
}
