import '../data/agreement_repository.dart';
import '../data/allocation_repository.dart';
import '../data/billing_repository.dart';
import '../data/room_repository.dart';
import '../data/student_repository.dart';
import '../models/agreement.dart';
import '../models/allocation.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/room.dart';
import '../models/student.dart';
import 'agreement_defaults.dart';
import 'agreement_signature_service.dart';
import 'date_format.dart';
import 'money.dart';
import 'report_service.dart';
import 'validators.dart';

/// The residency agreement (client decision): the client's text with the
/// student's name, father, address, room, bed and annual fee filled in, as
/// the desktop AgreementService. The text is editable (app_setting
/// "Agreement.Text"); a new installation starts with the client's sample.
class AgreementService {
  /// The {Fields} that can be used in the agreement text.
  static const fields = [
    'AgreementDate',
    'StudentName',
    'RelationPrefix',
    'ParentName',
    'Address',
    'StudentMobile',
    'ParentMobile',
    'CollegeName',
    'HostelName',
    'HostelType',
    'RoomNumber',
    'BedNumber',
    'BedsInRoom',
    'CheckInDate',
    'AnnualFee',
    'AnnualRent',
    'TransportFee',
  ];

  static final _fieldPattern = RegExp(r'\{([A-Za-z]+)\}');

  /// Lines trimmed at the end and the text trimmed, with \n line ends.
  static String normalise(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .trim();

  static String get defaultTemplate => normalise(agreementDefaultText);

  static Future<String> getTemplate() async {
    final saved = await AgreementRepository.instance.getTemplate();
    final text = saved == null ? '' : normalise(saved);
    return text.isEmpty ? defaultTemplate : text;
  }

  /// Checks and saves the agreement text.
  static Future<void> saveTemplate(String text) async {
    final clean = normalise(text);
    if (clean.trim().isEmpty) {
      throw const ValidationException(
        'Please enter the agreement text (or click Restore Default).',
      );
    }
    final unknown = {
      for (final m in _fieldPattern.allMatches(clean))
        if (!fields.contains(m.group(1))) '{${m.group(1)}}',
    }.toList();
    if (unknown.isNotEmpty) {
      throw ValidationException(
        'The agreement uses ${unknown.join(', ')}, which is not available. '
        'Available: ${fields.map((f) => '{$f}').join(', ')}.',
      );
    }
    await AgreementRepository.instance.saveTemplate(clean);
  }

  static String _t(String? s) => (s ?? '').trim();

  /// The agreement for the student's current room and bed (or the last room,
  /// for a student who has left).
  static Future<AgreementDocument> prepare(
    Hostel hostel,
    int studentId,
    DateTime agreementDate,
  ) async {
    final id = hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      StudentRepository.instance.getForHostel(id),
      AllocationRepository.instance.getForHostel(id, includeHistory: true),
      RoomRepository.instance.getForHostel(id),
      billing.getInvoices(id),
      billing.getAcademicYearStartMonth(),
      getTemplate(),
    ]);
    final student = (r[0] as List<Student>)
        .where((s) => s.studentId == studentId)
        .firstOrNull;
    if (student == null) {
      throw const ValidationException('Please select the student.');
    }
    final stays =
        (r[1] as List<RoomAllocation>)
            .where((a) => a.studentId == studentId)
            .toList()
          ..sort((a, b) {
            final d = a.checkInDate.compareTo(b.checkInDate);
            return d != 0 ? d : a.allocationId.compareTo(b.allocationId);
          });
    final allocation =
        stays.where((a) => a.isCurrent).firstOrNull ?? stays.lastOrNull;
    if (allocation == null) {
      throw ValidationException(
        '${student.studentName} has not been checked in to a room yet. '
        'Check in the student first.',
      );
    }
    final room = (r[2] as List<Room>)
        .where((x) => x.roomId == allocation.roomId)
        .firstOrNull;
    if (room == null) {
      throw const ValidationException("The student's room no longer exists.");
    }

    // The fee of the academic year of the agreement, or the student's latest
    // fee.
    final month = r[4] as int;
    final mine =
        (r[3] as List<Invoice>).where((i) => i.studentId == studentId).toList()
          ..sort((a, b) => b.academicYear.compareTo(a.academicYear));
    final year = AcademicYear.of(agreementDate, month);
    final fee =
        mine.where((i) => i.academicYear == year).firstOrNull ??
        mine.firstOrNull;

    final values = <String, String>{
      'AgreementDate': formatDate(agreementDate),
      'StudentName': student.studentName,
      'RelationPrefix': switch (student.gender) {
        RoomGender.male => 'S/o',
        RoomGender.female => 'D/o',
        _ => 'D/o, S/o',
      },
      // Details not entered (only name and gender are required) print as a
      // dotted line to fill in by hand.
      'ParentName': _t(student.fatherName),
      'Address': _t(student.address).replaceAll(RegExp(r'\r\n|\r|\n'), ', '),
      'StudentMobile': _t(student.mobile),
      'ParentMobile': _t(student.fatherMobile),
      'CollegeName': _t(student.collegeName),
      'HostelName': hostel.hostelName,
      'HostelType': room.gender == RoomGender.female ? 'Girls' : 'Boys',
      'RoomNumber': room.roomNumber,
      'BedNumber': allocation.bedNumber?.toString() ?? '',
      'BedsInRoom': switch (room.capacity) {
        1 => 'one',
        2 => 'two',
        3 => 'three',
        4 => 'four',
        _ => '${room.capacity}',
      },
      'CheckInDate': formatDate(allocation.checkInDate),
      'AnnualFee': fee == null
          ? ''
          : '${Money.whole(fee.totalAmount)}/- (${Money.inWords(fee.totalAmount)})',
      'AnnualRent': fee == null ? '' : '${Money.whole(fee.roomRent)}/-',
      'TransportFee': fee == null
          ? ''
          : '${Money.whole(fee.transportAmount)}/-',
    };

    final filled = (r[5] as String).replaceAllMapped(_fieldPattern, (m) {
      final value = values[m.group(1)];
      if (value == null) return m.group(0)!;
      // A missing value leaves a dotted line to fill in by hand, as on the
      // printed form.
      final shown = value.trim().isNotEmpty
          ? value.trim()
          : '................................';
      return '${AgreementDocument.valueStart}$shown${AgreementDocument.valueEnd}';
    });

    final signatures = await AgreementSignatureService.get(
      studentId,
      student.hostelId,
    );
    return AgreementDocument(
      studentName: student.studentName,
      parentName: _t(student.fatherName).isNotEmpty
          ? _t(student.fatherName)
          : _t(student.motherName),
      filledText: filled,
      signatures: signatures.isSigned ? signatures : null,
    );
  }

  /// "Agreement_Aman-Sharma_2026-10-06.pdf".
  static String fileName(AgreementDocument d, DateTime date) =>
      'Agreement_${ReportService.safeName(d.studentName)}_${isoDate(date)}.pdf';
}
