import '../models/allocation.dart';
import '../models/college.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/report_table.dart';
import '../models/room.dart';
import '../models/student.dart';
import 'date_format.dart';
import 'fee_reminder_service.dart';
import 'money.dart';
import 'natural_order.dart';
import 'validators.dart';

/// The data the reports are made from.
class ReportData {
  const ReportData({
    required this.students,
    required this.colleges,
    required this.rooms,
    required this.allocations,
    required this.payments,
    required this.invoices,
    required this.startMonth,
  });

  final List<Student> students;
  final List<College> colleges;
  final List<Room> rooms;

  /// Current allocations (students in rooms now).
  final List<RoomAllocation> allocations;
  final List<Payment> payments;
  final List<Invoice> invoices;
  final int startMonth;
}

/// The five reports of the desktop ReportService, with the same columns,
/// order, subtotals and totals.
class ReportService {
  static String _date(DateTime d) => formatDate(d);

  static String _stamp(DateTime d) => isoDate(d);

  static String _paymentCount(int n) => n == 1 ? '1 payment' : '$n payments';

  /// Letters and digits only, for file names: "Shri Balaji Hostel" ->
  /// "Shri-Balaji-Hostel".
  static String safeName(String text) {
    var name = text
        .split('')
        .map((c) => RegExp(r'[A-Za-z0-9]').hasMatch(c) ? c : '-')
        .join();
    while (name.contains('--')) {
      name = name.replaceAll('--', '-');
    }
    name = name.replaceAll(RegExp(r'^-+|-+$'), '');
    return name.isEmpty ? 'Hostel' : name;
  }

  static List<String> _subtitles(
    Hostel hostel,
    String filter,
    DateTime now,
  ) => [
    hostel.hostelName,
    filter,
    'Printed on ${_date(now)} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
  ];

  static String _join(String? a, String? b) {
    final x = a ?? '', y = b ?? '';
    return x.isNotEmpty && y.isNotEmpty ? '$x, $y' : x + y;
  }

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  // ---------------------------------------------------------------------

  static ReportTable studentList(
    Hostel hostel,
    ReportData data,
    DateTime now, {
    String? status,
    int? collegeId,
  }) {
    final students =
        data.students
            .where((s) => status == null || s.status == status)
            .where((s) => collegeId == null || s.collegeId == collegeId)
            .toList()
          ..sort((a, b) => _byName(a.studentName, b.studentName));
    final filters = [status == null ? 'All students' : '$status students'];
    if (collegeId != null) {
      filters.add(
        data.colleges
                .where((c) => c.collegeId == collegeId)
                .firstOrNull
                ?.collegeName ??
            '',
      );
    }
    return ReportTable(
      title: 'Student List',
      subtitles: _subtitles(
        hostel,
        filters.where((f) => f.isNotEmpty).join(', '),
        now,
      ),
      columns: const [
        ReportColumn('Student', width: 1.6),
        ReportColumn('College', width: 1.5),
        ReportColumn('Course / class', width: 1.2),
        ReportColumn('Room', width: 0.5),
        ReportColumn('Mobile', width: 0.9),
        ReportColumn('Aadhaar', width: 1),
        ReportColumn('Father', width: 1.3),
        ReportColumn('Father mobile', width: 0.9),
        ReportColumn('Admission', kind: ReportValueKind.date, width: 0.8),
        ReportColumn('Status', width: 0.6),
      ],
      rows: [
        for (final s in students)
          ReportRow([
            s.studentName,
            s.collegeName,
            _join(s.course, s.className),
            s.roomNumber,
            s.mobile,
            s.aadhaarMasked,
            s.fatherName,
            s.fatherMobile,
            s.admissionDate,
            s.status,
          ]),
        ReportRow([
          '${students.length} students', null, null, null, null, null, null,
          null, null, null, //
        ], ReportRowStyle.total),
      ],
      fileName: 'Students_${safeName(hostel.hostelName)}_${_stamp(now)}',
    );
  }

  static ReportTable roomOccupancy(
    Hostel hostel,
    ReportData data,
    DateTime now,
  ) {
    final rooms = [...data.rooms]
      ..sort((a, b) => naturalCompare(a.roomNumber, b.roomNumber));
    final names = <int, List<String>>{};
    for (final a in data.allocations.where((a) => a.isCurrent)) {
      names.putIfAbsent(a.roomId, () => []).add(a.studentName);
    }
    for (final list in names.values) {
      list.sort(_byName);
    }
    int sum(int Function(Room) f, [bool Function(Room)? where]) =>
        rooms.where(where ?? (_) => true).fold(0, (t, r) => t + f(r));
    return ReportTable(
      title: 'Room Occupancy',
      subtitles: _subtitles(hostel, 'Current students in each room', now),
      columns: const [
        ReportColumn('Room', width: 0.6),
        ReportColumn('Floor', width: 0.5),
        ReportColumn('For', width: 0.5),
        ReportColumn('Sharing', width: 0.7),
        ReportColumn('Beds', kind: ReportValueKind.number, width: 0.5),
        ReportColumn('Occupied', kind: ReportValueKind.number, width: 0.6),
        ReportColumn('Free', kind: ReportValueKind.number, width: 0.5),
        ReportColumn('Students', width: 4.2),
        ReportColumn('Status', width: 0.6),
      ],
      rows: [
        for (final r in rooms)
          ReportRow([
            r.roomNumber,
            r.floor,
            r.roomFor,
            r.sharingName,
            r.capacity,
            r.occupied,
            r.available,
            (names[r.roomId] ?? const []).join(', '),
            r.status,
          ]),
        ReportRow([
          '${rooms.length} rooms',
          null,
          null,
          null,
          sum((r) => r.capacity, (r) => r.isActive),
          sum((r) => r.occupied),
          sum((r) => r.available),
          null,
          null,
        ], ReportRowStyle.total),
      ],
      fileName: 'Rooms_${safeName(hostel.hostelName)}_${_stamp(now)}',
    );
  }

  /// Payments received between two dates (inclusive), with a total after
  /// each day, then per method, then the total.
  static ReportTable paymentsReceived(
    Hostel hostel,
    ReportData data,
    DateTime now,
    DateTime from,
    DateTime to, {
    String? method,
  }) {
    final f = dateOnly(from), t = dateOnly(to);
    if (f.isAfter(t)) {
      throw const ValidationException(
        'The From date must be on or before the To date.',
      );
    }
    final payments =
        data.payments
            .where(
              (p) => !p.paymentDate.isBefore(f) && !p.paymentDate.isAfter(t),
            )
            .where((p) => method == null || p.paymentMethod == method)
            .toList()
          ..sort((a, b) {
            final d = a.paymentDate.compareTo(b.paymentDate);
            return d != 0 ? d : a.paymentId.compareTo(b.paymentId);
          });
    double total(Iterable<Payment> ps) => ps.fold(0.0, (s, p) => s + p.amount);

    final rows = <ReportRow>[];
    final days = <DateTime, List<Payment>>{};
    for (final p in payments) {
      days.putIfAbsent(dateOnly(p.paymentDate), () => []).add(p);
    }
    for (final e in days.entries) {
      for (final p in e.value) {
        rows.add(
          ReportRow([
            p.paymentDate,
            p.receiptNumber,
            p.studentName,
            p.invoiceNumber,
            p.paymentMethod,
            p.reference,
            p.amount,
          ]),
        );
      }
      rows.add(
        ReportRow([
          null,
          'Total for ${_date(e.key)} (${_paymentCount(e.value.length)})',
          null, null, null, null, total(e.value), //
        ], ReportRowStyle.subtotal),
      );
    }
    for (final m in PaymentMethod.all) {
      final ofMethod = payments.where((p) => p.paymentMethod == m).toList();
      if (ofMethod.isEmpty) continue;
      rows.add(
        ReportRow([
          null, '$m total (${_paymentCount(ofMethod.length)})', null, null, //
          null, null, total(ofMethod),
        ], ReportRowStyle.subtotal),
      );
    }
    rows.add(
      ReportRow([
        null,
        'Total received (${_paymentCount(payments.length)})',
        null,
        null, //
        null, null, total(payments),
      ], ReportRowStyle.total),
    );

    return ReportTable(
      title: 'Payments Received',
      subtitles: _subtitles(
        hostel,
        '${_date(f)} to ${_date(t)}, '
        '${method ?? 'all payment methods'}',
        now,
      ),
      columns: const [
        ReportColumn('Date', kind: ReportValueKind.date, width: 0.8),
        ReportColumn('Receipt no.', width: 1.4),
        ReportColumn('Student', width: 1.5),
        ReportColumn('Invoice no.', width: 1.2),
        ReportColumn('Paid by', width: 0.8),
        ReportColumn('Reference', width: 1.1),
        ReportColumn('Amount', kind: ReportValueKind.money, width: 1),
      ],
      rows: rows,
      fileName:
          'Payments_${safeName(hostel.hostelName)}_${_stamp(f)}_to_${_stamp(t)}',
    );
  }

  /// The yearly fees of an academic year (or all years), optionally of one
  /// status.
  static ReportTable invoices(
    Hostel hostel,
    ReportData data,
    DateTime now, {
    int? year,
    String? status,
  }) {
    final list =
        data.invoices
            .where((i) => year == null || i.academicYear == year)
            .where((i) => status == null || i.status == status)
            .toList()
          ..sort((a, b) {
            final y = a.academicYear.compareTo(b.academicYear);
            return y != 0 ? y : _byName(a.studentName, b.studentName);
          });
    String label(int y) => AcademicYear.label(y, data.startMonth);
    double sum(double Function(Invoice) f) =>
        list.fold(0.0, (t, i) => t + f(i));
    final yearText = year == null
        ? 'All academic years'
        : 'Academic year ${label(year)}';
    return ReportTable(
      title: 'Fees (Invoices)',
      subtitles: _subtitles(
        hostel,
        '$yearText, ${status == null ? 'all invoices' : status.toLowerCase()}',
        now,
      ),
      columns: const [
        ReportColumn('Invoice no.', width: 1.3),
        ReportColumn('Year', width: 0.6),
        ReportColumn('Student', width: 1.6),
        ReportColumn('Room rent', kind: ReportValueKind.money, width: 1),
        ReportColumn('Transport', kind: ReportValueKind.money, width: 1),
        ReportColumn('Total fee', kind: ReportValueKind.money, width: 1),
        ReportColumn('Paid', kind: ReportValueKind.money, width: 1),
        ReportColumn('Pending', kind: ReportValueKind.money, width: 1),
        ReportColumn('Status', width: 0.8),
      ],
      rows: [
        for (final i in list)
          ReportRow([
            i.invoiceNumber,
            label(i.academicYear),
            i.studentName,
            i.roomRent,
            i.transportAmount,
            i.totalAmount,
            i.paidAmount,
            i.pendingAmount,
            i.status,
          ]),
        ReportRow([
          '${list.length} invoices',
          null,
          null,
          sum((i) => i.roomRent),
          sum((i) => i.transportAmount),
          sum((i) => i.totalAmount),
          sum((i) => i.paidAmount),
          sum((i) => i.pendingAmount),
          null,
        ], ReportRowStyle.total),
      ],
      fileName:
          'Fees_${safeName(hostel.hostelName)}_'
          '${year == null ? 'all-years' : label(year)}',
    );
  }

  /// Pending fees: a bold line per student with total, paid and pending,
  /// then that student's invoices.
  static ReportTable pendingDues(Hostel hostel, ReportData data, DateTime now) {
    final dues = FeeReminderService.dues(
      invoices: data.invoices,
      students: data.students,
      lastReminders: const {},
    );
    final status = {for (final s in data.students) s.studentId: s.status};
    final rows = <ReportRow>[];
    for (final d in dues) {
      final name = status[d.studentId] == StudentStatus.left
          ? '${d.studentName} (left)'
          : d.studentName;
      rows.add(
        ReportRow([
          name, d.roomNumber, d.fatherText, null, d.totalAmount, d.paidAmount,
          d.pendingAmount, //
        ], ReportRowStyle.group),
      );
      for (final i in d.invoices) {
        rows.add(
          ReportRow([
            '    ${i.invoiceNumber}',
            null,
            null,
            AcademicYear.label(i.academicYear, data.startMonth),
            i.totalAmount,
            i.paidAmount,
            i.pendingAmount,
          ]),
        );
      }
    }
    double sum(double Function(FeeDue) f) => dues.fold(0.0, (t, d) => t + f(d));
    rows.add(
      ReportRow([
        '${dues.length} students', null, null, null, sum((d) => d.totalAmount),
        sum((d) => d.paidAmount), sum((d) => d.pendingAmount), //
      ], ReportRowStyle.total),
    );
    return ReportTable(
      title: 'Pending Fees',
      subtitles: _subtitles(
        hostel,
        'As on ${_date(now)}, all students with an amount pending',
        now,
      ),
      columns: const [
        ReportColumn('Student / invoice', width: 2.2),
        ReportColumn('Room', width: 0.5),
        ReportColumn('Father / mobile', width: 1.8),
        ReportColumn('Year', width: 0.6),
        ReportColumn('Total fee', kind: ReportValueKind.money, width: 1),
        ReportColumn('Paid', kind: ReportValueKind.money, width: 1),
        ReportColumn('Pending', kind: ReportValueKind.money, width: 1),
      ],
      rows: rows,
      fileName: 'PendingFees_${safeName(hostel.hostelName)}_${_stamp(now)}',
    );
  }

  /// A value as shown on screen (₹) or in the PDF (Rs., which the PDF font
  /// has), as the desktop.
  static String format(Object? value, {bool pdf = false}) => switch (value) {
    null => '',
    DateTime d => formatDate(d),
    double a =>
      pdf ? 'Rs. ${Money.format(a).replaceFirst('₹', '')}' : Money.format(a),
    int n => '$n',
    _ => '$value',
  };
}
