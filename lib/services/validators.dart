/// A problem the admin can fix, shown as a message on the screen.
class ValidationException implements Exception {
  const ValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Input checks, the same rules as the desktop Validators class.
class Validators {
  /// Removes spaces at the start and end; null becomes empty.
  static String clean(String? text) => text?.trim() ?? '';

  /// Throws when the text is longer than the database column allows.
  static void checkLength(String value, int maxLength, String fieldName) {
    if (value.length > maxLength) {
      throw ValidationException(
        '$fieldName can be at most $maxLength characters.',
      );
    }
  }

  /// Empty is allowed; otherwise digits, spaces, + - ( ) with 6 to 15 digits.
  static bool isValidPhoneOrEmpty(String phone) {
    if (phone.isEmpty) return true;
    if (!RegExp(r'^[0-9+\-() ]+$').hasMatch(phone)) return false;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '').length;
    return digits >= 6 && digits <= 15;
  }

  /// Empty is allowed; otherwise one address like name@example.com.
  static bool isValidEmailOrEmpty(String email) {
    if (email.isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  /// Removes the spaces and hyphens people type in Aadhaar numbers
  /// ("2345 6789 0124").
  static String cleanAadhaar(String? text) =>
      (text ?? '').replaceAll(RegExp(r'[ -]'), '');

  // Verhoeff checksum tables, used by UIDAI for the last digit of an
  // Aadhaar number.
  static const _multiply = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
    [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
    [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
    [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
    [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
    [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
  ];
  static const _permute = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
    [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
    [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
    [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
    [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
  ];

  /// Empty is allowed; otherwise 12 digits, not starting with 0 or 1, with a
  /// valid Verhoeff check digit (catches most typing mistakes).
  static bool isValidAadhaarOrEmpty(String aadhaar) {
    if (aadhaar.isEmpty) return true;
    if (!RegExp(r'^[2-9][0-9]{11}$').hasMatch(aadhaar)) return false;
    var check = 0;
    for (var i = 0; i < 12; i++) {
      final digit = aadhaar.codeUnitAt(11 - i) - 48;
      check = _multiply[check][_permute[i % 8][digit]];
    }
    return check == 0;
  }
}
