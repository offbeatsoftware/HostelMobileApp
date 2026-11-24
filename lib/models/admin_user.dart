/// The administrator (the desktop AdminUser): user name, email and phone.
class AdminUser {
  const AdminUser({
    required this.adminUserId,
    required this.userName,
    this.email = '',
    this.phone = '',
  });

  final int adminUserId;
  final String userName;
  final String email;
  final String phone;

  factory AdminUser.fromMap(Map<String, dynamic> map) => AdminUser(
    adminUserId: map['admin_user_id'] as int,
    userName: map['user_name'] as String,
    email: (map['email'] as String?) ?? '',
    phone: (map['phone'] as String?) ?? '',
  );
}
