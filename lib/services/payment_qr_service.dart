import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../data/payment_qr_repository.dart';
import 'validators.dart';

/// The saved payment QR image.
class PaymentQr {
  const PaymentQr(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// The payment QR image of the WhatsApp fee reminders, with the desktop's
/// checks (PNG or JPG, at most 5 MB, a readable image).
class PaymentQrService {
  static const maxBytes = 5 * 1024 * 1024;

  /// The saved QR image, or null when there is none.
  static Future<PaymentQr?> get() async {
    final repo = PaymentQrRepository.instance;
    final name = await repo.getName();
    if (name == null) return null;
    return PaymentQr(name, await repo.download(name));
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot).toLowerCase();
  }

  /// "image/png" or "image/jpeg" for the file name.
  static String contentType(String fileName) =>
      _extension(fileName) == '.png' ? 'image/png' : 'image/jpeg';

  /// Checks the chosen file as the desktop does before saving.
  static void validate(String fileName, Uint8List bytes) {
    if (!['.png', '.jpg', '.jpeg'].contains(_extension(fileName))) {
      throw const ValidationException(
        'Please choose the QR code as a PNG or JPG image.',
      );
    }
    if (bytes.length > maxBytes) {
      throw const ValidationException(
        'The QR image is larger than 5 MB. Please choose a smaller image.',
      );
    }
    final png =
        bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final jpg =
        bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    if (!png && !jpg) {
      throw const ValidationException('The QR file is not a readable image.');
    }
  }

  /// Saves a new QR image (replacing the old one) and returns it.
  static Future<PaymentQr> save(String fileName, Uint8List bytes) async {
    validate(fileName, bytes);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ext = _extension(fileName) == '.png' ? '.png' : '.jpg';
    final name =
        'PaymentQR_${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}$ext';
    await PaymentQrRepository.instance.save(name, bytes, contentType(name));
    return PaymentQr(name, bytes);
  }

  static Future<void> remove() => PaymentQrRepository.instance.remove();

  static Future<({String name, Uint8List bytes})?> Function() _pick = () async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  };

  /// Lets the admin pick the QR image from the phone's pictures; null when
  /// cancelled.
  static Future<({String name, Uint8List bytes})?> pick() => _pick();

  @visibleForTesting
  static void usePicker(
    Future<({String name, Uint8List bytes})?> Function()? picker,
  ) {
    _pick =
        picker ??
        () async {
          final file = await ImagePicker().pickImage(
            source: ImageSource.gallery,
          );
          if (file == null) return null;
          return (name: file.name, bytes: await file.readAsBytes());
        };
  }
}
