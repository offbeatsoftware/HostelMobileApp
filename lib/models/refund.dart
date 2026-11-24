/// Money paid back to a student; it also lowers the fee by the same amount.
class Refund {
  const Refund({
    required this.refundId,
    required this.refundNumber,
    required this.studentId,
    required this.invoiceId,
    required this.refundDate,
    required this.amount,
    this.refundMethod = 'Cash',
    this.reference,
    this.reason = '',
    this.invoiceNumber = '',
    this.studentName = '',
  });

  final int refundId;
  final String refundNumber;
  final int studentId;
  final int invoiceId;
  final DateTime refundDate;
  final double amount;

  /// How the money was paid back (cash, UPI, bank transfer, cheque).
  final String refundMethod;
  final String? reference;
  final String reason;
  final String invoiceNumber;
  final String studentName;

  /// A row of the refund_list view.
  factory Refund.fromMap(Map<String, dynamic> map) => Refund(
    refundId: map['refund_id'] as int,
    refundNumber: map['refund_number'] as String,
    studentId: map['student_id'] as int,
    invoiceId: map['invoice_id'] as int,
    refundDate: DateTime.parse(map['refund_date'] as String),
    amount: (map['amount'] as num).toDouble(),
    refundMethod: (map['refund_method'] as String?) ?? 'Cash',
    reference: map['reference'] as String?,
    reason: (map['reason'] as String?) ?? '',
    invoiceNumber: (map['invoice_number'] as String?) ?? '',
    studentName: (map['student_name'] as String?) ?? '',
  );
}
