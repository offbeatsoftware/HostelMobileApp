import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/email_send_repository.dart';
import 'package:hostel_mobile_app/data/email_settings_repository.dart';
import 'package:hostel_mobile_app/screens/email_settings_screen.dart';
import 'package:hostel_mobile_app/services/document_email.dart';
import 'package:hostel_mobile_app/services/email_sender.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

/// Records the calls to the send-email function.
class FakeSender extends EmailSendRepository {
  FakeSender({this.configured = true, this.error});

  bool configured;
  String? error;
  final calls = <Map<String, Object?>>[];

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<String?> call(Map<String, Object?> body) async {
    calls.add(body);
    if (body['action'] == 'save_password' && error == null) {
      configured = true;
    }
    return error;
  }
}

class NoSettings extends EmailSettingsRepository {
  final saved = <Map<String, String>>[];
  @override
  Future<Map<String, String>> getValues() async => {};
  @override
  Future<void> saveValues(Map<String, String> values) async =>
      saved.add(values);
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  late FakeSender fake;

  setUp(() {
    fake = FakeSender();
    EmailSendRepository.useInstance(fake);
  });
  tearDown(() {
    EmailSendRepository.useInstance(null);
    EmailSettingsRepository.useInstance(null);
  });

  group('EmailSender', () {
    test('the app password is cleaned and sent only to the function', () async {
      await EmailSender.savePassword(' abcd efgh\nijkl mnop ');
      expect(fake.calls.single, {
        'action': 'save_password',
        'password': 'abcdefghijklmnop',
      });
      await expectMessage(
        EmailSender.savePassword('   '),
        'Please enter the Gmail app password.',
      );
      expect(fake.calls.length, 1);
    });

    test('a refused password is explained', () async {
      fake.error = 'The app password could not be saved.';
      await expectMessage(
        EmailSender.savePassword('abcd'),
        'The app password could not be saved.',
      );
    });

    test('test email: address checked first', () async {
      await expectMessage(
        EmailSender.sendTest('nope'),
        'Please enter a valid email address to send the test to.',
      );
      expect(fake.calls, isEmpty);
      await EmailSender.sendTest(' me@x.com ');
      await EmailSender.sendTest('');
      expect(fake.calls, [
        {'action': 'test', 'to': 'me@x.com'},
        {'action': 'test', 'to': ''},
      ]);
    });

    test('send: the email, PDFs as base64 and what to log', () async {
      const draft = EmailDraft(
        to: 'rakesh@x.com',
        relation: 'Father',
        parentName: 'Rakesh',
        copyTo: 'admin@x.com',
        subject: 'Fee reminder',
        body: 'Dear Rakesh,',
        type: 'DueReminder',
        studentId: 7,
        invoiceIds: [2, 1],
      );
      await EmailSender.send(draft, [
        (name: 'a.pdf', bytes: utf8.encode('%PDF-1') as dynamic),
      ]);
      final c = fake.calls.single;
      expect(c['action'], 'send');
      expect(c['to'], 'rakesh@x.com');
      expect(c['toName'], 'Rakesh');
      expect(c['cc'], 'admin@x.com');
      expect(c['attachments'], [
        {'name': 'a.pdf', 'base64': base64Encode(utf8.encode('%PDF-1'))},
      ]);
      expect(c['log'], {
        'emailType': 'DueReminder',
        'studentId': 7,
        'invoiceIds': [2, 1],
      });
    });

    test('an absence is logged with its night; a failure is thrown', () async {
      const draft = EmailDraft(
        to: 'm@x.com',
        relation: 'Mother',
        parentName: 'Sunita',
        copyTo: '',
        subject: 's',
        body: 'b',
        type: 'Absence',
        studentId: 1,
        attendanceDate: '2026-11-24',
      );
      fake.error = 'Gmail did not accept the sender address and app password.';
      await expectMessage(
        EmailSender.send(draft, const []),
        'Gmail did not accept the sender address and app password.',
      );
      expect(fake.calls.single['log'], {
        'emailType': 'Absence',
        'studentId': 1,
        'attendanceDate': '2026-11-24',
      });
    });
  });

  group('Email Settings: Gmail password and test email', () {
    late NoSettings settings;

    setUp(() {
      settings = NoSettings();
      EmailSettingsRepository.useInstance(settings);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const EmailSettingsScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a saved password is not shown, only its label changes', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.text('App password (saved; type a new one to replace it)'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      fake.configured = false;
      await open(tester);
      expect(find.text('App password'), findsOneWidget);
    });

    testWidgets('Save sends a typed password and clears the box', (
      tester,
    ) async {
      fake.configured = false;
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('appPassword')),
        'abcd efgh ijkl mnop',
      );
      await tester.tap(find.byKey(const Key('saveEmail')));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(fake.calls.single['password'], 'abcdefghijklmnop');
      expect(settings.saved, isNotEmpty);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('appPassword')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '',
      );
      expect(
        find.text('App password (saved; type a new one to replace it)'),
        findsOneWidget,
      );
    });

    testWidgets('Save without a typed password leaves the saved one', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('saveEmail')));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('Send Test Email saves, then sends to the address', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('testTo')), 'me@x.com');
      await tester.tap(find.byKey(const Key('sendTest')));
      await tester.pumpAndSettle();
      expect(
        find.text('Test email sent to me@x.com. Check its inbox.'),
        findsOneWidget,
      );
      expect(fake.calls.single, {'action': 'test', 'to': 'me@x.com'});
      expect(settings.saved, isNotEmpty);
    });

    testWidgets('the test needs a password, and shows Gmail\'s answer', (
      tester,
    ) async {
      fake.configured = false;
      await open(tester);
      await tester.tap(find.byKey(const Key('sendTest')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter the Gmail app password.'), findsOneWidget);
      expect(fake.calls, isEmpty);

      await tester.enterText(find.byKey(const Key('appPassword')), 'wrongpass');
      fake.error =
          'Could not connect to smtp.gmail.com. Check the internet connection and try again.';
      await tester.scrollUntilVisible(
        find.byKey(const Key('sendTest')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('gmailTab')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('sendTest')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not connect to smtp.gmail.com. Check the internet connection and try again.',
        ),
        findsOneWidget,
      );
    });
  });
}
