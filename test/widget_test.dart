import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/main.dart';
import 'package:hostel_mobile_app/screens/home_screen.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';

void main() {
  group('AuthService', () {
    test('accepts admin / admin, user name not case sensitive', () {
      expect(AuthService.isValidLogin('admin', 'admin'), isTrue);
      expect(AuthService.isValidLogin(' Admin ', 'admin'), isTrue);
    });
    test('rejects wrong or empty credentials', () {
      expect(AuthService.isValidLogin('admin', 'Admin'), isFalse);
      expect(AuthService.isValidLogin('admin', 'wrong'), isFalse);
      expect(AuthService.isValidLogin('', 'admin'), isFalse);
      expect(AuthService.isValidLogin('admin', ''), isFalse);
    });
  });

  testWidgets('user name is prefilled with admin', (tester) async {
    await tester.pumpWidget(const HostelMobileApp());
    expect(find.text('admin'), findsOneWidget);
    expect(find.text('Shri Balaji Hostel'), findsOneWidget);
  });

  testWidgets('wrong password shows an error and stays on login',
      (tester) async {
    await tester.pumpWidget(const HostelMobileApp());
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.tap(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect user name or password.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('admin / admin opens the blank home page', (tester) async {
    await tester.pumpWidget(const HostelMobileApp());
    await tester.enterText(find.byKey(const Key('password')), 'admin');
    await tester.tap(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const Key('homeBody')), findsOneWidget);
  });
}
