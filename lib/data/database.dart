import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../services/validators.dart';

/// Shared access to the Supabase database for the repositories.
class Database {
  /// The Supabase client; explains when the app is not set up yet.
  static SupabaseClient get client {
    if (!SupabaseConfig.isConfigured) {
      throw StateError(
        'The Supabase URL and key are not set in '
        'lib/config/supabase_config.dart.',
      );
    }
    return Supabase.instance.client;
  }

  /// Runs a database call. The database functions explain refusals with
  /// error P0001; those messages are shown to the admin as they are.
  static Future<T> run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ValidationException(e.message);
      rethrow;
    }
  }
}
