import 'dart:typed_data';

/// Who signs the residency agreement, in the order of the signature lines.
enum AgreementSigner { owner, student, parent, witness }

/// The signatures of one student's agreement: PNG images (null when that
/// person has not signed), the witness's name and the date it was signed.
class AgreementSignatures {
  const AgreementSignatures({
    this.owner,
    this.student,
    this.parent,
    this.witness,
    this.witnessName = '',
    this.signedDate,
  });

  static const none = AgreementSignatures();

  final Uint8List? owner;
  final Uint8List? student;
  final Uint8List? parent;
  final Uint8List? witness;
  final String witnessName;
  final DateTime? signedDate;

  Uint8List? of(AgreementSigner signer) => switch (signer) {
    AgreementSigner.owner => owner,
    AgreementSigner.student => student,
    AgreementSigner.parent => parent,
    AgreementSigner.witness => witness,
  };

  bool get isSigned =>
      owner != null || student != null || parent != null || witness != null;
}

/// The agreement text with the student's details filled in, ready to be
/// written as a PDF. Filled in values sit between [AgreementDocument.valueStart]
/// and [AgreementDocument.valueEnd] so the PDF prints them in bold.
class AgreementDocument {
  const AgreementDocument({
    required this.studentName,
    required this.parentName,
    required this.filledText,
    this.photo,
    this.signatures,
  });

  static const valueStart = '\u0001';
  static const valueEnd = '\u0002';

  final String studentName;
  final String parentName;
  final String filledText;

  /// The student's photo, printed at the top; null when there is none.
  final Uint8List? photo;

  /// Signatures made on screen; null when not signed.
  final AgreementSignatures? signatures;
}
