import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/email_settings_repository.dart';
import 'package:hostel_mobile_app/data/payment_qr_repository.dart';
import 'package:hostel_mobile_app/data/reminder_repository.dart';
import 'package:hostel_mobile_app/data/settings_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/email_settings_screen.dart';
import 'package:hostel_mobile_app/screens/fee_reminders_screen.dart';
import 'package:hostel_mobile_app/services/document_share.dart';
import 'package:hostel_mobile_app/services/launcher.dart';
import 'package:hostel_mobile_app/services/payment_qr_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';

/// A 1x1 PNG.
final png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class MemoryQr extends PaymentQrRepository {
  MemoryQr({String? name, Uint8List? bytes}) : _name = name, _bytes = bytes;

  String? _name;
  Uint8List? _bytes;
  final saved = <String>[];
  var failLoad = false;

  @override
  Future<String?> getName() async {
    if (failLoad) throw Exception('no bucket');
    return _name;
  }

  @override
  Future<Uint8List> download(String name) async => _bytes!;

  @override
  Future<void> save(String name, Uint8List bytes, String contentType) async {
    saved.add('$name|$contentType');
    _name = name;
    _bytes = bytes;
  }

  @override
  Future<void> remove() async {
    _name = null;
    _bytes = null;
  }
}

class NoEmailSettings extends EmailSettingsRepository {
  @override
  Future<Map<String, String>> getValues() async => {};
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  group('PaymentQrService', () {
    test('the desktop checks', () async {
      await expectMessage(
        Future(() => PaymentQrService.validate('qr.gif', png)),
        'Please choose the QR code as a PNG or JPG image.',
      );
      await expectMessage(
        Future(
          () => PaymentQrService.validate(
            'qr.png',
            Uint8List(5 * 1024 * 1024 + 1),
          ),
        ),
        'The QR image is larger than 5 MB. Please choose a smaller image.',
      );
      await expectMessage(
        Future(
          () => PaymentQrService.validate(
            'qr.png',
            Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]),
          ),
        ),
        'The QR file is not a readable image.',
      );
      PaymentQrService.validate('QR.PNG', png);
      PaymentQrService.validate(
        'qr.JPEG',
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]),
      );
    });

    test('save names the file and replaces the old one', () async {
      final db = MemoryQr(name: 'old.png', bytes: png);
      PaymentQrRepository.useInstance(db);
      addTearDown(() => PaymentQrRepository.useInstance(null));
      final saved = await PaymentQrService.save('photo.PNG', png);
      expect(saved.name, matches(RegExp(r'^PaymentQR_\d{14}\.png$')));
      expect(db.saved.single, endsWith('|image/png'));
      expect((await PaymentQrService.get())!.name, saved.name);
      await PaymentQrService.remove();
      expect(await PaymentQrService.get(), isNull);
    });
  });

  group('Email Settings: QR image', () {
    late MemoryQr db;
    Future<({String name, Uint8List bytes})?> Function() pick = () async =>
        null;

    setUp(() {
      db = MemoryQr();
      PaymentQrRepository.useInstance(db);
      EmailSettingsRepository.useInstance(NoEmailSettings());
      PaymentQrService.usePicker(() => pick());
    });
    tearDown(() {
      PaymentQrRepository.useInstance(null);
      EmailSettingsRepository.useInstance(null);
      PaymentQrService.usePicker(null);
    });

    Future<void> openWhatsApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const EmailSettingsScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'WhatsApp'));
      await tester.pumpAndSettle();
    }

    testWidgets('none yet; choose; remove', (tester) async {
      await openWhatsApp(tester);
      expect(find.byKey(const Key('qrNone')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('removeQr')))
            .onPressed,
        isNull,
      );

      pick = () async => (name: 'upi.png', bytes: png);
      await tester.tap(find.byKey(const Key('chooseQr')));
      await tester.pumpAndSettle();
      expect(find.text('The payment QR image was saved.'), findsOneWidget);
      expect(find.byKey(const Key('qrPreview')), findsOneWidget);
      expect(db.saved.length, 1);

      await tester.tap(find.byKey(const Key('removeQr')));
      await tester.pumpAndSettle();
      expect(find.text('The payment QR image was removed.'), findsOneWidget);
      expect(find.byKey(const Key('qrNone')), findsOneWidget);
    });

    testWidgets('a wrong file is refused; cancelling changes nothing', (
      tester,
    ) async {
      await openWhatsApp(tester);
      pick = () async => (name: 'scan.pdf', bytes: png);
      await tester.tap(find.byKey(const Key('chooseQr')));
      await tester.pumpAndSettle();
      expect(
        find.text('Please choose the QR code as a PNG or JPG image.'),
        findsOneWidget,
      );
      pick = () async => null;
      await tester.tap(find.byKey(const Key('chooseQr')));
      await tester.pumpAndSettle();
      expect(db.saved, isEmpty);
    });

    testWidgets('a saved image is shown; a missing bucket is explained', (
      tester,
    ) async {
      PaymentQrRepository.useInstance(MemoryQr(name: 'a.png', bytes: png));
      await openWhatsApp(tester);
      expect(find.byKey(const Key('qrPreview')), findsOneWidget);
      expect(find.text('a.png'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      PaymentQrRepository.useInstance(MemoryQr()..failLoad = true);
      await openWhatsApp(tester);
      expect(find.byKey(const Key('qrProblem')), findsOneWidget);
    });
  });

  group('Fee Reminders: QR image', () {
    final hostel = const Hostel(hostelId: 1, hostelName: 'Boys Hostel');
    final shared = <String>[];

    setUp(() {
      shared.clear();
      BillingRepository.useInstance(_Billing());
      StudentRepository.useInstance(_Students());
      ReminderRepository.useInstance(_Reminders());
      SettingsRepository.useInstance(_Settings());
      Launcher.useForTests((uri) async => true);
      DocumentShare.useForTests(
        null,
        shareImage: (bytes, name) async => shared.add('$name|${bytes.length}'),
      );
    });
    tearDown(() {
      BillingRepository.useInstance(null);
      StudentRepository.useInstance(null);
      ReminderRepository.useInstance(null);
      SettingsRepository.useInstance(null);
      PaymentQrRepository.useInstance(null);
      Launcher.useForTests(null);
      DocumentShare.useForTests(null);
    });

    Future<void> openReminder(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: FeeRemindersScreen(
            hostel: hostel,
            today: DateTime(2026, 11, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remind_1')));
      await tester.pumpAndSettle();
    }

    testWidgets('with a QR image the dialog can send it', (tester) async {
      PaymentQrRepository.useInstance(MemoryQr(name: 'upi.png', bytes: png));
      await openReminder(tester);
      expect(find.byKey(const Key('sendQr')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sendQr')));
      await tester.pump();
      expect(shared, ['upi.png|${png.length}']);
      // The dialog stays open for the text.
      expect(find.byKey(const Key('openWhatsApp')), findsOneWidget);
    });

    testWidgets('without one (or without the script) there is no button', (
      tester,
    ) async {
      PaymentQrRepository.useInstance(MemoryQr());
      await openReminder(tester);
      expect(find.byKey(const Key('sendQr')), findsNothing);
      expect(find.byKey(const Key('openWhatsApp')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      PaymentQrRepository.useInstance(MemoryQr()..failLoad = true);
      await openReminder(tester);
      expect(find.byKey(const Key('sendQr')), findsNothing);
      expect(find.byKey(const Key('openWhatsApp')), findsOneWidget);
    });
  });
}

class _Billing extends BillingRepository {
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => [
    const Invoice(
      invoiceId: 1,
      invoiceNumber: 'SBH/2026-2027/0001',
      studentId: 1,
      academicYear: 2026,
      roomRent: 80000,
      transportAmount: 0,
      receivedAmount: 50000,
      studentName: 'Ravi',
    ),
  ];
  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

class _Students extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => [
    Student(
      studentId: 1,
      hostelId: 1,
      studentName: 'Ravi',
      gender: 'Male',
      admissionDate: DateTime(2025, 7, 1),
      fatherName: 'Rakesh',
      fatherMobile: '98111 22233',
    ),
  ];
}

class _Reminders extends ReminderRepository {
  @override
  Future<Map<int, DateTime>> getLastReminders(int hostelId) async => {};
}

class _Settings extends SettingsRepository {
  @override
  Future<Map<String, String>> getWhatsAppTexts() async => {};
  @override
  Future<String?> getAdminPhone() async => '99999 11111';
}
