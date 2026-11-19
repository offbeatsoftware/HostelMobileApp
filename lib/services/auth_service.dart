import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Admin sign in through Firebase Authentication (email and password).
/// Admin accounts are created in the Firebase Console
/// (Authentication > Users), not in the app.
class AuthService {
  static FirebaseAuth? _testAuth;

  static FirebaseAuth get _auth => _testAuth ?? FirebaseAuth.instance;

  /// Lets the automated tests use a mock instead of the real Firebase.
  @visibleForTesting
  static void useAuth(FirebaseAuth? auth) => _testAuth = auth;

  /// The admin who is signed in, or null.
  static User? get currentUser => _auth.currentUser;

  static bool get isSignedIn => currentUser != null;

  /// Signs in. Returns null when it worked, otherwise a message to show.
  static Future<String?> signIn(String email, String password) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      return 'Enter the email and password.';
    }
    try {
      await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return messageFor(e.code);
    } catch (_) {
      return 'The sign in could not be completed. Please try again.';
    }
  }

  /// Turns a Firebase error code into a message for the admin.
  static String messageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please check and try again.';
      default: // invalid-credential, wrong-password, user-not-found
        return 'Incorrect email or password.';
    }
  }

  static Future<void> signOut() => _auth.signOut();
}
