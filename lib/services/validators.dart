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
}
