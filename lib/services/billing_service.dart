import '../data/billing_repository.dart';
import '../models/allocation.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import 'allocation_service.dart';
import 'date_format.dart';
import 'money.dart';
import 'validators.dart';

/// A student in a room without a fee for the year (New Year Fees), with
/// last year's fee for reference.
class NewYearCandidate {
  const NewYearCandidate(
    this.studentId,
    this.studentName,
    this.roomText,
    this.lastYear,
  );

  final int studentId;
  final String studentName;
  final String roomText;
  final Invoice? lastYear;
}

/// Invoice and payment rules, as in the desktop InvoiceService and
/// PaymentService. The database checks every rule again when saving.
class BillingService {
  // ---- Invoices ----

  /// Invoices matching the search (invoice no. or student), status and year.
  static List<Invoice> filterInvoices(
    List<Invoice> invoices,
    String? search,
    String? status,
    int? year,
  ) {
    final s = Validators.clean(search).toLowerCase();
    return invoices.where((i) {
      if (s.isNotEmpty &&
          !i.invoiceNumber.toLowerCase().contains(s) &&
          !i.studentName.toLowerCase().contains(s)) {
        return false;
      }
      if (status != null && i.status != status) return false;
      return year == null || i.academicYear == year;
    }).toList();
  }

  /// "12 invoices, total ₹.., paid ₹.., pending ₹..".
  static String invoiceSummary(List<Invoice> shown) {
    double sum(double Function(Invoice) f) => shown.fold(0, (t, i) => t + f(i));
    return '${shown.length} ${shown.length == 1 ? 'invoice' : 'invoices'}, '
        'total ${Money.format(sum((i) => i.totalAmount))}, '
        'paid ${Money.format(sum((i) => i.paidAmount))}, '
        'pending ${Money.format(sum((i) => i.pendingAmount))}';
  }

  /// The academic years that have invoices, newest first.
  static List<int> years(List<Invoice> invoices) =>
      {for (final i in invoices) i.academicYear}.toList()
        ..sort((a, b) => b.compareTo(a));

  /// Students in a room (current allocations) without a fee for [year],
  /// sorted by name, with last year's fee.
  static List<NewYearCandidate> newYearCandidates(
    List<RoomAllocation> current,
    List<Invoice> invoices,
    int year,
  ) {
    final invoiced = {
      for (final i in invoices)
        if (i.academicYear == year) i.studentId,
    };
    final lastYear = <int, Invoice>{
      for (final i in invoices)
        if (i.academicYear == year - 1) i.studentId: i,
    };
    final list =
        [
          for (final a in current)
            if (a.isCurrent && !invoiced.contains(a.studentId))
              NewYearCandidate(
                a.studentId,
                a.studentName,
                a.roomAndBed,
                lastYear[a.studentId],
              ),
        ]..sort(
          (a, b) => a.studentName.toLowerCase().compareTo(
            b.studentName.toLowerCase(),
          ),
        );
    return list;
  }

  /// The year New Year Fees opens on: the next academic year from three
  /// months before it starts, otherwise the current one (as the desktop).
  static int defaultNewYear(DateTime today, int startMonth) {
    final current = AcademicYear.of(today, startMonth);
    final nextStart = DateTime(current + 1, startMonth, 1);
    final threeMonthsBefore = DateTime(
      nextStart.year,
      nextStart.month - 3,
      nextStart.day,
    );
    return dateOnly(today).isBefore(threeMonthsBefore) ? current : current + 1;
  }

  /// Saves a changed fee; throws [ValidationException] with a message.
  static Future<void> updateFee(
    Invoice invoice,
    String rentText,
    String transportText,
    String? remarks,
  ) async {
    if (Money.tryParse(rentText) == null) {
      throw const ValidationException(
        'Please enter the room rent for the year.',
      );
    }
    final fee = AllocationService.readFee(rentText, transportText);
    final cleanRemarks = Validators.clean(remarks);
    Validators.checkLength(cleanRemarks, 255, 'Remarks');
    await BillingRepository.instance.updateFee(
      invoiceId: invoice.invoiceId,
      roomRent: fee.roomRent,
      transport: fee.transport,
      remarks: cleanRemarks,
    );
  }

  static Future<void> deleteInvoice(Invoice invoice) =>
      BillingRepository.instance.deleteInvoice(invoice.invoiceId);

  /// Reads the New Year Fees rows (rows with nothing typed are skipped) and
  /// creates the fees; returns how many were created.
  static Map<int, (double, double)> readYearFees(
    List<NewYearCandidate> candidates,
    Map<int, (String rent, String transport)> typed,
  ) {
    final fees = <int, (double, double)>{};
    for (final c in candidates) {
      final (rentText, transportText) = typed[c.studentId] ?? ('', '');
      if (rentText.trim().isEmpty && transportText.trim().isEmpty) continue;
      final rent = Money.tryParse(rentText);
      if (rent == null || rent <= 0) {
        throw ValidationException(
          'Please enter a valid room rent for ${c.studentName}.',
        );
      }
      var transport = 0.0;
      if (transportText.trim().isNotEmpty) {
        final t = Money.tryParse(transportText);
        if (t == null) {
          throw ValidationException(
            'Please enter a valid transport amount '
            'for ${c.studentName}, or leave it empty.',
          );
        }
        transport = t;
      }
      fees[c.studentId] = (rent, transport);
    }
    if (fees.isEmpty) {
      throw const ValidationException(
        'Please enter the room rent for at least one student.',
      );
    }
    return fees;
  }

  // ---- Payments ----

  /// Payments matching the search (receipt, invoice, student, reference or
  /// remarks) and the method.
  static List<Payment> filterPayments(
    List<Payment> payments,
    String? search,
    String? method,
  ) {
    final s = Validators.clean(search).toLowerCase();
    bool has(String? v) => (v ?? '').toLowerCase().contains(s);
    return payments.where((p) {
      if (s.isNotEmpty &&
          !has(p.receiptNumber) &&
          !has(p.invoiceNumber) &&
          !has(p.reference) &&
          !has(p.remarks) &&
          !has(p.studentName)) {
        return false;
      }
      return method == null || p.paymentMethod == method;
    }).toList();
  }

  static String paymentSummary(List<Payment> shown) =>
      '${shown.length} ${shown.length == 1 ? 'payment' : 'payments'}, received '
      '${Money.format(shown.fold(0.0, (t, p) => t + p.amount))}';

  /// Invoices that still have an amount pending, oldest year first.
  static List<Invoice> invoicesWithPending(List<Invoice> invoices) =>
      invoices.where((i) => i.pendingAmount > 0).toList()..sort((a, b) {
        final y = a.academicYear.compareTo(b.academicYear);
        if (y != 0) return y;
        final n = a.studentName.toLowerCase().compareTo(
          b.studentName.toLowerCase(),
        );
        return n != 0 ? n : a.invoiceId.compareTo(b.invoiceId);
      });

  static double _readAmount(String text, String message) {
    final amount = Money.tryParse(text);
    if (amount == null) throw ValidationException(message);
    return amount;
  }

  static void _check(
    DateTime date,
    DateTime today,
    double amount,
    String method,
    String reference,
    String remarks,
  ) {
    if (dateOnly(date).isAfter(dateOnly(today))) {
      throw const ValidationException(
        'The payment date cannot be in the future.',
      );
    }
    if (amount <= 0) {
      throw const ValidationException(
        'Please enter an amount greater than zero.',
      );
    }
    if (((amount * 100) - (amount * 100).round()).abs() > 1e-6) {
      throw const ValidationException(
        'The amount can have at most two decimal places (paise).',
      );
    }
    if (!PaymentMethod.all.contains(method)) {
      throw const ValidationException(
        'Please select how the payment was made.',
      );
    }
    if (PaymentMethod.requiresReference(method) && reference.isEmpty) {
      throw ValidationException(
        'Please enter the ${PaymentMethod.referenceName(method).toLowerCase()}.',
      );
    }
    Validators.checkLength(reference, 100, 'Reference');
    Validators.checkLength(remarks, 255, 'Remarks');
  }

  /// Records a payment; returns the receipt number.
  static Future<String> recordPayment({
    required Invoice? invoice,
    required DateTime date,
    required DateTime today,
    required String amountText,
    required String method,
    String? reference,
    String? remarks,
  }) async {
    if (invoice == null) {
      throw const ValidationException('Please select the invoice.');
    }
    final amount = _readAmount(
      amountText,
      'Please enter the amount as a number, for example 25000.',
    );
    final ref = Validators.clean(reference);
    final rem = Validators.clean(remarks);
    _check(date, today, amount, method, ref, rem);
    if (amount > invoice.pendingAmount) {
      throw ValidationException(
        'The amount cannot be more than the pending '
        'amount of ${Money.format(invoice.pendingAmount)}. Advance or extra '
        'payments are not accepted.',
      );
    }
    return BillingRepository.instance.recordPayment(
      invoiceId: invoice.invoiceId,
      date: isoDate(date),
      amount: amount,
      method: method,
      reference: ref,
      remarks: rem,
    );
  }

  /// Corrects a payment; the database records the change with [reason].
  static Future<void> editPayment({
    required Payment payment,
    required DateTime date,
    required DateTime today,
    required String amountText,
    required String method,
    String? reference,
    String? remarks,
    String? reason,
  }) async {
    final amount = _readAmount(amountText, 'Please enter a valid amount.');
    final ref = Validators.clean(reference);
    final rem = Validators.clean(remarks);
    final why = Validators.clean(reason);
    _check(date, today, amount, method, ref, rem);
    Validators.checkLength(why, 255, 'Reason');
    await BillingRepository.instance.editPayment(
      paymentId: payment.paymentId,
      date: isoDate(date),
      amount: amount,
      method: method,
      reference: ref,
      remarks: rem,
      reason: why,
    );
  }

  static Future<void> deletePayment(Payment payment, String? reason) async {
    final why = Validators.clean(reason);
    Validators.checkLength(why, 255, 'Reason');
    await BillingRepository.instance.deletePayment(payment.paymentId, why);
  }
}
