import 'hostel.dart';
import 'invoice.dart';
import 'payment.dart';
import 'refund.dart';
import 'student.dart';

/// Everything printed on an invoice PDF.
class InvoicePrintData {
  const InvoicePrintData({
    required this.invoice,
    required this.hostel,
    required this.student,
    required this.startMonth,
    this.roomText = '',
    this.payments = const [],
    this.refunds = const [],
  });

  final Invoice invoice;
  final Hostel hostel;
  final Student student;
  final int startMonth;

  /// "Room 101, bed 2", or empty.
  final String roomText;
  final List<Payment> payments;
  final List<Refund> refunds;
}

/// Everything printed on a payment receipt PDF.
class ReceiptPrintData {
  const ReceiptPrintData({
    required this.payment,
    required this.invoice,
    required this.hostel,
    required this.student,
    required this.startMonth,
  });

  final Payment payment;
  final Invoice invoice;
  final Hostel hostel;
  final Student student;
  final int startMonth;
}

/// Everything printed on a refund receipt PDF.
class RefundPrintData {
  const RefundPrintData({
    required this.refund,
    required this.invoice,
    required this.hostel,
    required this.student,
    required this.startMonth,
  });

  final Refund refund;
  final Invoice invoice;
  final Hostel hostel;
  final Student student;
  final int startMonth;
}
