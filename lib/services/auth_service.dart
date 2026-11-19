/// Admin sign in. For this first step of the migration the login is hard coded
/// to admin / admin; it will later be checked against the hostel database as the
/// desktop AuthService does.
class AuthService {
  static const defaultUserName = 'admin';
  static const _password = 'admin';

  /// The user name is not case sensitive; the password is (as on the desktop).
  static bool isValidLogin(String? userName, String? password) {
    final name = userName?.trim() ?? '';
    if (name.isEmpty || password == null || password.isEmpty) {
      return false;
    }
    return name.toLowerCase() == defaultUserName && password == _password;
  }
}
