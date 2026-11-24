import '../models/invoice.dart';
import '../models/student.dart';
import 'attendance_service.dart';
import 'message_text.dart';
import 'money.dart';
import 'validators.dart';

/// A student with fees pending, for the Fee Reminders screen.
class FeeDue {
  const FeeDue({
    required this.studentId,
    required this.studentName,
    required this.invoices,
    this.roomNumber,
    this.fatherName,
    this.fatherMobile,
    this.parentName,
    this.parentMobile,
    this.parentRelation,
    this.lastReminder,
  });

  final int studentId;
  final String studentName;

  /// The invoices with an amount pending, oldest year first.
  final List<Invoice> invoices;
  final String? roomNumber;
  final String? fatherName;
  final String? fatherMobile;

  /// Who gets the reminder: the father, else the mother.
  final String? parentName;

  /// As WhatsApp needs it (91 and ten digits), or null.
  final String? parentMobile;
  final String? parentRelation;
  final DateTime? lastReminder;

  double get totalAmount => invoices.fold(0, (t, i) => t + i.totalAmount);
  double get paidAmount => invoices.fold(0, (t, i) => t + i.paidAmount);
  double get pendingAmount => invoices.fold(0, (t, i) => t + i.pendingAmount);

  /// "Rakesh Sharma, 98111 22233".
  String get fatherText => (fatherMobile ?? '').isNotEmpty
      ? '${fatherName ?? ''}, $fatherMobile'
      : (fatherName ?? '');
}

/// Fee reminders, as the desktop: every student with a pending fee (highest
/// first), and a WhatsApp reminder to the father (else the mother) with the
/// desktop's wording.
class FeeReminderService {
  static List<FeeDue> dues({
    required List<Invoice> invoices,
    required List<Student> students,
    required Map<int, DateTime> lastReminders,
  }) {
    final byId = {for (final s in students) s.studentId: s};
    final groups = <int, List<Invoice>>{};
    for (final i in invoices.where((i) => i.pendingAmount > 0)) {
      groups.putIfAbsent(i.studentId, () => []).add(i);
    }
    final list =
        [
          for (final e in groups.entries)
            () {
              final s = byId[e.key];
              final invs = e.value
                ..sort((a, b) {
                  final y = a.academicYear.compareTo(b.academicYear);
                  return y != 0 ? y : a.invoiceId.compareTo(b.invoiceId);
                });
              final parent = s == null ? null : recipient(s);
              return FeeDue(
                studentId: e.key,
                studentName: s?.studentName ?? invs.first.studentName,
                invoices: invs,
                roomNumber: s?.roomNumber,
                fatherName: s?.fatherName,
                fatherMobile: s?.fatherMobile,
                parentName: parent?.$1,
                parentMobile: parent?.$2,
                parentRelation: parent?.$3,
                lastReminder: lastReminders[e.key],
              );
            }(),
        ]..sort((a, b) {
          final p = b.pendingAmount.compareTo(a.pendingAmount);
          return p != 0
              ? p
              : a.studentName.toLowerCase().compareTo(
                  b.studentName.toLowerCase(),
                );
        });
    return list;
  }

  /// Students whose name, room or father (name or mobile) contains the text.
  static List<FeeDue> search(List<FeeDue> dues, String? text) {
    final s = Validators.clean(text).toLowerCase();
    if (s.isEmpty) return dues;
    return dues
        .where(
          (d) =>
              d.studentName.toLowerCase().contains(s) ||
              (d.roomNumber ?? '').toLowerCase().contains(s) ||
              d.fatherText.toLowerCase().contains(s),
        )
        .toList();
  }

  /// "12 students, pending ₹4,50,000.00" (all students, as the desktop).
  static String summary(List<FeeDue> dues) =>
      '${dues.length} ${dues.length == 1 ? 'student' : 'students'}, pending '
      '${Money.format(dues.fold(0.0, (t, d) => t + d.pendingAmount))}';

  /// The father's mobile, else the mother's: (name, number, relation).
  static (String, String, String)? recipient(Student s) {
    for (final (name, mobile, relation) in [
      (s.fatherName, s.fatherMobile, 'Father'),
      (s.motherName, s.motherMobile, 'Mother'),
    ]) {
      final number = AttendanceService.toWhatsAppNumber(mobile);
      if (number != null) {
        return (
          (name ?? '').trim().isEmpty ? 'Parent' : name!.trim(),
          number,
          relation,
        );
      }
    }
    return null;
  }

  /// "2025-2026, 2026-2027".
  static String years(FeeDue due, int startMonth) => due.invoices
      .map((i) => AcademicYear.label(i.academicYear, startMonth))
      .join(', ');

  /// The reminder text ([template] is the text saved on the desktop, or its
  /// default wording).
  static String message({
    required FeeDue due,
    required String hostelName,
    required int startMonth,
    String? hostelPhone,
    String? adminPhone,
    String template = MessageText.defaultFeeText,
  }) => MessageText.fill(template, {
    'ParentName': due.parentName ?? 'Parent',
    'HostelName': hostelName,
    'StudentName': due.studentName,
    'AcademicYear': years(due, startMonth),
    'TotalAmount': MessageText.amount(due.totalAmount),
    'PaidAmount': MessageText.amount(due.paidAmount),
    'Pending': MessageText.amount(due.pendingAmount),
    'HostelPhone': MessageText.contactNumber(hostelPhone, adminPhone),
  });
}
