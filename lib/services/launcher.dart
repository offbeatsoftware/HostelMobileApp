import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens links outside the app (WhatsApp). The tests replace it.
class Launcher {
  static Future<bool> Function(Uri) _open = (uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<bool> open(Uri uri) => _open(uri);

  @visibleForTesting
  static void useForTests(Future<bool> Function(Uri)? open) => _open =
      open ?? (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}
