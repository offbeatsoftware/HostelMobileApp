import '../data/college_repository.dart';
import '../models/college.dart';
import 'validators.dart';

/// College rules, as in the desktop CollegeService. The checks here give
/// quick messages; the database checks the name and deletions again.
class CollegeService {
  /// Colleges whose name contains [text], ignoring capitals (all when empty).
  static List<College> filter(List<College> colleges, String? text) {
    final search = Validators.clean(text).toLowerCase();
    if (search.isEmpty) return colleges;
    return colleges
        .where((c) => c.collegeName.toLowerCase().contains(search))
        .toList();
  }

  /// Validates and adds a college to [hostelId] (collegeId null) or saves
  /// changes. Throws [ValidationException] with a message for the admin.
  static Future<int> save({
    int? collegeId,
    required int hostelId,
    required String collegeName,
    String? address,
    String? phone,
  }) async {
    final name = Validators.clean(collegeName);
    final cleanAddress = Validators.clean(address);
    final cleanPhone = Validators.clean(phone);

    if (name.isEmpty) {
      throw const ValidationException('Please enter the college name.');
    }
    Validators.checkLength(name, 150, 'College name');
    Validators.checkLength(cleanAddress, 255, 'Address');
    Validators.checkLength(cleanPhone, 20, 'Phone');
    if (!Validators.isValidPhoneOrEmpty(cleanPhone)) {
      throw const ValidationException(
        'Please enter a valid phone number (digits, spaces, + and - only).',
      );
    }

    return await CollegeRepository.instance.save(
      collegeId: collegeId,
      hostelId: hostelId,
      collegeName: name,
      address: cleanAddress,
      phone: cleanPhone,
    );
  }

  static Future<void> delete(int collegeId) =>
      CollegeRepository.instance.delete(collegeId);
}
