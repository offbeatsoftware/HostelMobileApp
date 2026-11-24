import 'dart:typed_data';

import '../data/agreement_repository.dart';
import '../models/agreement.dart';
import 'date_format.dart';
import 'validators.dart';

/// Agreements signed on screen (client decision): the student, the parent or
/// guardian, the hostel owner and a witness sign with a finger or pen. Kept
/// as PNG images: S12_student.png, S12_parent.png, S12_witness.png and
/// S12_owner.png for student 12, and H3_owner.png, the owner's signature
/// saved once for hostel 3 and used on every agreement of that hostel.
class AgreementSignatureService {
  static String _file(int studentId, AgreementSigner s) =>
      'S${studentId}_${s.name}.png';

  static String _ownerFile(int hostelId) => 'H${hostelId}_owner.png';

  static Future<AgreementSignatures> get(int studentId, int hostelId) async {
    final repo = AgreementRepository.instance;
    Set<String> own;
    Set<String> hostelFiles;
    ({DateTime date, String witness})? signing;
    try {
      own = await repo.listNames('S${studentId}_');
      hostelFiles = await repo.listNames(_ownerFile(hostelId));
      signing = await repo.getSigning(studentId);
    } catch (_) {
      // Without the signatures script (016) there are no signatures.
      return AgreementSignatures.none;
    }
    Future<Uint8List?> load(String name, Set<String> where) async =>
        where.contains(name) ? await repo.download(name) : null;

    return AgreementSignatures(
      owner:
          await load(_file(studentId, AgreementSigner.owner), own) ??
          await load(_ownerFile(hostelId), hostelFiles),
      student: await load(_file(studentId, AgreementSigner.student), own),
      parent: await load(_file(studentId, AgreementSigner.parent), own),
      witness: await load(_file(studentId, AgreementSigner.witness), own),
      witnessName: signing?.witness ?? '',
      signedDate: signing?.date,
    );
  }

  /// Saves the signatures given (null removes that signature) with the
  /// signing date and the witness's name. With [keepOwnerForHostel] the
  /// owner's signature is also saved for the whole hostel.
  static Future<AgreementSignatures> save(
    int studentId,
    int hostelId,
    Map<AgreementSigner, Uint8List?> signatures,
    String witnessName,
    DateTime signedDate, {
    required bool keepOwnerForHostel,
  }) async {
    final witness = Validators.clean(witnessName);
    Validators.checkLength(witness, 100, 'Witness name');
    if (signatures.values.every((s) => s == null)) {
      throw const ValidationException(
        'Please sign at least one box before saving.',
      );
    }
    final repo = AgreementRepository.instance;
    final remove = <String>[];
    for (final e in signatures.entries) {
      final name = _file(studentId, e.key);
      if (e.value == null) {
        remove.add(name);
        continue;
      }
      await repo.upload(name, e.value!);
      if (e.key == AgreementSigner.owner && keepOwnerForHostel) {
        await repo.upload(_ownerFile(hostelId), e.value!);
      }
    }
    await repo.remove(remove);
    await repo.saveSigning(studentId, isoDate(signedDate), witness);
    return get(studentId, hostelId);
  }

  /// Removes all of a student's signatures (the database row goes with the
  /// student); used when the student is deleted for good.
  static Future<void> deleteForStudent(int studentId) async {
    final repo = AgreementRepository.instance;
    await repo.remove([
      for (final s in AgreementSigner.values) _file(studentId, s),
    ]);
  }
}
