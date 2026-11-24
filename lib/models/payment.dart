/// How a payment was made.
class PaymentMethod {
  static const cash = 'Cash';
  static const upi = 'UPI';
  static const bankTransfer = 'Bank transfer';
  static const cheque = 'Cheque';
  static const all = [cash, upi, bankTransfer, cheque];

  /// Every method except cash needs a reference.
  static bool requiresReference(String method) => method != cash;

  /// What the reference is called, for example "Cheque number".
  static String referenceName(String method) => switch (method) {
    upi => 'UPI transaction id',
    bankTransfer => 'Bank reference',
    cheque => 'Cheque number',
    _ => 'Reference',
  };
}

/// A payment against one invoice, with its own receipt number.
class Payment {
  const Payment({
    required this.paymentId,
    required this.receiptNumber,
    required this.studentId,
    required this.invoiceId,
    required this.paymentDate,
    required this.amount,
    required this.paymentMethod,
    this.reference,
    this.remarks,
    this.studentName = '',
    this.invoiceNumber = '',
    this.academicYear,
  });

  final int paymentId;
  final String receiptNumber;
  final int studentId;
  final int invoiceId;
  final DateTime paymentDate;
  final double amount;
  final String paymentMethod;
  final String? reference;
  final String? remarks;
  final String studentName;
  final String invoiceNumber;
  final int? academicYear;

  /// A row of the payment_list view.
  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
    paymentId: map['payment_id'] as int,
    receiptNumber: map['receipt_number'] as String,
    studentId: map['student_id'] as int,
    invoiceId: map['invoice_id'] as int,
    paymentDate: DateTime.parse(map['payment_date'] as String),
    amount: (map['amount'] as num).toDouble(),
    paymentMethod: map['payment_method'] as String,
    reference: map['reference'] as String?,
    remarks: map['remarks'] as String?,
    studentName: (map['student_name'] as String?) ?? '',
    invoiceNumber: (map['invoice_number'] as String?) ?? '',
    academicYear: map['academic_year'] as int?,
  );
}

/// A correction or deletion of a payment, kept in the change history.
class PaymentChange {
  const PaymentChange({
    required this.paymentChangeId,
    required this.receiptNumber,
    required this.studentName,
    required this.changeType,
    required this.changedDate,
    required this.details,
    this.reason,
  });

  final int paymentChangeId;
  final String receiptNumber;
  final String studentName;

  /// Edited or Deleted.
  final String changeType;
  final DateTime changedDate;
  final String details;
  final String? reason;

  factory PaymentChange.fromMap(Map<String, dynamic> map) => PaymentChange(
    paymentChangeId: map['payment_change_id'] as int,
    receiptNumber: map['receipt_number'] as String,
    studentName: (map['student_name'] as String?) ?? '',
    changeType: map['change_type'] as String,
    changedDate: DateTime.parse(map['changed_date'] as String).toLocal(),
    details: map['details'] as String,
    reason: map['reason'] as String?,
  );
}
