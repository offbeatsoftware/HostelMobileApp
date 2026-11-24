import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a PDF to the phone's share sheet: to save or print it, send it on
/// WhatsApp, or (with [email]) attach it to a mail with the subject and text
/// filled in.
class DocumentShare {
  static Future<void> Function(
    Uint8List bytes,
    String fileName,
    String? subject,
    String? text,
  )
  _share = (bytes, name, subject, text) => SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      fileNameOverrides: [name],
      subject: subject,
      text: text,
    ),
  );

  static Future<void> pdf(Uint8List bytes, String fileName) =>
      _share(bytes, fileName, null, null);

  static Future<void> email(
    Uint8List bytes,
    String fileName,
    String subject,
    String body,
  ) => _share(bytes, fileName, subject, body);

  /// Lets the automated tests record what would be shared.
  @visibleForTesting
  static void useForTests(
    Future<void> Function(Uint8List, String, String?, String?)? share,
  ) {
    _share =
        share ??
        (bytes, name, subject, text) => SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(bytes, mimeType: 'application/pdf', name: name),
            ],
            fileNameOverrides: [name],
            subject: subject,
            text: text,
          ),
        );
  }
}
