import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// A file to hand to the share sheet.
typedef SharedFile = ({String name, Uint8List bytes});

/// Hands files and text to the phone's share sheet: save or print a PDF,
/// send it on WhatsApp, or attach PDFs to a mail with the subject and text
/// filled in.
class DocumentShare {
  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  static Future<void> _defaultShare(
    List<SharedFile> files,
    String? subject,
    String? text,
  ) => SharePlus.instance.share(
    ShareParams(
      files: files.isEmpty
          ? null
          : [
              for (final f in files)
                XFile.fromData(f.bytes, mimeType: _mime(f.name), name: f.name),
            ],
      fileNameOverrides: files.isEmpty ? null : [for (final f in files) f.name],
      subject: subject,
      text: text,
    ),
  );

  static Future<void> Function(
    List<SharedFile> files,
    String? subject,
    String? text,
  )
  _share = _defaultShare;

  static Future<void> _defaultImage(Uint8List bytes, String name) =>
      _defaultShare([(name: name, bytes: bytes)], null, null);

  static Future<void> Function(Uint8List bytes, String fileName) _shareImage =
      _defaultImage;

  /// The payment QR image, to send in a WhatsApp chat.
  static Future<void> image(Uint8List bytes, String fileName) =>
      _shareImage(bytes, fileName);

  static Future<void> pdf(Uint8List bytes, String fileName) =>
      _share([(name: fileName, bytes: bytes)], null, null);

  /// A mail with one PDF attached.
  static Future<void> email(
    Uint8List bytes,
    String fileName,
    String subject,
    String body,
  ) => _share([(name: fileName, bytes: bytes)], subject, body);

  /// A mail with several PDFs attached (none: text only).
  static Future<void> emailFiles(
    List<SharedFile> files,
    String subject,
    String body,
  ) => _share(files, subject, body);

  /// Lets the automated tests record what would be shared.
  @visibleForTesting
  static void useForTests(
    Future<void> Function(List<SharedFile>, String?, String?)? share, {
    Future<void> Function(Uint8List, String)? shareImage,
  }) {
    _share = share ?? _defaultShare;
    _shareImage = shareImage ?? _defaultImage;
  }
}
