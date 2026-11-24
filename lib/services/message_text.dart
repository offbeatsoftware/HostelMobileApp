/// The WhatsApp texts, as the desktop's "WhatsApp on this PC" mode sends
/// them: the admin can change them on the desktop (Email Settings >
/// WhatsApp); these are the desktop's default wordings.
class MessageText {
  static const feeKey = 'WhatsApp.FeeText';
  static const attendanceKey = 'WhatsApp.AttendanceText';

  static const defaultFeeText =
      'Dear {ParentName},\n'
      'This is a fee reminder from {HostelName} for {StudentName} for the '
      'academic year {AcademicYear}.\n'
      'Total fee: ₹{TotalAmount}\n'
      'Paid: ₹{PaidAmount}\n'
      'Pending: ₹{Pending}\n\n'
      'To pay the fee, please scan our UPI QR code with any UPI app (GPay, '
      'PhonePe, Paytm, BHIM). For bank transfer details, please call '
      '{HostelPhone}.\n\n'
      'After paying, please share the payment receipt or UTR number on '
      '{HostelPhone}. Thank you.';

  static const defaultAttendanceText =
      'Dear {ParentName},\n'
      'This is to inform you that {StudentName} was absent from {HostelName} '
      'on {AttendanceDate}.\n'
      'For any question, please call {HostelPhone}. Thank you.';

  /// Replaces each {Field} with its value; unknown fields are left as they
  /// are (as the desktop does).
  static String fill(String template, Map<String, String> values) =>
      template.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) => values[m.group(1)] ?? m.group(0)!,
      );

  /// The number parents are asked to call: the hostel's phone, else the
  /// admin's, else "the hostel office".
  static String contactNumber(String? hostelPhone, String? adminPhone) {
    for (final phone in [hostelPhone, adminPhone]) {
      if ((phone ?? '').trim().isNotEmpty) return phone!.trim();
    }
    return 'the hostel office';
  }

  /// An amount in a message, as the desktop writes it: 85,000 or 85,000.50
  /// (Indian grouping, no ₹ sign; the text has it).
  static String amount(double value) {
    final whole = value == value.truncateToDouble();
    final fixed = value.abs().toStringAsFixed(whole ? 0 : 2);
    final parts = fixed.split('.');
    var digits = parts[0];
    if (digits.length > 3) {
      var head = digits.substring(0, digits.length - 3);
      final tail = digits.substring(digits.length - 3);
      final groups = <String>[];
      while (head.length > 2) {
        groups.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
      digits = [head, ...groups, tail].join(',');
    }
    return '${value < 0 ? '-' : ''}$digits${parts.length > 1 ? '.${parts[1]}' : ''}';
  }
}
