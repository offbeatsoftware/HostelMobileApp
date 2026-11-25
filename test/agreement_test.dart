import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/agreement_repository.dart';
import 'package:hostel_mobile_app/data/allocation_repository.dart';
import 'package:hostel_mobile_app/data/billing_repository.dart';
import 'package:hostel_mobile_app/data/college_repository.dart';
import 'package:hostel_mobile_app/data/room_repository.dart';
import 'package:hostel_mobile_app/data/student_file_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/agreement.dart';
import 'package:hostel_mobile_app/models/allocation.dart';
import 'package:hostel_mobile_app/models/college.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/invoice.dart';
import 'package:hostel_mobile_app/models/room.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/students_screen.dart';
import 'package:hostel_mobile_app/services/agreement_pdf.dart';
import 'package:hostel_mobile_app/services/agreement_service.dart';
import 'package:hostel_mobile_app/services/agreement_signature_service.dart';
import 'package:hostel_mobile_app/services/document_share.dart';
import 'package:hostel_mobile_app/services/student_file_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';
import 'package:hostel_mobile_app/widgets/signature_pad.dart';

const hostel = Hostel(hostelId: 1, hostelName: 'Boys Hostel');
final today = DateTime(2026, 10, 6);

final png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Student student(
  int id,
  String name, {
  String gender = 'Male',
  String? father,
  String? mother,
  String? address,
  String? mobile,
  String? fatherMobile,
  String? college,
}) => Student(
  studentId: id,
  hostelId: 1,
  studentName: name,
  gender: gender,
  admissionDate: DateTime(2026, 7, 1),
  fatherName: father,
  motherName: mother,
  address: address,
  mobile: mobile,
  fatherMobile: fatherMobile,
  collegeName: college,
);

final students = [
  student(
    1,
    'Aman Sharma',
    father: 'Rakesh Sharma',
    address: '12 Rajpur Road\nDehradun',
    mobile: '98765 43210',
    fatherMobile: '98111 22233',
    college: 'DAV College',
  ),
  student(2, 'Sita Devi', gender: 'Female', mother: 'Gita'), // little entered
  student(3, 'Karan'), // never in a room
  student(4, 'Gone Boy', father: 'Raj'), // left, room history only
];

Room room(int id, String number, String gender, int capacity) => Room(
  roomId: id,
  hostelId: 1,
  roomNumber: number,
  sharingTypeId: 1,
  gender: gender,
  sharingName: 'x',
  capacity: capacity,
);

final rooms = [
  room(1, '101', 'Male', 3),
  room(2, '7', 'Female', 2),
  room(3, '55', 'Male', 5),
];

RoomAllocation stay(
  int id,
  int studentId,
  int roomId,
  String roomNumber,
  int bed,
  DateTime from, {
  DateTime? to,
}) => RoomAllocation(
  allocationId: id,
  studentId: studentId,
  studentName: 'x',
  roomId: roomId,
  roomNumber: roomNumber,
  hostelId: 1,
  bedNumber: bed,
  checkInDate: from,
  checkOutDate: to,
  status: to == null ? AllocationStatus.current : AllocationStatus.checkedOut,
);

final stays = [
  stay(1, 1, 1, '101', 2, DateTime(2026, 7, 5)),
  stay(2, 2, 2, '7', 1, DateTime(2026, 7, 6)),
  stay(3, 4, 3, '55', 3, DateTime(2025, 7, 1), to: DateTime(2026, 6, 1)),
];

Invoice invoice(int student, int year, double rent, double transport) =>
    Invoice(
      invoiceId: student * 10 + year % 10,
      invoiceNumber: 'I$student/$year',
      studentId: student,
      academicYear: year,
      roomRent: rent,
      transportAmount: transport,
    );

final invoices = [
  invoice(1, 2025, 70000, 0),
  invoice(1, 2026, 80000, 12000),
  invoice(4, 2025, 60000, 0), // his latest, not the agreement's year
];

class MemoryAgreements extends AgreementRepository {
  String? template;
  final signing = <int, ({DateTime date, String witness})>{};
  final files = <String, Uint8List>{};
  final removed = <String>[];

  @override
  Future<String?> getTemplate() async => template;
  @override
  Future<void> saveTemplate(String text) async => template = text;
  @override
  Future<({DateTime date, String witness})?> getSigning(int id) async =>
      signing[id];
  @override
  Future<void> saveSigning(int id, String date, String witness) async =>
      signing[id] = (date: DateTime.parse(date), witness: witness);
  @override
  Future<Set<String>> listNames(String prefix) async => {
    for (final n in files.keys)
      if (n.startsWith(prefix)) n,
  };
  @override
  Future<Uint8List> download(String name) async => files[name]!;
  @override
  Future<void> upload(String name, Uint8List bytes) async =>
      files[name] = bytes;
  @override
  Future<void> remove(List<String> names) async {
    removed.addAll(names);
    names.forEach(files.remove);
  }
}

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
  }) async => stays;
}

class FakeRooms extends RoomRepository {
  @override
  Future<List<Room>> getForHostel(int hostelId) async => rooms;
}

class FakeBilling extends BillingRepository {
  @override
  Future<List<Invoice>> getInvoices(int hostelId) async => invoices;
  @override
  Future<int> getAcademicYearStartMonth() async => 7;
}

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

String bold(String v) => '\u0001$v\u0002';

void main() {
  late MemoryAgreements db;

  setUp(() {
    db = MemoryAgreements();
    AgreementRepository.useInstance(db);
    StudentRepository.useInstance(FakeStudents());
    CollegeRepository.useInstance(FakeColleges());
    AllocationRepository.useInstance(FakeAllocs());
    RoomRepository.useInstance(FakeRooms());
    BillingRepository.useInstance(FakeBilling());
  });
  tearDown(() {
    AgreementRepository.useInstance(null);
    StudentRepository.useInstance(null);
    CollegeRepository.useInstance(null);
    AllocationRepository.useInstance(null);
    RoomRepository.useInstance(null);
    BillingRepository.useInstance(null);
    DocumentShare.useForTests(null);
    SignatureController.rasterizer = null;
  });

  group('agreement text', () {
    test('the default is the client\'s sample and uses only known fields', () {
      final t = AgreementService.defaultTemplate;
      expect(t, startsWith('# SHRI BALAJI HOSTEL RESIDENCY AGREEMENT'));
      expect(t, contains('## Rules & Regulations'));
      expect(t, contains('40. All disputes are subject to Dehradun court'));
      final used = RegExp(
        r'\{([A-Za-z]+)\}',
      ).allMatches(t).map((m) => m.group(1)).toSet();
      expect(used.difference(AgreementService.fields.toSet()), isEmpty);
      expect(AgreementService.fields.length, 17);
    });

    test('saved text wins; empty falls back; line ends are tidied', () async {
      expect(
        await AgreementService.getTemplate(),
        AgreementService.defaultTemplate,
      );
      db.template = '   ';
      expect(
        await AgreementService.getTemplate(),
        AgreementService.defaultTemplate,
      );
      await AgreementService.saveTemplate(
        '# T  \r\nHello {StudentName}   \r\n\r\n',
      );
      expect(db.template, '# T\nHello {StudentName}');
    });

    test('the desktop checks', () async {
      await expectMessage(
        AgreementService.saveTemplate('  \n '),
        'Please enter the agreement text (or click Restore Default).',
      );
      await expectMessage(
        AgreementService.saveTemplate('Hi {Foo} {StudentName} {Bar}'),
        'The agreement uses {Foo}, {Bar}, which is not available. Available: '
        '{AgreementDate}, {StudentName}, {RelationPrefix}, {ParentName}, '
        '{Address}, {StudentMobile}, {ParentMobile}, {CollegeName}, '
        '{HostelName}, {HostelType}, {RoomNumber}, {BedNumber}, {BedsInRoom}, '
        '{CheckInDate}, {AnnualFee}, {AnnualRent}, {TransportFee}.',
      );
      expect(db.template, isNull);
    });
  });

  group('prepare', () {
    setUp(
      () => db.template = '''
Name {StudentName}, {RelationPrefix} {ParentName}, R/o {Address}.
Room {RoomNumber} bed {BedNumber} of {BedsInRoom} ({HostelType}) from {CheckInDate} on {AgreementDate}.
Fee {AnnualFee}; rent {AnnualRent}; transport {TransportFee}.
Phones {StudentMobile} {ParentMobile} at {CollegeName} of {HostelName}. {Unknown}''',
    );

    test('fills in the student, room and the fee of the year', () async {
      final d = await AgreementService.prepare(hostel, 1, today);
      expect(d.studentName, 'Aman Sharma');
      expect(d.parentName, 'Rakesh Sharma');
      final lines = d.filledText.split('\n');
      expect(
        lines[0],
        'Name ${bold('Aman Sharma')}, ${bold('S/o')} ${bold('Rakesh Sharma')}, '
        'R/o ${bold('12 Rajpur Road, Dehradun')}.',
      );
      expect(
        lines[1],
        'Room ${bold('101')} bed ${bold('2')} of ${bold('three')} '
        '(${bold('Boys')}) from ${bold('05 Jul 2026')} on ${bold('06 Oct 2026')}.',
      );
      expect(
        lines[2],
        'Fee ${bold('92,000/- (Rupees Ninety Two Thousand Only)')}; '
        'rent ${bold('80,000/-')}; transport ${bold('12,000/-')}.',
      );
      expect(
        lines[3],
        'Phones ${bold('98765 43210')} ${bold('98111 22233')} at '
        '${bold('DAV College')} of ${bold('Boys Hostel')}. {Unknown}',
      );
      expect(d.signatures, isNull);
    });

    test('what was not entered is a dotted line; girls get D/o', () async {
      final d = await AgreementService.prepare(hostel, 2, today);
      const dots = '................................';
      final lines = d.filledText.split('\n');
      expect(lines[0], contains('${bold('D/o')} ${bold(dots)}'));
      expect(lines[0], contains('R/o ${bold(dots)}.'));
      expect(lines[1], contains('(${bold('Girls')})'));
      expect(lines[1], contains('of ${bold('two')}'));
      // No fee at all: three dotted lines.
      expect(
        lines[2],
        'Fee ${bold(dots)}; rent ${bold(dots)}; transport ${bold(dots)}.',
      );
      expect(
        d.parentName,
        'Gita',
        reason: 'the mother when there is no father',
      );
    });

    test('a student who left: the last room and his latest fee', () async {
      final d = await AgreementService.prepare(hostel, 4, today);
      final lines = d.filledText.split('\n');
      expect(
        lines[1],
        contains('Room ${bold('55')} bed ${bold('3')} of ${bold('5')}'),
      );
      expect(
        lines[2],
        contains('Fee ${bold('60,000/- (Rupees Sixty Thousand Only)')}'),
      );
    });

    test('someone never in a room, or not there, is explained', () async {
      await expectMessage(
        AgreementService.prepare(hostel, 3, today),
        'Karan has not been checked in to a room yet. Check in the student first.',
      );
      await expectMessage(
        AgreementService.prepare(hostel, 99, today),
        'Please select the student.',
      );
    });

    test('file name', () async {
      final d = await AgreementService.prepare(hostel, 1, today);
      expect(
        AgreementService.fileName(d, today),
        'Agreement_Aman-Sharma_2026-10-06.pdf',
      );
    });
  });

  group('signatures', () {
    test(
      'Save needs a signature; names and the owner for the hostel',
      () async {
        await expectMessage(
          AgreementSignatureService.save(
            1,
            1,
            {for (final s in AgreementSigner.values) s: null},
            '',
            today,
            keepOwnerForHostel: true,
          ).then((_) {}),
          'Please sign at least one box before saving.',
        );
        await AgreementSignatureService.save(
          1,
          1,
          {
            AgreementSigner.student: png,
            AgreementSigner.owner: png,
            AgreementSigner.parent: null,
            AgreementSigner.witness: null,
          },
          ' Mohan ',
          today,
          keepOwnerForHostel: true,
        );
        expect(db.files.keys.toSet(), {
          'S1_student.png',
          'S1_owner.png',
          'H1_owner.png',
        });
        expect(db.removed, ['S1_parent.png', 'S1_witness.png']);
        expect(db.signing[1], (date: DateTime(2026, 10, 6), witness: 'Mohan'));
      },
    );

    test(
      'the hostel owner signature fills every student\'s agreement',
      () async {
        db.files['H1_owner.png'] = png;
        final sigs = await AgreementSignatureService.get(2, 1);
        expect(sigs.owner, png);
        expect(sigs.isSigned, isTrue);
        await AgreementSignatureService.save(
          2,
          1,
          {AgreementSigner.owner: png},
          '',
          today,
          keepOwnerForHostel: false,
        );
        expect(db.files.containsKey('S2_owner.png'), isTrue);
      },
    );

    test('an agreement with signatures shows who signed and when', () async {
      db.files['S1_student.png'] = png;
      db.signing[1] = (date: DateTime(2026, 10, 1), witness: 'Mohan');
      final d = await AgreementService.prepare(hostel, 1, today);
      expect(d.signatures!.student, png);
      expect(d.signatures!.witnessName, 'Mohan');
      expect(d.signatures!.signedDate, DateTime(2026, 10, 1));
    });

    test('deleting a student removes their signature files', () async {
      await AgreementSignatureService.deleteForStudent(7);
      expect(db.removed, [
        'S7_owner.png',
        'S7_student.png',
        'S7_parent.png',
        'S7_witness.png',
      ]);
    });
  });

  group('photo', () {
    test('the student photo goes on the agreement', () async {
      final photo = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 480, height: 600)),
      );
      students[0] = Student(
        studentId: 1,
        hostelId: 1,
        studentName: 'Aman Sharma',
        gender: 'Male',
        admissionDate: DateTime(2026, 7, 1),
        photoPath: 'S1_photo_1.jpg',
      );
      addTearDown(
        () => students[0] = student(1, 'Aman Sharma', father: 'Rakesh Sharma'),
      );
      StudentFileService.clearCache();
      StudentFileRepository.useInstance(_OnePhoto(photo));
      addTearDown(() => StudentFileRepository.useInstance(null));
      final d = await AgreementService.prepare(hostel, 1, today);
      expect(d.photo, photo);
      final bytes = await AgreementPdf.build(d);
      expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
      // Without the photo file the agreement is still made.
      StudentFileService.clearCache();
      StudentFileRepository.useInstance(_OnePhoto(null));
      expect((await AgreementService.prepare(hostel, 1, today)).photo, isNull);
    });
  });

  group('PDF', () {
    test(
      'a real PDF, over more than one page, with a bad image ignored',
      () async {
        final d = await AgreementService.prepare(hostel, 1, today);
        final bytes = await AgreementPdf.build(
          AgreementDocument(
            studentName: d.studentName,
            parentName: d.parentName,
            filledText: AgreementService.defaultTemplate,
            signatures: AgreementSignatures(
              student: png,
              parent: Uint8List.fromList([1, 2, 3]),
              witnessName: 'Mohan',
              signedDate: today,
            ),
          ),
        );
        expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
        expect(
          RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length,
          greaterThan(1),
        );
      },
    );
  });

  group('screens', () {
    Future<void> openStudents(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5400);
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

    Future<void> menu(WidgetTester tester, int id, String item) async {
      await tester.tap(find.byKey(Key('studentMenu_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('Agreement PDF is shared', (tester) async {
      final shared = <String>[];
      DocumentShare.useForTests((files, subject, text) async {
        shared.add('${files.single.name}|${files.single.bytes.length > 1000}');
      });
      await openStudents(tester);
      await menu(tester, 1, 'Agreement PDF');
      expect(shared, ['Agreement_Aman-Sharma_2026-10-06.pdf|true']);
    });

    testWidgets('a student not in a room is told so', (tester) async {
      await openStudents(tester);
      await menu(tester, 3, 'Agreement PDF');
      expect(
        find.text(
          'Karan has not been checked in to a room yet. Check in the student first.',
        ),
        findsOneWidget,
      );
      await menu(tester, 3, 'Sign Agreement');
      expect(find.textContaining('Sign Agreement:'), findsNothing);
    });

    testWidgets('the Agreement text icon opens the editor', (tester) async {
      await openStudents(tester);
      await tester.tap(find.byKey(const Key('agreementText')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Agreement Text'), findsOneWidget);
      expect(
        find.textContaining('SHRI BALAJI HOSTEL RESIDENCY AGREEMENT'),
        findsOneWidget,
      );
    });

    testWidgets('edit the text: refused, saved, restored', (tester) async {
      await openStudents(tester);
      await tester.tap(find.byKey(const Key('agreementText')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('agreementText')).last,
        'Hello {Nope}',
      );
      await tester.tap(find.byKey(const Key('saveAgreementText')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('uses {Nope}, which is not available'),
        findsOneWidget,
      );
      expect(db.template, isNull);
      await tester.enterText(
        find.byKey(const Key('agreementText')).last,
        '# Mine\nHello {StudentName}',
      );
      await tester.tap(find.byKey(const Key('saveAgreementText')));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(db.template, '# Mine\nHello {StudentName}');
      await tester.tap(find.byKey(const Key('restoreAgreement')));
      await tester.pump();
      expect(
        find.textContaining('SHRI BALAJI HOSTEL RESIDENCY AGREEMENT'),
        findsOneWidget,
      );
    });

    testWidgets('Sign Agreement: sign, save, and the PDF follows', (
      tester,
    ) async {
      SignatureController.rasterizer = (strokes, size) async => png;
      final shared = <String>[];
      DocumentShare.useForTests((files, subject, text) async {
        shared.add(files.single.name);
      });
      await openStudents(tester);
      await menu(tester, 1, 'Sign Agreement');
      expect(
        find.widgetWithText(AppBar, 'Sign Agreement: Aman Sharma'),
        findsOneWidget,
      );

      // Nothing signed: refused.
      await tester.tap(find.byKey(const Key('saveAndPdf')));
      await tester.pumpAndSettle();
      expect(
        find.text('Please sign at least one box before saving.'),
        findsOneWidget,
      );

      // Sign in the student box with a finger.
      final pad = find.byKey(const Key('pad_student'));
      await tester.dragFrom(
        tester.getCenter(pad) - const Offset(60, 0),
        const Offset(120, 30),
      );
      await tester.pump();
      await tester.enterText(find.byKey(const Key('witnessName')), 'Mohan');
      await tester.tap(find.byKey(const Key('saveAndPdf')));
      await tester.pumpAndSettle();

      expect(db.files.keys.toSet(), {'S1_student.png'});
      expect(db.signing[1]!.witness, 'Mohan');
      expect(shared, ['Agreement_Aman-Sharma_2026-10-06.pdf']);
    });

    testWidgets('Sign Agreement shows what was saved; Clear removes it', (
      tester,
    ) async {
      db.files['S1_student.png'] = png;
      db.signing[1] = (date: DateTime(2026, 10, 1), witness: 'Old Witness');
      await openStudents(tester);
      await menu(tester, 1, 'Sign Agreement');
      expect(find.text('Old Witness'), findsOneWidget);
      expect(
        find.text('Sign here'),
        findsNWidgets(3),
        reason: 'the student box is filled',
      );
      await tester.tap(find.byKey(const Key('clear_student')));
      await tester.pump();
      expect(find.text('Sign here'), findsNWidgets(4));
    });
  });

  testWidgets('the pad draws a real PNG', (tester) async {
    final c = SignatureController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SignaturePad(controller: c)),
      ),
    );
    await tester.dragFrom(
      tester.getCenter(find.byType(SignaturePad)),
      const Offset(80, 20),
    );
    final bytes = await tester.runAsync(c.toPng);
    expect(bytes!.sublist(1, 4), [0x50, 0x4E, 0x47]);
    c.clear();
    expect(await c.toPng(), isNull);
  });
}

class _OnePhoto extends StudentFileRepository {
  _OnePhoto(this.photo);
  final Uint8List? photo;
  @override
  Future<Uint8List> download(String name) async =>
      photo ?? (throw Exception('missing'));
}
