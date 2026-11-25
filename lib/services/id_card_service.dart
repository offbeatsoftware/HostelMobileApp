import '../data/allocation_repository.dart';
import '../data/billing_repository.dart';
import '../data/student_repository.dart';
import '../models/allocation.dart';
import '../models/hostel.dart';
import '../models/id_card.dart';
import '../models/invoice.dart';
import '../models/student.dart';
import 'date_format.dart';
import 'money.dart';
import 'student_file_service.dart';
import 'validators.dart';

/// Student and transport I-cards (client decisions): any active student can
/// get a student I-card; a transport I-card only a student whose fee for the
/// academic year includes transport. The admin types the "Valid till" date
/// each time cards are printed; it starts as the last day of the academic
/// year. As the desktop IdCardService.
class IdCardService {
  /// The "Valid till" date offered when printing: the last day of the
  /// academic year.
  static DateTime defaultValidTill(DateTime today, int startMonth) =>
      AcademicYear.end(AcademicYear.of(today, startMonth), startMonth);

  static String _t(String? s) => (s ?? '').trim();

  /// The cards for the chosen students, valid till the given date (the end
  /// of the academic year when null); students who cannot get one are
  /// returned as problems.
  static Future<({List<IdCard> cards, List<String> problems})> prepare(
    Hostel hostel,
    List<int> studentIds, {
    required bool transport,
    required DateTime today,
    DateTime? validTill,
  }) async {
    if (studentIds.isEmpty) {
      throw const ValidationException('Please select one or more students.');
    }
    final id = hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      StudentRepository.instance.getForHostel(id),
      AllocationRepository.instance.getForHostel(id),
      billing.getInvoices(id),
      billing.getAcademicYearStartMonth(),
    ]);
    final startMonth = r[3] as int;
    final validUntil = dateOnly(
      validTill ?? defaultValidTill(today, startMonth),
    );
    if (validUntil.isBefore(dateOnly(today))) {
      throw const ValidationException(
        'The Valid till date cannot be in the past.',
      );
    }

    final students = {for (final s in r[0] as List<Student>) s.studentId: s};
    final rooms = {
      for (final a in (r[1] as List<RoomAllocation>).where((a) => a.isCurrent))
        a.studentId: a,
    };
    final invoices = r[2] as List<Invoice>;
    final year = AcademicYear.of(today, startMonth);
    final yearText = AcademicYear.label(year, startMonth);

    final cards = <IdCard>[];
    final problems = <String>[];
    for (final studentId in studentIds) {
      final student = students[studentId];
      if (student == null) continue;
      if (student.status != StudentStatus.active) {
        problems.add('${student.studentName}: has left the hostel.');
        continue;
      }
      if (transport &&
          !invoices.any(
            (i) =>
                i.studentId == studentId &&
                i.academicYear == year &&
                i.transportAmount > 0,
          )) {
        problems.add(
          '${student.studentName}: no transport in the $yearText fee.',
        );
        continue;
      }
      final photo = await StudentFileService.load(student.photoPath);
      if (photo == null) {
        problems.add(
          '${student.studentName}: no photo (the card has an empty photo '
          'box). Add one on the Students screen.',
        );
      }
      final room = rooms[studentId];
      cards.add(
        IdCard(
          hostelName: hostel.hostelName,
          hostelPhone: _t(hostel.phone),
          studentName: student.studentName,
          fatherName: _t(student.fatherName),
          collegeName: _t(student.collegeName),
          roomText: room == null ? '' : 'Room ${room.roomAndBed}',
          studentMobile: _t(student.mobile),
          fatherMobile: _t(student.fatherMobile),
          photo: photo,
          validTill: validUntil,
          academicYear: yearText,
        ),
      );
    }
    return (cards: cards, problems: problems);
  }

  /// "ICards_2026-10-12.pdf" or "TransportCards_2026-10-12.pdf".
  static String fileName(bool transport, DateTime today) =>
      '${transport ? 'TransportCards' : 'ICards'}_${isoDate(today)}.pdf';
}
