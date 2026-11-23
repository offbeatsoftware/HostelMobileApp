import '../data/hostel_repository.dart';
import 'validators.dart';

/// Hostel rules, as in the desktop HostelService. The checks here give quick
/// messages; the database checks the name and deletions again.
class HostelService {
  /// Validates and adds a hostel (hostelId null) or saves changes.
  /// Throws [ValidationException] with a message for the admin.
  static Future<int> save({
    int? hostelId,
    required String hostelName,
    String? address,
    String? phone,
    String? email,
  }) async {
    final name = Validators.clean(hostelName);
    final cleanAddress = Validators.clean(address);
    final cleanPhone = Validators.clean(phone);
    final cleanEmail = Validators.clean(email);

    if (name.isEmpty) {
      throw const ValidationException('Please enter the hostel name.');
    }
    Validators.checkLength(name, 150, 'Hostel name');
    Validators.checkLength(cleanAddress, 255, 'Address');
    Validators.checkLength(cleanPhone, 20, 'Phone');
    Validators.checkLength(cleanEmail, 150, 'Email');
    if (!Validators.isValidPhoneOrEmpty(cleanPhone)) {
      throw const ValidationException(
        'Please enter a valid phone number (digits, spaces, + and - only).',
      );
    }
    if (!Validators.isValidEmailOrEmpty(cleanEmail)) {
      throw const ValidationException(
        'Please enter a valid email address, for example office@myhostel.com.',
      );
    }

    return await HostelRepository.instance.save(
      hostelId: hostelId,
      hostelName: name,
      address: cleanAddress,
      phone: cleanPhone,
      email: cleanEmail,
    );
  }

  static Future<void> delete(int hostelId) =>
      HostelRepository.instance.delete(hostelId);
}
