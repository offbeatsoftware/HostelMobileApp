import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/admin_repository.dart';
import 'package:hostel_mobile_app/models/admin_user.dart';
import 'package:hostel_mobile_app/screens/admin_account_screen.dart';
import 'package:hostel_mobile_app/services/admin_service.dart';
import 'package:hostel_mobile_app/services/auth_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

class MemoryAdmins extends AdminRepository {
  MemoryAdmins({this.fail = false});
  final bool fail;
  AdminUser admin = const AdminUser(
    adminUserId: 1,
    userName: 'admin',
    email: 'admin@shribalajihostel.com',
    phone: '99999 11111',
  );
  String? uidAsked;

  @override
  Future<AdminUser?> getCurrent(String? firebaseUid) async {
    uidAsked = firebaseUid;
    if (fail) throw Exception('offline');
    return admin;
  }

  @override
  Future<AdminUser> saveContact(
    int adminUserId, {
    required String email,
    required String phone,
  }) async {
    admin = AdminUser(
      adminUserId: adminUserId,
      userName: admin.userName,
      email: email,
      phone: phone,
    );
    return admin;
  }
}

late MockUser user;
late MockFirebaseAuth auth;
late MemoryAdmins db;

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  var n = 0;
  setUp(() {
    // A new user each test: mock_exceptions remembers errors per user.
    final uid = n++ == 0 ? 'uid-admin' : 'uid-admin-$n';
    user = MockUser(uid: uid, email: 'admin@shribalajihostel.com');
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    AuthService.useAuth(auth);
    db = MemoryAdmins();
    AdminRepository.useInstance(db);
  });
  tearDown(() {
    AuthService.useAuth(null);
    AdminRepository.useInstance(null);
  });

  group('AdminService', () {
    test('finds the admin by the Firebase user', () async {
      final admin = await AdminService.getCurrentAdmin();
      expect(admin.userName, 'admin');
      expect(db.uidAsked, user.uid);
    });

    test('contact: valid details are cleaned and saved', () async {
      final saved = await AdminService.saveContact(
        db.admin,
        '  boss@example.com ',
        ' 98765 43210 ',
      );
      expect(saved.email, 'boss@example.com');
      expect(saved.phone, '98765 43210');
      final empty = await AdminService.saveContact(db.admin, '', '');
      expect(empty.email, '');
    });

    test('contact: the desktop messages', () async {
      await expectMessage(
        AdminService.saveContact(db.admin, 'nope', ''),
        'Please enter a valid email address.',
      );
      await expectMessage(
        AdminService.saveContact(db.admin, '', 'abc'),
        'Please enter a valid phone number.',
      );
      await expectMessage(
        AdminService.saveContact(db.admin, '${'a' * 150}@x.com', ''),
        'Email can be at most 150 characters.',
      );
    });

    test('password: the desktop rules, in order', () async {
      await expectMessage(
        AdminService.changePassword('old123', 'abc', 'abc'),
        'The new password must have at least 6 characters.',
      );
      await expectMessage(
        AdminService.changePassword('old123', ' abcdef', ' abcdef'),
        'The new password cannot start or end with a space.',
      );
      await expectMessage(
        AdminService.changePassword('old123', 'abcdef', 'abcdeg'),
        'The new password and its confirmation are not the same.',
      );
      await expectMessage(
        AdminService.changePassword('abcdef', 'abcdef', 'abcdef'),
        'The new password must be different from the current password.',
      );
      await AdminService.changePassword('old123', 'newpass1', 'newpass1');
    });

    test('password: a wrong current password is refused first', () async {
      whenCalling(
        Invocation.method(#reauthenticateWithCredential, null),
      ).on(user).thenThrow(FirebaseAuthException(code: 'wrong-password'));
      await expectMessage(
        AdminService.changePassword('bad', 'abc', 'abc'),
        'The current password is not correct.',
      );
    });

    test('password: no internet is said as such', () async {
      whenCalling(Invocation.method(#reauthenticateWithCredential, null))
          .on(user)
          .thenThrow(FirebaseAuthException(code: 'network-request-failed'));
      await expectMessage(
        AdminService.changePassword('old123', 'newpass1', 'newpass1'),
        'No internet connection. Please check and try again.',
      );
    });
  });

  group('screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AdminAccountScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the admin, user name locked', (tester) async {
      await open(tester);
      TextField field(String k) => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(Key(k)),
          matching: find.byType(TextField),
        ),
      );
      expect(field('adminUserName').controller!.text, 'admin');
      expect(field('adminUserName').enabled, false);
      expect(
        field('adminEmail').controller!.text,
        'admin@shribalajihostel.com',
      );
      expect(field('adminPhone').controller!.text, '99999 11111');
    });

    testWidgets('saves the contact, or says what is wrong', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('adminEmail')), 'bad');
      await tester.tap(find.byKey(const Key('saveContact')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid email address.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('adminEmail')),
        'boss@example.com',
      );
      await tester.tap(find.byKey(const Key('saveContact')));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(db.admin.email, 'boss@example.com');
    });

    testWidgets('changes the password and clears the boxes', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('currentPassword')),
        'old123',
      );
      await tester.enterText(find.byKey(const Key('newPassword')), 'newpass1');
      await tester.enterText(find.byKey(const Key('confirmPassword')), 'other');
      await tester.tap(find.byKey(const Key('changePassword')));
      await tester.pumpAndSettle();
      expect(
        find.text('The new password and its confirmation are not the same.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('confirmPassword')),
        'newpass1',
      );
      await tester.tap(find.byKey(const Key('changePassword')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Password changed. Use the new password next time you sign in.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('newPassword')))
            .controller!
            .text,
        '',
      );
    });

    testWidgets('a load error is shown', (tester) async {
      AdminRepository.useInstance(MemoryAdmins(fail: true));
      await open(tester);
      expect(find.byKey(const Key('adminError')), findsOneWidget);
    });
  });
}
