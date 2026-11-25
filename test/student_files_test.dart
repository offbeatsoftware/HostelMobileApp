import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_mobile_app/data/agreement_repository.dart';
import 'package:hostel_mobile_app/data/student_file_repository.dart';
import 'package:hostel_mobile_app/data/student_repository.dart';
import 'package:hostel_mobile_app/models/hostel.dart';
import 'package:hostel_mobile_app/models/student.dart';
import 'package:hostel_mobile_app/screens/student_edit_screen.dart';
import 'package:hostel_mobile_app/services/document_share.dart';
import 'package:hostel_mobile_app/services/student_file_service.dart';
import 'package:hostel_mobile_app/services/student_service.dart';
import 'package:hostel_mobile_app/services/validators.dart';
import 'package:hostel_mobile_app/theme/app_theme.dart';
import 'package:hostel_mobile_app/widgets/student_avatar.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

Uint8List jpg(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

Uint8List png(int w, int h) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

img.Image decode(Uint8List b) => img.decodeImage(b)!;

final pdf = Uint8List.fromList([...'%PDF-1.4 hello'.codeUnits]);

class MemoryFiles extends StudentFileRepository {
  final files = <String, Uint8List>{};
  final uploads = <String>[];
  final paths = <Map<String, Object?>>[];
  final removed = <String>[];
  var downloads = 0;
  var failUpload = false;

  @override
  Future<Uint8List> download(String name) async {
    downloads++;
    return files[name] ?? (throw Exception('missing'));
  }

  @override
  Future<void> upload(String name, Uint8List bytes, String contentType) async {
    if (failUpload) throw Exception('offline');
    uploads.add('$name|$contentType');
    files[name] = bytes;
  }

  @override
  Future<void> remove(List<String> names) async {
    removed.addAll(names);
    names.forEach(files.remove);
  }

  @override
  Future<void> setPaths(
    int studentId, {
    bool photo = false,
    String? photoPath,
    bool aadhaar = false,
    String? aadhaarCardPath,
  }) async => paths.add({
    'id': studentId,
    if (photo) 'photo': photoPath,
    if (aadhaar) 'aadhaar': aadhaarCardPath,
  });
}

class SavingStudents extends StudentRepository {
  final saved = <Map<String, Object?>>[];
  final deleted = <int>[];
  final purged = <int>[];

  @override
  Future<int> save({
    int? studentId,
    required int hostelId,
    required Map<String, Object?> data,
  }) async {
    saved.add({'id': studentId, ...data});
    return studentId ?? 7;
  }

  @override
  Future<void> delete(int studentId) async => deleted.add(studentId);

  @override
  Future<void> deletePermanently(int studentId, String reason) async =>
      purged.add(studentId);
}

class NoAgreements extends AgreementRepository {
  @override
  Future<void> remove(List<String> names) async {}
}

Student student({String? photo, String? aadhaar, String status = 'Active'}) =>
    Student(
      studentId: 3,
      hostelId: 1,
      studentName: 'Ravi Kumar',
      gender: 'Male',
      admissionDate: DateTime(2026, 7, 1),
      photoPath: photo,
      aadhaarCardPath: aadhaar,
      status: status,
    );

Future<void> expectMessage(Future<void> f, String message) => expectLater(
  f,
  throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  late MemoryFiles files;

  setUp(() {
    files = MemoryFiles();
    StudentFileRepository.useInstance(files);
    StudentFileService.inBackground = false;
    StudentFileService.clearCache();
  });
  tearDown(() {
    StudentFileRepository.useInstance(null);
    StudentRepository.useInstance(null);
    AgreementRepository.useInstance(null);
    StudentFileService.inBackground = true;
    StudentFileService.usePickers(
      image: (_) async => null,
      pdf: () async => null,
    );
    DocumentShare.useForTests(null);
  });

  group('shrinking', () {
    test('a photo is cropped to passport shape and shrunk', () {
      final wide = decode(StudentFileService.shrinkPhoto(jpg(1000, 700))!);
      expect((wide.width, wide.height), (480, 600));
      final tall = decode(StudentFileService.shrinkPhoto(jpg(600, 1500))!);
      expect((tall.width, tall.height), (480, 600));
      final small = decode(StudentFileService.shrinkPhoto(jpg(160, 200))!);
      expect((small.width, small.height), (160, 200));
      expect(
        StudentFileService.shrinkPhoto(Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });

    test('a scan keeps its shape, at most 1600 on the long side', () {
      final big = decode(StudentFileService.shrinkScan(png(3000, 2000))!);
      expect((big.width, big.height), (1600, 1067));
      final upright = decode(StudentFileService.shrinkScan(jpg(1000, 2400))!);
      expect(upright.height, 1600);
      final small = decode(StudentFileService.shrinkScan(jpg(300, 200))!);
      expect((small.width, small.height), (300, 200));
    });
  });

  group('checks', () {
    test('photo: the desktop messages', () async {
      await expectMessage(
        StudentFileService.preparePhoto('a.gif', jpg(10, 10)),
        'The photo must be one of these file types: .jpg, .jpeg, .png, .bmp.',
      );
      await expectMessage(
        StudentFileService.preparePhoto('a.jpg', Uint8List(0)),
        'The selected photo is empty.',
      );
      await expectMessage(
        StudentFileService.preparePhoto('a.jpg', Uint8List(41 * 1024 * 1024)),
        'The photo is too large. The maximum size is 5 MB.',
      );
      await expectMessage(
        StudentFileService.preparePhoto('a.jpg', Uint8List.fromList([1, 2, 3])),
        'The selected photo could not be read. Please choose a JPG or PNG picture.',
      );
      // No extension (some galleries): read by content.
      final ok = await StudentFileService.preparePhoto('IMG_1', png(300, 300));
      expect(decode(ok).height, 300);
    });

    test('Aadhaar: PDF kept, picture shrunk, bad ones refused', () async {
      final p = await StudentFileService.prepareAadhaar('card.PDF', pdf);
      expect((p.extension, p.isPdf, p.bytes), ('.pdf', true, pdf));
      final i = await StudentFileService.prepareAadhaar(
        'c.png',
        png(2400, 1800),
      );
      expect((i.extension, i.isPdf), ('.jpg', false));
      expect(decode(i.bytes).width, 1600);
      await expectMessage(
        StudentFileService.prepareAadhaar(
          'c.pdf',
          Uint8List.fromList([1, 2, 3, 4, 5]),
        ),
        'The selected Aadhaar card file is not a valid PDF.',
      );
      await expectMessage(
        StudentFileService.prepareAadhaar(
          'c.pdf',
          Uint8List(5 * 1024 * 1024 + 1),
        ),
        'The Aadhaar card file is too large. The maximum size is 5 MB.',
      );
      await expectMessage(
        StudentFileService.prepareAadhaar('c.bmp', png(10, 10)),
        'The Aadhaar card file must be one of these file types: .jpg, .jpeg, .png, .pdf.',
      );
    });
  });

  group('saving', () {
    final now = DateTime(2026, 11, 25, 10, 30, 5);

    test(
      'a new photo and scan are uploaded, named, saved and the old ones deleted',
      () async {
        final old = student(
          photo: 'S3_photo_old.jpg',
          aadhaar: 'S3_aadhaar_old.pdf',
        );
        await StudentFileService.apply(
          3,
          old,
          StudentFileChanges(
            newPhoto: jpg(50, 50),
            newAadhaar: AadhaarFile(pdf, '.pdf'),
          ),
          now: now,
        );
        expect(files.uploads, [
          'S3_photo_20261125103005.jpg|image/jpeg',
          'S3_aadhaar_20261125103005.pdf|application/pdf',
        ]);
        expect(files.paths.single, {
          'id': 3,
          'photo': 'S3_photo_20261125103005.jpg',
          'aadhaar': 'S3_aadhaar_20261125103005.pdf',
        });
        expect(files.removed, ['S3_photo_old.jpg', 'S3_aadhaar_old.pdf']);
      },
    );

    test('only what changed is touched; remove clears the name', () async {
      final old = student(
        photo: 'S3_photo_old.jpg',
        aadhaar: 'S3_aadhaar_old.jpg',
      );
      await StudentFileService.apply(
        3,
        old,
        const StudentFileChanges(removePhoto: true),
      );
      expect(files.paths.single, {'id': 3, 'photo': null});
      expect(files.removed, ['S3_photo_old.jpg']);
      expect(files.uploads, isEmpty);
    });

    test('nothing changed: nothing happens', () async {
      await StudentFileService.apply(3, student(), const StudentFileChanges());
      expect(files.uploads, isEmpty);
      expect(files.paths, isEmpty);
    });

    test('a failed upload changes nothing on the student', () async {
      files.failUpload = true;
      await expectLater(
        StudentFileService.apply(
          3,
          student(photo: 'old.jpg'),
          StudentFileChanges(newPhoto: jpg(9, 9)),
          now: now,
        ),
        throwsA(isA<Exception>()),
      );
      expect(files.paths, isEmpty);
      expect(files.removed, isEmpty, reason: 'the old photo stays');
    });

    test('a failed save of the names removes the new uploads', () async {
      final bad = _FailingPaths();
      StudentFileRepository.useInstance(bad);
      await expectLater(
        StudentFileService.apply(
          3,
          null,
          StudentFileChanges(newPhoto: jpg(9, 9)),
          now: now,
        ),
        throwsA(isA<Exception>()),
      );
      expect(bad.removed, ['S3_photo_20261125103005.jpg']);
    });
  });

  group('showing', () {
    test('loaded once, kept, and a missing file is null', () async {
      files.files['a.jpg'] = jpg(10, 10);
      expect(await StudentFileService.load('a.jpg'), isNotNull);
      expect(await StudentFileService.load('a.jpg'), isNotNull);
      expect(files.downloads, 1);
      expect(await StudentFileService.load('gone.jpg'), isNull);
      expect(await StudentFileService.load(null), isNull);
      expect(await StudentFileService.load(''), isNull);
    });

    testWidgets('the avatar shows the photo, else the first letter', (
      tester,
    ) async {
      files.files['a.jpg'] = jpg(40, 50);
      Future<void> show(String? path) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentAvatar(name: 'amit', photoPath: path),
          ),
        ),
      );
      await show('a.jpg');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('studentPhoto')), findsOneWidget);
      await show(null);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      await show('missing.jpg');
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('deleting', () {
    test('delete and delete permanently remove the files too', () async {
      final db = SavingStudents();
      StudentRepository.useInstance(db);
      AgreementRepository.useInstance(NoAgreements());
      final s = student(
        photo: 'S3_photo_1.jpg',
        aadhaar: 'S3_aadhaar_1.pdf',
        status: 'Left',
      );
      await StudentService.delete(3, student: s);
      expect(files.removed, ['S3_photo_1.jpg', 'S3_aadhaar_1.pdf']);
      files.removed.clear();
      await StudentService.deletePermanently(s, 'old');
      expect(files.removed, ['S3_photo_1.jpg', 'S3_aadhaar_1.pdf']);
      expect(db.purged, [3]);
    });
  });

  group('student form', () {
    late SavingStudents db;

    setUp(() {
      db = SavingStudents();
      StudentRepository.useInstance(db);
    });

    Future<void> open(WidgetTester tester, {Student? s}) async {
      tester.view.physicalSize = const Size(1080, 9000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const Key('go'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StudentEditScreen(
                        hostel: const Hostel(
                          hostelId: 1,
                          hostelName: 'Boys Hostel',
                        ),
                        colleges: const [],
                        student: s,
                        today: DateTime(2026, 11, 25),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSave(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('studentName')), 'Ravi');
      await tester.tap(find.byKey(const Key('studentGender')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a chosen photo is shown, then uploaded when the student is saved',
      (tester) async {
        StudentFileService.usePickers(
          image: (source) async {
            expect(source, ImageSource.gallery);
            return (name: 'me.jpg', bytes: jpg(800, 800));
          },
        );
        await open(tester);
        await tester.tap(find.byKey(const Key('choosePhoto')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('newPhotoPreview')), findsOneWidget);
        expect(
          files.uploads,
          isEmpty,
          reason: 'nothing is uploaded before Save',
        );
        await fillAndSave(tester);
        expect(db.saved.single['student_name'], 'Ravi');
        expect(
          files.uploads.single,
          matches(RegExp(r'^S7_photo_\d{14}\.jpg\|image/jpeg$')),
        );
        expect(files.paths.single['id'], 7);
        expect(
          find.byKey(const Key('go')),
          findsOneWidget,
          reason: 'the form closed',
        );
      },
    );

    testWidgets('the camera button uses the camera; a wrong file is refused', (
      tester,
    ) async {
      var source = ImageSource.gallery;
      StudentFileService.usePickers(
        image: (s) async {
          source = s;
          return (name: 'x.gif', bytes: jpg(10, 10));
        },
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('takePhoto')));
      await tester.pumpAndSettle();
      expect(source, ImageSource.camera);
      expect(
        find.text(
          'The photo must be one of these file types: .jpg, .jpeg, .png, .bmp.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('newPhotoPreview')), findsNothing);
    });

    testWidgets('an existing photo can be removed', (tester) async {
      files.files['S3_photo_old.jpg'] = jpg(40, 50);
      await open(tester, s: student(photo: 'S3_photo_old.jpg'));
      expect(find.byKey(const Key('studentPhoto')), findsOneWidget);
      await tester.tap(find.byKey(const Key('removePhoto')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('studentPhoto')), findsNothing);
      await tester.tap(find.byKey(const Key('saveStudent')));
      await tester.pumpAndSettle();
      expect(files.paths.single, {'id': 3, 'photo': null});
      expect(files.removed, ['S3_photo_old.jpg']);
    });

    testWidgets('Aadhaar: choose a PDF, see it, remove it', (tester) async {
      StudentFileService.usePickers(
        pdf: () async => (name: 'card.pdf', bytes: pdf),
      );
      final shared = <String>[];
      DocumentShare.useForTests((f, s, t) async => shared.add(f.single.name));
      await open(tester);
      expect(find.text('No Aadhaar card saved.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choosePdf')));
      await tester.pumpAndSettle();
      expect(
        find.text('A PDF is chosen (saved when you save the student).'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('viewAadhaar')));
      await tester.pumpAndSettle();
      expect(shared, ['Aadhaar_new.pdf']);
      await fillAndSave(tester);
      expect(
        files.uploads.single,
        matches(RegExp(r'^S7_aadhaar_\d{14}\.pdf\|application/pdf$')),
      );
      expect(files.paths.single.containsKey('photo'), isFalse);
    });

    testWidgets('a saved Aadhaar picture opens full size', (tester) async {
      files.files['S3_aadhaar_1.jpg'] = jpg(60, 40);
      await open(tester, s: student(aadhaar: 'S3_aadhaar_1.jpg'));
      expect(find.text('The Aadhaar card is saved.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('viewAadhaar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pictureView')), findsOneWidget);
    });

    testWidgets('a failed upload still saves the student and says so', (
      tester,
    ) async {
      files.failUpload = true;
      StudentFileService.usePickers(
        image: (_) async => (name: 'me.jpg', bytes: jpg(100, 100)),
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('choosePhoto')));
      await tester.pumpAndSettle();
      await fillAndSave(tester);
      expect(db.saved.length, 1);
      expect(
        find.textContaining(
          'The student was saved, but the photo or Aadhaar card could not be uploaded',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('go')), findsOneWidget);
    });
  });
}

class _FailingPaths extends MemoryFiles {
  @override
  Future<void> setPaths(
    int studentId, {
    bool photo = false,
    String? photoPath,
    bool aadhaar = false,
    String? aadhaarCardPath,
  }) async => throw Exception('db down');
}
