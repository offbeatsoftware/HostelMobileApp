/// Values of an invoice's status (calculated from the payments).
class InvoiceStatus {
  static const unpaid = 'Unpaid';
  static const partlyPaid = 'Partly paid';
  static const paid = 'Paid';
  static const all = [unpaid, partlyPaid, paid];
}

/// A student's yearly fee (room rent + transport) for one academic year.
/// Paid, pending and status are calculated from the payments.
class Invoice {
  const Invoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.studentId,
    required this.academicYear,
    required this.roomRent,
    required this.transportAmount,
    this.waivedAmount = 0,
    this.receivedAmount = 0,
    this.refundedAmount = 0,
    this.studentName = '',
    this.invoiceDate,
    this.remarks,
  });

  final int invoiceId;
  final String invoiceNumber;
  final int studentId;
  final int academicYear;
  final double roomRent;
  final double transportAmount;
  final double waivedAmount;

  /// All payments received, before refunds.
  final double receivedAmount;
  final double refundedAmount;
  final String studentName;
  final DateTime? invoiceDate;
  final String? remarks;

  /// The fee agreed for the year: room rent plus transport.
  double get feeAmount => roomRent + transportAmount;

  /// The fee due: the agreed fee less what was waived and refunded.
  double get totalAmount => feeAmount - waivedAmount - refundedAmount;

  /// Money received less money refunded.
  double get paidAmount => receivedAmount - refundedAmount;

  /// Still to be paid.
  double get pendingAmount => totalAmount - paidAmount;

  String get status => pendingAmount <= 0
      ? InvoiceStatus.paid
      : paidAmount <= 0
      ? InvoiceStatus.unpaid
      : InvoiceStatus.partlyPaid;

  static double _n(Object? v) => v == null ? 0 : (v as num).toDouble();

  /// A row of the invoice_list view.
  factory Invoice.fromMap(Map<String, dynamic> map) => Invoice(
    invoiceId: map['invoice_id'] as int,
    invoiceNumber: map['invoice_number'] as String,
    studentId: map['student_id'] as int,
    academicYear: map['academic_year'] as int,
    roomRent: _n(map['room_rent']),
    transportAmount: _n(map['transport_amount']),
    waivedAmount: _n(map['waived_amount']),
    receivedAmount: _n(map['received_amount']),
    refundedAmount: _n(map['refunded_amount']),
    studentName: (map['student_name'] as String?) ?? '',
    invoiceDate: map['invoice_date'] == null
        ? null
        : DateTime.parse(map['invoice_date'] as String),
    remarks: map['remarks'] as String?,
  );
}
