/// A student's yearly fee (room rent + transport) for one academic year.
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

  /// The fee due: the agreed fee less what was waived and refunded.
  double get totalAmount =>
      roomRent + transportAmount - waivedAmount - refundedAmount;

  /// Still to be paid.
  double get pendingAmount =>
      roomRent + transportAmount - waivedAmount - receivedAmount;

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
  );
}
