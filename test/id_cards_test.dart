import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/college_repository.dart';
import 'package:hostel_mobile_app/data/student_file_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/college.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/id_card.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/students_screen.dart';
import 'package:hostel_mobile_app/services/document_share.dart';
import 'package:hostel_mobile_app/services/id_card_pdf.dart';
import 'package:hostel_mobile_app/services/id_card_service.dart';
import 'package:hostel_mobile_app/services/student_file_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';
import 'package:image/image.dart' as img;

const hostel = Hostel(
  hostelId: 1,
  hostelName: 'Boys Hostel',
  phone: '0135 2345678',
);
final today = DateTime(2026, 11, 25);

final photo = Uint8List.fromList(
  img.encodeJpg(img.Image(width: 480, height: 600)),
);

Student student(
  int id,
  String name, {
  String status = 'Active',
  String? photoPath,
  String? college = 'DAV College',
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: 'Male',
  admissionDate: DateTime(2026, 7, 1),
  status: status,
  photoPath: photoPath,
  collegeName: college,
  fatherName: 'Rakesh',
  fatherMobile: '98111 22233',
  mobile: '98765 43210',
);

final students = [
  student(1, 'Aman', photoPath: 'S1_photo.jpg'),
  student(2, 'Bina', photoPath: 'S2_photo.jpg'),
  student(3, 'Chet'), // no photo
  student(4, 'Dev', status: 'Left', photoPath: 'S4_photo.jpg'),
];

RoomAllocation stay(int studentId, String room, int bed) => RoomAllocation(
  allocationId: studentId,
  studentId: studentId,
  studentName: 'x',
  roomId: 1,
  roomNumber: room,
  hostelId: 1,
  bedNumber: bed,
  checkInDate: DateTime(2026, 7, 5),
  status: AllocationStatus.current,
);

Invoice invoice(int student, int year, double transport) => Invoice(
  invoiceId: student * 10 + year % 10,
  invoiceNumber: 'I$student',
  studentId: student,
  academicYear: year,
  roomRent: 80000,
  transportAmount: transport,
);

final invoices = [
  invoice(1, 2026, 12000), // Aman has transport this year
  invoice(2, 2025, 12000), // Bina only last year
  invoice(3, 2026, 0),
];

class FakeStudents extends StudentRepository {
  @override
  Future<List<Student>> getForHostel(int hostelId) async => students;
}

class FakeColleges extends CollegeRepository {
  @override
  Future<List<College>> getForHostel(int hostelId) async => const [];
}

class FakeAllocs extends AllocationRepository {
  @override
  Future<List<RoomAllocation>> getForHostel(
    int hostelId, {
    bool includeHistory = false,
  }) async => [stay(1, '101', 2), stay(2, '7', 1)];
}

class FakeBilling extends BillingRepository {
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

class FakeFiles extends StudentFileRepository {
  @override
  Future<Uint8List> download(String name) async => photo;
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  setUp(() {
    StudentRepository.useInstance(FakeStudents());
    CollegeRepository.useInstance(FakeColleges());
    AllocationRepository.useInstance(FakeAllocs());
    BillingRepository.useInstance(FakeBilling());
    StudentFileRepository.useInstance(FakeFiles());
    StudentFileService.clearCache();
  });
  tearDown(() {
    StudentRepository.useInstance(null);
    CollegeRepository.useInstance(null);
    AllocationRepository.useInstance(null);
    BillingRepository.useInstance(null);
    StudentFileRepository.useInstance(null);
    DocumentShare.useForTests(null);
  });

  group('IdCardService', () {
    test('valid till starts as the end of the academic year', () {
      expect(IdCardService.defaultValidTill(today, 7), DateTime(2027, 6, 30));
      expect(
        IdCardService.defaultValidTill(DateTime(2026, 3, 1), 7),
        DateTime(2026, 6, 30),
      );
    });

    test('file names', () {
      expect(IdCardService.fileName(false, today), 'ICards_2026-11-25.pdf');
      expect(
        IdCardService.fileName(true, today),
        'TransportCards_2026-11-25.pdf',
      );
    });

    test('the card shows the student, room and photo', () async {
      final r = await IdCardService.prepare(
        hostel,
        [1],
        transport: false,
        today: today,
      );
      expect(r.problems, isEmpty);
      final c = r.cards.single;
      expect(c.hostelName, 'Boys Hostel');
      expect(c.hostelPhone, '0135 2345678');
      expect(c.studentName, 'Aman');
      expect(c.fatherName, 'Rakesh');
      expect(c.collegeName, 'DAV College');
      expect(c.roomText, 'Room 101, bed 2');
      expect(c.studentMobile, '98765 43210');
      expect(c.fatherMobile, '98111 22233');
      expect(c.photo, photo);
      expect(c.validTill, DateTime(2027, 6, 30));
      expect(c.academicYear, '2026-2027');
    });

    test('a chosen valid till date is used', () async {
      final r = await IdCardService.prepare(
        hostel,
        [1],
        transport: false,
        today: today,
        validTill: DateTime(2026, 12, 31),
      );
      expect(r.cards.single.validTill, DateTime(2026, 12, 31));
    });

    test('the desktop messages', () async {
      await expectMessage(
        IdCardService.prepare(
          hostel,
          [],
          transport: false,
          today: today,
        ).then((_) {}),
        'Please select one or more students.',
      );
      await expectMessage(
        IdCardService.prepare(
          hostel,
          [1],
          transport: false,
          today: today,
          validTill: DateTime(2026, 11, 24),
        ).then((_) {}),
        'The Valid till date cannot be in the past.',
      );
    });

    test('students who cannot get a card are listed as problems', () async {
      final r = await IdCardService.prepare(
        hostel,
        [1, 3, 4, 99],
        transport: false,
        today: today,
      );
      expect([for (final c in r.cards) c.studentName], ['Aman', 'Chet']);
      expect(r.problems, [
        'Chet: no photo (the card has an empty photo box). Add one on the Students screen.',
        'Dev: has left the hostel.',
      ]);
      expect(r.cards.last.photo, isNull);
      expect(r.cards.last.roomText, '');
    });

    test('a transport card needs transport in this year\'s fee', () async {
      final r = await IdCardService.prepare(
        hostel,
        [1, 2, 3],
        transport: true,
        today: today,
      );
      expect([for (final c in r.cards) c.studentName], ['Aman']);
      expect(r.problems, [
        'Bina: no transport in the 2026-2027 fee.',
        'Chet: no transport in the 2026-2027 fee.',
      ]);
    });
  });

  group('IdCardPdf', () {
    IdCard card(String name, {Uint8List? p}) => IdCard(
      hostelName: 'Boys Hostel',
      hostelPhone: '',
      studentName: name,
      fatherName: '',
      collegeName: '',
      roomText: '',
      studentMobile: '',
      fatherMobile: '',
      photo: p,
      validTill: DateTime(2027, 6, 30),
      academicYear: '2026-2027',
    );

    int pages(Uint8List b) =>
        RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(b)).length;

    test('eight cards on a page, more on the next', () async {
      final eight = await IdCardPdf.build([
        for (var i = 0; i < 8; i++) card('S$i', p: photo),
      ], transport: false);
      expect(latin1.decode(eight.sublist(0, 4)), '%PDF');
      expect(pages(eight), 1);
      final nine = await IdCardPdf.build([
        for (var i = 0; i < 9; i++) card('S$i'),
      ], transport: true);
      expect(pages(nine), 2);
    });

    test('a bad photo leaves an empty photo box', () async {
      final b = await IdCardPdf.build([
        card('A', p: Uint8List.fromList([1, 2, 3])),
      ], transport: false);
      expect(latin1.decode(b.sublist(0, 4)), '%PDF');
    });
  });

  group('Students screen', () {
    late List<String> shared;

    setUp(() {
      shared = [];
      DocumentShare.useForTests((files, subject, text) async {
        shared.add('${files.single.name}|${files.single.bytes.length > 1000}');
      });
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 8400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StudentsScreen(hostel: hostel, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> select(WidgetTester tester, int id) async {
      await tester.longPress(find.byKey(Key('student_$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('long press selects, a tap changes the choice, close clears', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Students'), findsOneWidget);
      await select(tester, 1);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const Key('studentSelected')), findsOneWidget);
      await tester.tap(find.byKey(const Key('student_2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('student_1')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clearSelection')));
      await tester.pumpAndSettle();
      expect(find.text('Students'), findsOneWidget);
      expect(find.byKey(const Key('studentSelected')), findsNothing);
    });

    testWidgets('select all, ask the valid till date, share the cards', (
      tester,
    ) async {
      await open(tester);
      await select(tester, 1);
      await tester.tap(find.byKey(const Key('selectAll')));
      await tester.pumpAndSettle();
      expect(
        find.text('3 selected'),
        findsOneWidget,
        reason: 'the three active students',
      );
      await tester.tap(find.byKey(const Key('idCardAction')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'I-cards for 3 student(s). Enter the date printed after "Valid till" on the cards.',
        ),
        findsOneWidget,
      );
      expect(find.text('30 Jun 2027'), findsOneWidget);
      await tester.tap(find.byKey(const Key('makeCards')));
      await tester.pumpAndSettle();
      // Chet has no photo: told first, then the PDF is shared.
      expect(find.byKey(const Key('idCardNote')), findsOneWidget);
      expect(
        find.textContaining('3 I-card(s) were made. Please note:'),
        findsOneWidget,
      );
      expect(shared, isEmpty);
      await tester.tap(find.byKey(const Key('idCardNoteOk')));
      await tester.pumpAndSettle();
      expect(shared, ['ICards_2026-11-25.pdf|true']);
      expect(
        find.text('Students'),
        findsOneWidget,
        reason: 'the choice is cleared',
      );
    });

    testWidgets(
      'transport cards: only those with transport; none is explained',
      (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const Key('studentMenu_2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Transport I-Card'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('makeCards')));
        await tester.pumpAndSettle();
        expect(find.textContaining('No I-card could be made:'), findsOneWidget);
        expect(
          find.textContaining('Bina: no transport in the 2026-2027 fee.'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('idCardNoteOk')));
        await tester.pumpAndSettle();
        expect(shared, isEmpty);

        await tester.tap(find.byKey(const Key('studentMenu_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Transport I-Card'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('makeCards')));
        await tester.pumpAndSettle();
        expect(shared, ['TransportCards_2026-11-25.pdf|true']);
      },
    );

    testWidgets('cancelling the date makes nothing', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('studentMenu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I-Card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(shared, isEmpty);
    });
  });
}
