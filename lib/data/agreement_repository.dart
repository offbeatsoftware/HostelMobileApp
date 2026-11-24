import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';

/// The agreement text (app_setting "Agreement.Text"), the signing date and
/// witness (table agreement_signing) and the signature images (Storage
/// bucket "signatures"), from supabase/016_agreement.sql.
class AgreementRepository {
  static AgreementRepository? _testInstance;

  static AgreementRepository get instance =>
      _testInstance ?? AgreementRepository();

  @visibleForTesting
  static void useInstance(AgreementRepository? repository) =>
      _testInstance = repository;

  static const bucket = 'signatures';
  static const textKey = 'Agreement.Text';

  /// The saved agreement text, or null when none was saved.
  Future<String?> getTemplate() async {
    final rows = await Database.client
        .from('app_setting')
        .select('setting_value')
        .eq('setting_key', textKey);
    if (rows.isEmpty) return null;
    final text = (rows.first['setting_value'] as String?) ?? '';
    return text.trim().isEmpty ? null : text;
  }

  Future<void> saveTemplate(String text) async {
    await Database.client.from('app_setting').upsert({
      'setting_key': textKey,
      'setting_value': text,
    }, onConflict: 'setting_key');
  }

  /// When the student's agreement was signed and the witness's name.
  Future<({DateTime date, String witness})?> getSigning(int studentId) async {
    final rows = await Database.client
        .from('agreement_signing')
        .select('signed_date, witness_name')
        .eq('student_id', studentId);
    if (rows.isEmpty) return null;
    return (
      date: DateTime.parse(rows.first['signed_date'] as String),
      witness: (rows.first['witness_name'] as String?) ?? '',
    );
  }

  Future<void> saveSigning(
    int studentId,
    String signedDate,
    String witnessName,
  ) async {
    await Database.client.from('agreement_signing').upsert({
      'student_id': studentId,
      'signed_date': signedDate,
      'witness_name': witnessName.isEmpty ? null : witnessName,
    }, onConflict: 'student_id');
  }

  /// The names of the stored files that start with [prefix].
  Future<Set<String>> listNames(String prefix) async {
    final files = await Database.client.storage
        .from(bucket)
        .list(searchOptions: SearchOptions(search: prefix, limit: 100));
    return {
      for (final f in files)
        if (f.name.startsWith(prefix)) f.name,
    };
  }

  Future<Uint8List> download(String name) =>
      Database.client.storage.from(bucket).download(name);

  Future<void> upload(String name, Uint8List bytes) async {
    await Database.client.storage
        .from(bucket)
        .uploadBinary(
          name,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
  }

  Future<void> remove(List<String> names) async {
    if (names.isEmpty) return;
    await Database.client.storage.from(bucket).remove(names);
  }
}
