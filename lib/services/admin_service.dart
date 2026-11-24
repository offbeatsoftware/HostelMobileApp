import 'package:firebase_auth/firebase_auth.dart';

import '../data/admin_repository.dart';
import '../models/admin_user.dart';
import 'auth_service.dart';
import 'validators.dart';

/// Admin Account rules, the same as the desktop AuthService.
class AdminService {
  static const minimumPasswordLength = 6;

  static Future<AdminUser> getCurrentAdmin() async {
    final admin = await AdminRepository.instance.getCurrent(
      AuthService.currentUser?.uid,
    );
    if (admin == null) {
      throw const ValidationException('No admin account was found.');
    }
    return admin;
  }

  static Future<AdminUser> saveContact(
    AdminUser admin,
    String email,
    String phone,
  ) async {
    email = Validators.clean(email);
    phone = Validators.clean(phone);
    if (!Validators.isValidEmailOrEmpty(email)) {
      throw const ValidationException('Please enter a valid email address.');
    }
    if (!Validators.isValidPhoneOrEmpty(phone)) {
      throw const ValidationException('Please enter a valid phone number.');
    }
    Validators.checkLength(email, 150, 'Email');
    Validators.checkLength(phone, 20, 'Phone');
    return await AdminRepository.instance.saveContact(
      admin.adminUserId,
      email: email,
      phone: phone,
    );
  }

  /// Changes the Firebase password after checking the current one.
  static Future<void> changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    final user = AuthService.currentUser;
    if (user == null || user.email == null) {
      throw const ValidationException('Sign in again to change the password.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed' || e.code == 'too-many-requests') {
        throw ValidationException(AuthService.messageFor(e.code));
      }
      throw const ValidationException('The current password is not correct.');
    }
    if (newPassword.length < minimumPasswordLength) {
      throw const ValidationException(
        'The new password must have at least $minimumPasswordLength characters.',
      );
    }
    if (newPassword.trim().length != newPassword.length) {
      throw const ValidationException(
        'The new password cannot start or end with a space.',
      );
    }
    if (newPassword != confirmPassword) {
      throw const ValidationException(
        'The new password and its confirmation are not the same.',
      );
    }
    if (newPassword == currentPassword) {
      throw const ValidationException(
        'The new password must be different from the current password.',
      );
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw ValidationException(
        e.code == 'weak-password'
            ? 'The new password is too weak. Choose a longer one.'
            : AuthService.messageFor(e.code),
      );
    }
  }
}
