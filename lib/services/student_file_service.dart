import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/student_file_repository.dart';
import '../models/student.dart';
import 'validators.dart';

/// A student's Aadhaar card file ready to save: a shrunk JPG, or the PDF as
/// it is.
class AadhaarFile {
  const AadhaarFile(this.bytes, this.extension);

  final Uint8List bytes;

  /// ".jpg" or ".pdf".
  final String extension;

  bool get isPdf => extension == '.pdf';
}

/// What the admin changed about a student's files in the form. A new file
/// replaces the old one; a remove flag clears it.
class StudentFileChanges {
  const StudentFileChanges({
    this.newPhoto,
    this.removePhoto = false,
    this.newAadhaar,
    this.removeAadhaar = false,
  });

  final Uint8List? newPhoto;
  final bool removePhoto;
  final AadhaarFile? newAadhaar;
  final bool removeAadhaar;

  bool get isEmpty =>
      newPhoto == null && !removePhoto && newAadhaar == null && !removeAadhaar;
}

/// Student photos and Aadhaar card scans (the desktop StudentFileService):
/// checked as the desktop does, shrunk for the phone, kept in private
/// Storage, shown from a cache.
class StudentFileService {
  static const maxBytes = 5 * 1024 * 1024;

  /// What the phone's camera or gallery may hand over before it is shrunk.
  static const maxPickedBytes = 40 * 1024 * 1024;

  static const photoExtensions = ['.jpg', '.jpeg', '.png', '.bmp'];
  static const aadhaarExtensions = ['.jpg', '.jpeg', '.png', '.pdf'];

  /// The shape of a passport photo, as the desktop crops it (width / height).
  static const photoAspect = 84 / 105;
  static const photoWidth = 480;
  static const photoHeight = 600;
  static const aadhaarLongSide = 1600;

  // ---- checks ----

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot).toLowerCase();
  }

  static void _check(
    String fileName,
    Uint8List bytes,
    List<String> allowed,
    String description, {
    required int limit,
  }) {
    final ext = _extension(fileName);
    // A picture from the gallery may come without an extension; whether it
    // can be read is checked when it is opened.
    if (ext.isNotEmpty && !allowed.contains(ext)) {
      throw ValidationException(
        'The $description must be one of these file types: '
        '${allowed.join(', ')}.',
      );
    }
    if (bytes.isEmpty) {
      throw ValidationException('The selected $description is empty.');
    }
    if (bytes.length > limit) {
      throw ValidationException(
        'The $description is too large. The maximum size is 5 MB.',
      );
    }
  }

  // ---- shrinking (runs off the screen's thread) ----

  /// Lets the automated tests shrink on the same thread.
  @visibleForTesting
  static bool inBackground = true;

  static Future<Uint8List?> _run(
    Uint8List? Function(Uint8List) work,
    Uint8List bytes,
  ) => inBackground ? compute(work, bytes) : Future.value(work(bytes));

  /// The picture, or null when the bytes are not a readable image (the
  /// decoder can throw on damaged files).
  static img.Image? _decode(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// The photo cropped to the passport shape, 480 x 600 at most, as a JPG;
  /// null when it cannot be read.
  static Uint8List? shrinkPhoto(Uint8List bytes) {
    final decoded = _decode(bytes);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    final w = image.width;
    final h = image.height;
    final cropW = (w / h > photoAspect) ? (h * photoAspect).round() : w;
    final cropH = (w / h > photoAspect) ? h : (w / photoAspect).round();
    image = img.copyCrop(
      image,
      x: (w - cropW) ~/ 2,
      y: (h - cropH) ~/ 2,
      width: cropW,
      height: cropH,
    );
    if (image.width > photoWidth) {
      image = img.copyResize(
        image,
        width: photoWidth,
        height: photoHeight,
        interpolation: img.Interpolation.average,
      );
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  /// The scan with its long side at most 1600 pixels, as a JPG (still sharp
  /// enough to read); null when it cannot be read.
  static Uint8List? shrinkScan(Uint8List bytes) {
    final decoded = _decode(bytes);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    final longSide = image.width > image.height ? image.width : image.height;
    if (longSide > aadhaarLongSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: aadhaarLongSide)
          : img.copyResize(image, height: aadhaarLongSide);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  /// Checks a chosen photo and returns it cropped and shrunk.
  static Future<Uint8List> preparePhoto(
    String fileName,
    Uint8List bytes,
  ) async {
    _check(fileName, bytes, photoExtensions, 'photo', limit: maxPickedBytes);
    final out = await _run(shrinkPhoto, bytes);
    if (out == null) {
      throw const ValidationException(
        'The selected photo could not be read. Please choose a JPG or PNG '
        'picture.',
      );
    }
    return out;
  }

  /// Checks a chosen Aadhaar card file: a PDF is kept as it is (at most
  /// 5 MB), a picture is shrunk.
  static Future<AadhaarFile> prepareAadhaar(
    String fileName,
    Uint8List bytes,
  ) async {
    final isPdf = _extension(fileName) == '.pdf';
    _check(
      fileName,
      bytes,
      aadhaarExtensions,
      'Aadhaar card file',
      limit: isPdf ? maxBytes : maxPickedBytes,
    );
    if (isPdf) {
      final header = bytes.length >= 4
          ? String.fromCharCodes(bytes.sublist(0, 4))
          : '';
      if (header != '%PDF') {
        throw const ValidationException(
          'The selected Aadhaar card file is not a valid PDF.',
        );
      }
      return AadhaarFile(bytes, '.pdf');
    }
    final out = await _run(shrinkScan, bytes);
    if (out == null) {
      throw const ValidationException(
        'The selected Aadhaar card file could not be read. Please choose a '
        'JPG or PNG picture, or a PDF.',
      );
    }
    return AadhaarFile(out, '.jpg');
  }

  /// Why a save of the files failed, in words the admin can act on.
  static String describeError(Object error) {
    if (error is ValidationException) return error.message;
    final text = error is StorageException
        ? '${error.message} (${error.statusCode ?? 'no status'})'
        : '$error';
    final lower = text.toLowerCase();
    if (lower.contains('bucket not found') || lower.contains('404')) {
      return 'The storage folder "student-files" was not found. Run '
          'supabase/017_student_files.sql in the Supabase SQL Editor. '
          '[$text]';
    }
    if (lower.contains('row-level security') ||
        lower.contains('unauthorized') ||
        lower.contains('403') ||
        lower.contains('401')) {
      return 'Supabase Storage did not accept the admin login for '
          '"student-files". Run supabase/017_student_files.sql again and '
          'check that you are signed in as the hostel admin. [$text]';
    }
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timeout')) {
      return 'There is no internet connection, or it dropped. Try again. '
          '[$text]';
    }
    return text;
  }

  // ---- choosing files ----

  static Future<({String name, Uint8List bytes})?> Function(ImageSource)
  _pickImage = (source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 90,
    );
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  };

  static Future<({String name, Uint8List bytes})?> Function() _pickPdf =
      () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: true,
        );
        final file = result?.files.firstOrNull;
        if (file == null || file.bytes == null) return null;
        return (name: file.name, bytes: file.bytes!);
      };

  /// Lets the automated tests choose files without the phone's pickers.
  @visibleForTesting
  static void usePickers({
    Future<({String name, Uint8List bytes})?> Function(ImageSource)? image,
    Future<({String name, Uint8List bytes})?> Function()? pdf,
  }) {
    if (image != null) _pickImage = image;
    if (pdf != null) _pickPdf = pdf;
  }

  /// Takes or chooses a photo; null when cancelled.
  static Future<Uint8List?> pickPhoto(ImageSource source) async {
    final picked = await _pickImage(source);
    return picked == null ? null : preparePhoto(picked.name, picked.bytes);
  }

  /// Takes or chooses a picture of the Aadhaar card; null when cancelled.
  static Future<AadhaarFile?> pickAadhaarImage(ImageSource source) async {
    final picked = await _pickImage(source);
    return picked == null ? null : prepareAadhaar(picked.name, picked.bytes);
  }

  /// Chooses the Aadhaar card as a PDF; null when cancelled.
  static Future<AadhaarFile?> pickAadhaarPdf() async {
    final picked = await _pickPdf();
    return picked == null ? null : prepareAadhaar(picked.name, picked.bytes);
  }

  // ---- saving ----

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  /// Uploads the new files, saves their names on the student and deletes
  /// the replaced ones. A failed upload changes nothing on the student.
  static Future<void> apply(
    int studentId,
    Student? existing,
    StudentFileChanges changes, {
    DateTime? now,
  }) async {
    if (changes.isEmpty) return;
    final repo = StudentFileRepository.instance;
    final stamp = _stamp(now ?? DateTime.now());

    final uploaded = <String>[];
    String? photoName;
    String? aadhaarName;
    try {
      if (changes.newPhoto != null) {
        photoName = 'S${studentId}_photo_$stamp.jpg';
        await repo.upload(photoName, changes.newPhoto!, 'image/jpeg');
        uploaded.add(photoName);
      }
      if (changes.newAadhaar != null) {
        final a = changes.newAadhaar!;
        aadhaarName = 'S${studentId}_aadhaar_$stamp${a.extension}';
        await repo.upload(
          aadhaarName,
          a.bytes,
          a.isPdf ? 'application/pdf' : 'image/jpeg',
        );
        uploaded.add(aadhaarName);
      }
      await repo.setPaths(
        studentId,
        photo: changes.newPhoto != null || changes.removePhoto,
        photoPath: photoName,
        aadhaar: changes.newAadhaar != null || changes.removeAadhaar,
        aadhaarCardPath: aadhaarName,
      );
    } catch (_) {
      // Nothing was saved on the student: do not leave the new files behind.
      try {
        await repo.remove(uploaded);
      } catch (_) {}
      rethrow;
    }

    // The replaced files are no longer used.
    final old = [
      if (changes.newPhoto != null || changes.removePhoto) existing?.photoPath,
      if (changes.newAadhaar != null || changes.removeAadhaar)
        existing?.aadhaarCardPath,
    ].whereType<String>().toList();
    try {
      await repo.remove(old);
    } catch (_) {
      // Leftover files are harmless.
    }
  }

  /// Deletes a student's photo and Aadhaar card files (the student is gone).
  static Future<void> deleteFiles(Student student) async {
    final names = [
      student.photoPath,
      student.aadhaarCardPath,
    ].whereType<String>().toList();
    try {
      await StudentFileRepository.instance.remove(names);
    } catch (_) {
      // Leftover files are harmless.
    }
  }

  // ---- showing files ----

  static final _cache = <String, Uint8List>{};
  static const _cacheLimit = 80;

  /// The file's bytes (kept for next time: a name is never reused, so a
  /// cached file is never out of date); null when there is no file or it
  /// cannot be read.
  static Future<Uint8List?> load(String? name) async {
    if (name == null || name.isEmpty) return null;
    final cached = _cache.remove(name);
    if (cached != null) {
      _cache[name] = cached; // most recently used
      return cached;
    }
    try {
      final bytes = await StudentFileRepository.instance.download(name);
      _cache[name] = bytes;
      while (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}
