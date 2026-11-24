import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';

/// The payment QR image of the WhatsApp fee reminders, kept in the private
/// Storage bucket "payment-qr" (supabase/014_payment_qr_storage.sql). Its
/// file name is in app_setting "WhatsApp.PaymentQrCloud".
class PaymentQrRepository {
  static PaymentQrRepository? _testInstance;

  static PaymentQrRepository get instance =>
      _testInstance ?? PaymentQrRepository();

  @visibleForTesting
  static void useInstance(PaymentQrRepository? repository) =>
      _testInstance = repository;

  static const bucket = 'payment-qr';
  static const settingKey = 'WhatsApp.PaymentQrCloud';

  /// The file name of the saved QR image, or null when there is none.
  Future<String?> getName() async {
    final rows = await Database.client
        .from('app_setting')
        .select('setting_value')
        .eq('setting_key', settingKey);
    if (rows.isEmpty) return null;
    final name = (rows.first['setting_value'] as String?) ?? '';
    return name.isEmpty ? null : name;
  }

  Future<Uint8List> download(String name) =>
      Database.client.storage.from(bucket).download(name);

  /// Stores the image, makes it the QR image and deletes the old one.
  Future<void> save(String name, Uint8List bytes, String contentType) async {
    final old = await getName();
    await Database.client.storage
        .from(bucket)
        .uploadBinary(
          name,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await Database.client.from('app_setting').upsert({
      'setting_key': settingKey,
      'setting_value': name,
    }, onConflict: 'setting_key');
    if (old != null && old != name) {
      await Database.client.storage.from(bucket).remove([old]);
    }
  }

  Future<void> remove() async {
    final old = await getName();
    await Database.client.from('app_setting').upsert({
      'setting_key': settingKey,
      'setting_value': '',
    }, onConflict: 'setting_key');
    if (old != null) await Database.client.storage.from(bucket).remove([old]);
  }
}
