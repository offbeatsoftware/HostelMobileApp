import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/main.dart';
import 'package:hostel_mobile_app/screens/home_screen.dart';
import 'package:hostel_mobile_app/screens/login_screen.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';

// The tests use a mock Firebase, so they never reach the real project.
const adminEmail = AuthService.defaultEmail;
const adminPassword = 'secret123';

MockFirebaseAuth mockAuth({bool signedIn = false}) => MockFirebaseAuth(
  signedIn: signedIn,
  mockUser: MockUser(uid: 'admin1', email: adminEmail),
);

/// Makes the mock reject sign in with the given Firebase error code.
MockFirebaseAuth failingAuth(String code) {
  final auth = mockAuth();
  whenCalling(
    Invocation.method(#signInWithEmailAndPassword, null),
  ).on(auth).thenThrow(FirebaseAuthException(code: code));
  return auth;
}

Future<void> signIn(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byKey(const Key('email')), email);
  await tester.enterText(find.byKey(const Key('password')), password);
  await tester.tap(find.byKey(const Key('signIn')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AuthService.useAuth(null));

  group('AuthService', () {
    test('signs in with email and password', () async {
      AuthService.useAuth(mockAuth());
      expect(await AuthService.signIn(' $adminEmail ', adminPassword), isNull);
      expect(AuthService.isSignedIn, isTrue);
    });

    test('asks for both boxes when one is empty', () async {
      AuthService.useAuth(mockAuth());
      expect(
        await AuthService.signIn('', adminPassword),
        'Enter the email and password.',
      );
      expect(
        await AuthService.signIn(adminEmail, ''),
        'Enter the email and password.',
      );
      expect(AuthService.isSignedIn, isFalse);
    });

    test('turns Firebase errors into plain messages', () async {
      AuthService.useAuth(failingAuth('invalid-credential'));
      expect(
        await AuthService.signIn(adminEmail, 'wrong'),
        'Incorrect email or password.',
      );
      expect(
        AuthService.messageFor('invalid-email'),
        'The email address is not valid.',
      );
      expect(
        AuthService.messageFor('network-request-failed'),
        'No internet connection. Please check and try again.',
      );
      expect(
        AuthService.messageFor('too-many-requests'),
        'Too many attempts. Please try again later.',
      );
    });

    test('sign out', () async {
      AuthService.useAuth(mockAuth(signedIn: true));
      expect(AuthService.isSignedIn, isTrue);
      await AuthService.signOut();
      expect(AuthService.isSignedIn, isFalse);
    });
  });

  testWidgets('opens on the login screen when nobody is signed in', (
    tester,
  ) async {
    AuthService.useAuth(mockAuth());
    await tester.pumpWidget(const HostelMobileApp());
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text(AuthService.defaultEmail), findsOneWidget);
    expect(find.text('Shri Balaji Hostel'), findsOneWidget);
  });

  testWidgets('opens on the home page when already signed in', (tester) async {
    AuthService.useAuth(mockAuth(signedIn: true));
    await tester.pumpWidget(const HostelMobileApp());
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('wrong password shows an error and stays on login', (
    tester,
  ) async {
    AuthService.useAuth(failingAuth('invalid-credential'));
    await tester.pumpWidget(const HostelMobileApp());
    await signIn(tester, adminEmail, 'wrong');
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets(
    'correct email and password open the home page, sign out returns',
    (tester) async {
      AuthService.useAuth(mockAuth());
      await tester.pumpWidget(const HostelMobileApp());
      await signIn(tester, adminEmail, adminPassword);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('signOut')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(AuthService.isSignedIn, isFalse);
    },
  );
}
