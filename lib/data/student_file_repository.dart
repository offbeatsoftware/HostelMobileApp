import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';

/// Student photos and Aadhaar card scans in the private Storage bucket
/// "student-files" (supabase/017_student_files.sql). The file names are on
/// the student (photo_path, aadhaar_card_path).
class StudentFileRepository {
  static StudentFileRepository? _testInstance;

  static StudentFileRepository get instance =>
      _testInstance ?? StudentFileRepository();

  @visibleForTesting
  static void useInstance(StudentFileRepository? repository) =>
      _testInstance = repository;

  static const bucket = 'student-files';

  Future<Uint8List> download(String name) =>
      Database.client.storage.from(bucket).download(name);

  Future<void> upload(String name, Uint8List bytes, String contentType) async {
    await Database.client.storage
        .from(bucket)
        .uploadBinary(
          name,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
  }

  Future<void> remove(List<String> names) async {
    if (names.isEmpty) return;
    await Database.client.storage.from(bucket).remove(names);
  }

  /// Saves the file names on the student; null clears one. Only the given
  /// ones are changed.
  Future<void> setPaths(
    int studentId, {
    bool photo = false,
    String? photoPath,
    bool aadhaar = false,
    String? aadhaarCardPath,
  }) async {
    final data = <String, Object?>{
      if (photo) 'photo_path': photoPath,
      if (aadhaar) 'aadhaar_card_path': aadhaarCardPath,
    };
    if (data.isEmpty) return;
    await Database.client
        .from('student')
        .update(data)
        .eq('student_id', studentId);
  }
}
