import 'package:flutter/material.dart';

import '../models/admin_user.dart';
import '../services/admin_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

const _success = Color(0xFF198754);

/// Admin Account (the desktop screen): the admin's email and phone, and
/// changing the password.
class AdminAccountScreen extends StatefulWidget {
  const AdminAccountScreen({super.key});

  @override
  State<AdminAccountScreen> createState() => _AdminAccountScreenState();
}

class _AdminAccountScreenState extends State<AdminAccountScreen> {
  late final Future<AdminUser> _admin = AdminService.getCurrentAdmin();
  final _userName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  AdminUser? _loaded;
  String _contactMessage = '';
  bool _contactOk = false;
  String _passwordMessage = '';
  bool _passwordOk = false;
  bool _savingContact = false;
  bool _changing = false;

  @override
  void dispose() {
    for (final c in [_userName, _email, _phone, _current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _show(AdminUser admin) {
    _loaded = admin;
    _userName.text = admin.userName;
    _email.text = admin.email;
    _phone.text = admin.phone;
  }

  Future<void> _saveContact() async {
    if (_savingContact || _loaded == null) return;
    setState(() {
      _savingContact = true;
      _contactMessage = '';
    });
    try {
      final saved = await AdminService.saveContact(
        _loaded!,
        _email.text,
        _phone.text,
      );
      if (!mounted) return;
      setState(() {
        _show(saved);
        _contactOk = true;
        _contactMessage = 'Saved.';
      });
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _contactOk = false;
          _contactMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'The admin details could not be saved. $e');
      }
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Future<void> _changePassword() async {
    if (_changing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _changing = true;
      _passwordMessage = '';
    });
    try {
      await AdminService.changePassword(
        _current.text,
        _new.text,
        _confirm.text,
      );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      setState(() {
        _passwordOk = true;
        _passwordMessage =
            'Password changed. Use the new password next time you sign in.';
      });
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _passwordOk = false;
          _passwordMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) showToast(context, 'The password could not be changed. $e');
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Widget _message(String text, bool ok, Key key) => text.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            text,
            key: key,
            style: TextStyle(color: ok ? _success : const Color(0xFFC0392B)),
          ),
        );

  Widget _password(String label, TextEditingController c, Key key) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: key,
      controller: c,
      obscureText: true,
      maxLength: 100,
      decoration: InputDecoration(labelText: '$label *', counterText: ''),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Account')),
      body: FutureBuilder<AdminUser>(
        future: _admin,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return InfoView(
              key: const Key('adminError'),
              icon: Icons.cloud_off,
              text:
                  'The admin details could not be loaded.\n${snapshot.error}\n\n'
                  'Close this screen and open it again to try again.',
            );
          }
          if (_loaded == null) _show(snapshot.data!);
          return ListView(
            key: const Key('adminView'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const FormSection('Admin details'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FormTextField(
                        key: const Key('adminUserName'),
                        label: 'User name',
                        controller: _userName,
                        maxLength: 50,
                        enabled: false,
                      ),
                      FormTextField(
                        key: const Key('adminEmail'),
                        label: 'Email',
                        controller: _email,
                        maxLength: 150,
                        keyboard: TextInputType.emailAddress,
                      ),
                      FormTextField(
                        key: const Key('adminPhone'),
                        label: 'Phone',
                        controller: _phone,
                        maxLength: 20,
                        keyboard: TextInputType.phone,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'A copy of every email sent to parents (invoices, '
                          'receipts and reminders) goes to this email address. '
                          'Email and phone can also be used in the email texts '
                          'as {AdminEmail} and {AdminPhone}.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      _message(
                        _contactMessage,
                        _contactOk,
                        const Key('contactMessage'),
                      ),
                      SaveButton(
                        key: const Key('saveContact'),
                        busy: _savingContact,
                        onPressed: _saveContact,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const FormSection('Change password'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _password(
                        'Current password',
                        _current,
                        const Key('currentPassword'),
                      ),
                      _password('New password', _new, const Key('newPassword')),
                      _password(
                        'Confirm new password',
                        _confirm,
                        const Key('confirmPassword'),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'At least ${AdminService.minimumPasswordLength} characters. '
                          'Passwords are case sensitive.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      _message(
                        _passwordMessage,
                        _passwordOk,
                        const Key('passwordMessage'),
                      ),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const Key('changePassword'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.terracotta,
                          ),
                          onPressed: _changing ? null : _changePassword,
                          child: _changing
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Change Password'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
