import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Admin sign in, migrated from the desktop LoginForm: the hostel photo fills the
/// screen and the sign in panel sits at the bottom.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userNameController =
      TextEditingController(text: AuthService.defaultUserName);
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  String _message = '';
  bool _obscure = true;

  @override
  void dispose() {
    _userNameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _signIn() {
    if (AuthService.isValidLogin(
        _userNameController.text, _passwordController.text)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
    setState(() => _message = 'Incorrect user name or password.');
    _passwordController.clear();
    _passwordFocus.requestFocus();
  }

  InputDecoration _fieldDecoration({Widget? suffix}) => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(color: AppColors.lightText, fontSize: 15)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.loginBackground,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/login_background.jpg', fit: BoxFit.cover),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 32),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildPanel(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            AppInfo.businessName,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontFamilyFallback: ['serif'],
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 60, height: 2, color: AppColors.gold),
          ),
          const SizedBox(height: 22),
          _label('User name'),
          TextField(
            key: const Key('userName'),
            controller: _userNameController,
            maxLength: 50,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: _fieldDecoration().copyWith(counterText: ''),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          _label('Password'),
          TextField(
            key: const Key('password'),
            controller: _passwordController,
            focusNode: _passwordFocus,
            // The user name is filled in, so the cursor starts in the password box.
            autofocus: true,
            obscureText: _obscure,
            maxLength: 50,
            textInputAction: TextInputAction.done,
            decoration: _fieldDecoration(
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ).copyWith(counterText: ''),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 10),
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_message,
                  key: const Key('loginMessage'),
                  style: const TextStyle(color: AppColors.errorText)),
            ),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('signIn'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: _signIn,
              child: const Text('Sign in'),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Version ${AppInfo.version}',
              style: TextStyle(color: AppColors.mutedText, fontSize: 12)),
        ],
      ),
    );
  }
}
