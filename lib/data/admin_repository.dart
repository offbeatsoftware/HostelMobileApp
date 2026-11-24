import 'package:flutter/foundation.dart';

import '../models/admin_user.dart';
import 'database.dart';

/// The admin row (table admin_user). Passwords are not kept here: the mobile
/// app signs in with Firebase, which holds the password.
class AdminRepository {
  static AdminRepository? _testInstance;

  static AdminRepository get instance => _testInstance ?? AdminRepository();

  @visibleForTesting
  static void useInstance(AdminRepository? repository) =>
      _testInstance = repository;

  /// The admin linked to the signed in Firebase user ([firebaseUid]); when
  /// none is linked, the first admin, as the desktop does.
  Future<AdminUser?> getCurrent(String? firebaseUid) async {
    final table = Database.client.from('admin_user');
    if (firebaseUid != null) {
      final linked = await table
          .select()
          .eq('firebase_uid', firebaseUid)
          .limit(1);
      if (linked.isNotEmpty) return AdminUser.fromMap(linked.first);
    }
    final rows = await Database.client
        .from('admin_user')
        .select()
        .order('admin_user_id')
        .limit(1);
    return rows.isEmpty ? null : AdminUser.fromMap(rows.first);
  }

  /// Saves the email and phone; empty text is stored as nothing.
  Future<AdminUser> saveContact(
    int adminUserId, {
    required String email,
    required String phone,
  }) async {
    final row = await Database.run(
      () => Database.client
          .from('admin_user')
          .update({
            'email': email.isEmpty ? null : email,
            'phone': phone.isEmpty ? null : phone,
            'updated_date': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('admin_user_id', adminUserId)
          .select()
          .single(),
    );
    return AdminUser.fromMap(row);
  }
}
