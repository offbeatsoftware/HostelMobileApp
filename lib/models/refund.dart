/// Money paid back to a student; it also lowers the fee by the same amount.
class Refund {
  const Refund({
    required this.refundId,
    required this.refundNumber,
    required this.studentId,
    required this.invoiceId,
    required this.refundDate,
    required this.amount,
    this.studentName = '',
  });

  final int refundId;
  final String refundNumber;
  final int studentId;
  final int invoiceId;
  final DateTime refundDate;
  final double amount;
  final String studentName;

  /// A row of the refund_list view.
  factory Refund.fromMap(Map<String, dynamic> map) => Refund(
    refundId: map['refund_id'] as int,
    refundNumber: map['refund_number'] as String,
    studentId: map['student_id'] as int,
    invoiceId: map['invoice_id'] as int,
    refundDate: DateTime.parse(map['refund_date'] as String),
    amount: (map['amount'] as num).toDouble(),
    studentName: (map['student_name'] as String?) ?? '',
  );
}
