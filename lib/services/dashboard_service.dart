import '../models/allocation.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/refund.dart';
import '../models/room.dart';
import '../models/student.dart';
import 'date_format.dart';
import 'money.dart';

/// A student's total pending fee, over all their invoices.
class StudentDue {
  const StudentDue(this.studentId, this.studentName, this.pendingAmount);

  final int studentId;
  final String studentName;
  final double pendingAmount;
}

/// Money received in one month (net of refunds paid back that month).
class MonthTotal {
  const MonthTotal(this.month, this.amount);

  /// The first day of the month.
  final DateTime month;
  final double amount;
}

/// Everything the dashboard shows, as the desktop DashboardData.
class DashboardData {
  const DashboardData({
    required this.asOf,
    required this.academicYear,
    required this.yearStart,
    required this.activeStudents,
    required this.leftStudents,
    required this.totalBeds,
    required this.occupiedBeds,
    required this.freeBeds,
    required this.invoicedThisYear,
    required this.receivedThisMonth,
    required this.receivedThisYear,
    required this.pendingAmount,
    required this.pendingStudents,
    required this.highestPending,
    required this.latestPayments,
    required this.recentCheckIns,
    required this.paymentsPerMonth,
  });

  final DateTime asOf;

  /// "2026-2027".
  final String academicYear;
  final DateTime yearStart;
  final int activeStudents;
  final int leftStudents;
  final int totalBeds;
  final int occupiedBeds;
  final int freeBeds;
  final double invoicedThisYear;
  final double receivedThisMonth;
  final double receivedThisYear;
  final double pendingAmount;
  final int pendingStudents;
  final List<StudentDue> highestPending;
  final List<Payment> latestPayments;
  final List<RoomAllocation> recentCheckIns;
  final List<MonthTotal> paymentsPerMonth;
}

/// The dashboard of the selected hostel (the desktop DashboardService):
/// students, beds, this academic year's fees, money received this month and
/// this year (net of refunds), pending fees, the five highest pending fees,
/// the latest payments and check-ins, and payments per month of the year.
class DashboardService {
  static const listSize = 5;

  static DashboardData compute({
    required DateTime today,
    required int startMonth,
    required List<Student> students,
    required List<Room> rooms,
    required List<Invoice> invoices,
    required List<Payment> payments,
    required List<Refund> refunds,
    required List<RoomAllocation> allocations,
  }) {
    final asOf = dateOnly(today);
    final year = AcademicYear.of(asOf, startMonth);
    final yearStart = DateTime(year, startMonth, 1);
    final monthStart = DateTime(asOf.year, asOf.month, 1);

    // Money received, net of refunds paid back in the same period.
    double net(DateTime from, DateTime to) {
      bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
      final paid = payments
          .where((p) => inRange(p.paymentDate))
          .fold(0.0, (t, p) => t + p.amount);
      final refunded = refunds
          .where((r) => inRange(r.refundDate))
          .fold(0.0, (t, r) => t + r.amount);
      return paid - refunded;
    }

    // Pending fees per student, highest first.
    final pendingByStudent = <int, double>{};
    final names = <int, String>{};
    for (final i in invoices.where((i) => i.pendingAmount > 0)) {
      pendingByStudent[i.studentId] =
          (pendingByStudent[i.studentId] ?? 0) + i.pendingAmount;
      names[i.studentId] = i.studentName;
    }
    final studentNames = {for (final s in students) s.studentId: s.studentName};
    final dues =
        [
          for (final e in pendingByStudent.entries)
            StudentDue(
              e.key,
              studentNames[e.key] ?? names[e.key] ?? '',
              e.value,
            ),
        ]..sort((a, b) {
          final p = b.pendingAmount.compareTo(a.pendingAmount);
          return p != 0
              ? p
              : a.studentName.toLowerCase().compareTo(
                  b.studentName.toLowerCase(),
                );
        });

    final latestPayments = [...payments]
      ..sort((a, b) {
        final d = b.paymentDate.compareTo(a.paymentDate);
        return d != 0 ? d : b.paymentId.compareTo(a.paymentId);
      });
    final checkIns = [...allocations]
      ..sort((a, b) {
        final d = b.checkInDate.compareTo(a.checkInDate);
        return d != 0 ? d : b.allocationId.compareTo(a.allocationId);
      });

    return DashboardData(
      asOf: asOf,
      academicYear: AcademicYear.label(year, startMonth),
      yearStart: yearStart,
      activeStudents: students
          .where((s) => s.status == StudentStatus.active)
          .length,
      leftStudents: students
          .where((s) => s.status == StudentStatus.left)
          .length,
      totalBeds: rooms
          .where((r) => r.isActive)
          .fold(0, (t, r) => t + r.capacity),
      occupiedBeds: rooms.fold(0, (t, r) => t + r.occupied),
      freeBeds: rooms.fold(0, (t, r) => t + r.available),
      invoicedThisYear: invoices
          .where((i) => i.academicYear == year)
          .fold(0.0, (t, i) => t + i.totalAmount),
      receivedThisMonth: net(monthStart, asOf),
      receivedThisYear: net(yearStart, asOf),
      pendingAmount: dues.fold(0.0, (t, d) => t + d.pendingAmount),
      pendingStudents: dues.length,
      highestPending: dues.take(listSize).toList(),
      latestPayments: latestPayments.take(listSize).toList(),
      recentCheckIns: checkIns.take(listSize).toList(),
      paymentsPerMonth: [
        for (var m = 0; m < 12; m++)
          () {
            final month = DateTime(yearStart.year, yearStart.month + m, 1);
            final last = DateTime(month.year, month.month + 1, 0);
            final amount = net(month, last);
            return MonthTotal(month, amount < 0 ? 0 : amount);
          }(),
      ],
    );
  }
}
