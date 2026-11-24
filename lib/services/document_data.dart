import '../data/allocation_repository.dart';
import '../data/billing_repository.dart';
import '../data/student_repository.dart';
import '../models/allocation.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/print_data.dart';
import '../models/refund.dart';
import '../models/student.dart';
import 'money.dart';
import 'validators.dart';

/// Reads what an invoice, receipt or refund receipt shows, as the desktop
/// InvoiceService.GetPrintData, PaymentService.GetReceiptData and
/// RefundService.GetPrintData.
class DocumentData {
  static Student _student(List<Student> students, int id) =>
      students.where((s) => s.studentId == id).firstOrNull ??
      (throw const ValidationException(
        "The invoice's student no longer exists.",
      ));

  static Invoice _invoice(List<Invoice> invoices, int id) =>
      invoices.where((i) => i.invoiceId == id).firstOrNull ??
      (throw const ValidationException('This invoice no longer exists.'));

  static Future<InvoicePrintData> invoice(Hostel hostel, int invoiceId) async =>
      (await invoices(hostel, [invoiceId])).first;

  /// The print data of several invoices, read once.
  static Future<List<InvoicePrintData>> invoices(
    Hostel hostel,
    List<int> invoiceIds,
  ) async {
    final id = hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      billing.getInvoices(id),
      StudentRepository.instance.getForHostel(id),
      billing.getPayments(id),
      billing.getRefunds(id),
      AllocationRepository.instance.getForHostel(id, includeHistory: true),
      billing.getAcademicYearStartMonth(),
    ]);
    final startMonth = r[5] as int;
    return [
      for (final invoiceId in invoiceIds)
        _one(
          hostel,
          invoiceId,
          startMonth,
          r[0] as List<Invoice>,
          r[1] as List<Student>,
          r[2] as List<Payment>,
          r[3] as List<Refund>,
          r[4] as List<RoomAllocation>,
        ),
    ];
  }

  static InvoicePrintData _one(
    Hostel hostel,
    int invoiceId,
    int startMonth,
    List<Invoice> allInvoices,
    List<Student> students,
    List<Payment> allPayments,
    List<Refund> allRefunds,
    List<RoomAllocation> allocations,
  ) {
    final invoice = _invoice(allInvoices, invoiceId);
    final student = _student(students, invoice.studentId);

    // The room the student is in now, or the last room during the academic
    // year.
    final from = AcademicYear.start(invoice.academicYear, startMonth);
    final to = AcademicYear.end(invoice.academicYear, startMonth);
    final stays =
        allocations
            .where(
              (a) =>
                  a.studentId == student.studentId &&
                  !_day(a.checkInDate).isAfter(to) &&
                  !_day(a.checkOutDate ?? DateTime(9999)).isBefore(from),
            )
            .toList()
          ..sort((a, b) {
            final d = b.checkInDate.compareTo(a.checkInDate);
            return d != 0 ? d : b.allocationId.compareTo(a.allocationId);
          });

    final payments = allPayments.where((p) => p.invoiceId == invoiceId).toList()
      ..sort((a, b) {
        final d = a.paymentDate.compareTo(b.paymentDate);
        return d != 0 ? d : a.paymentId.compareTo(b.paymentId);
      });
    final refunds = allRefunds.where((x) => x.invoiceId == invoiceId).toList()
      ..sort((a, b) {
        final d = a.refundDate.compareTo(b.refundDate);
        return d != 0 ? d : a.refundId.compareTo(b.refundId);
      });

    return InvoicePrintData(
      invoice: invoice,
      hostel: hostel,
      student: student,
      startMonth: startMonth,
      roomText: stays.isEmpty ? '' : 'Room ${stays.first.roomAndBed}',
      payments: payments,
      refunds: refunds,
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static Future<ReceiptPrintData> receipt(Hostel hostel, int paymentId) async {
    final id = hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      billing.getPayments(id),
      billing.getInvoices(id),
      StudentRepository.instance.getForHostel(id),
      billing.getAcademicYearStartMonth(),
    ]);
    final payment = (r[0] as List<Payment>)
        .where((p) => p.paymentId == paymentId)
        .firstOrNull;
    if (payment == null) {
      throw const ValidationException('This payment no longer exists.');
    }
    final invoice = _invoice(r[1] as List<Invoice>, payment.invoiceId);
    return ReceiptPrintData(
      payment: payment,
      invoice: invoice,
      hostel: hostel,
      student: _student(r[2] as List<Student>, payment.studentId),
      startMonth: r[3] as int,
    );
  }

  static Future<RefundPrintData> refund(Hostel hostel, int refundId) async {
    final id = hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      billing.getRefunds(id),
      billing.getInvoices(id),
      StudentRepository.instance.getForHostel(id),
      billing.getAcademicYearStartMonth(),
    ]);
    final refund = (r[0] as List<Refund>)
        .where((x) => x.refundId == refundId)
        .firstOrNull;
    if (refund == null) {
      throw const ValidationException('This refund no longer exists.');
    }
    return RefundPrintData(
      refund: refund,
      invoice: _invoice(r[1] as List<Invoice>, refund.invoiceId),
      hostel: hostel,
      student: _student(r[2] as List<Student>, refund.studentId),
      startMonth: r[3] as int,
    );
  }
}
