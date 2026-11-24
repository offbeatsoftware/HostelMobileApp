/// Rupee amounts, shown as the desktop shows them: ₹2,68,500.00 (Indian
/// grouping: the last three digits, then pairs).
class Money {
  static String format(double amount) {
    final negative = amount < 0;
    final fixed = amount.abs().toStringAsFixed(2);
    final whole = fixed.substring(0, fixed.length - 3);
    final paise = fixed.substring(fixed.length - 2);
    var grouped = whole;
    if (whole.length > 3) {
      var head = whole.substring(0, whole.length - 3);
      final tail = whole.substring(whole.length - 3);
      final pairs = <String>[];
      while (head.length > 2) {
        pairs.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
      grouped = [head, ...pairs, tail].join(',');
    }
    return '${negative ? '-' : ''}₹$grouped.$paise';
  }

  /// Accepts "4500", "4,500.00" or "₹4,500"; null for anything else.
  static double? tryParse(String? text) {
    final cleaned = (text ?? '')
        .replaceAll('₹', '')
        .replaceAll('Rs.', '')
        .replaceAll(',', '')
        .trim();
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(cleaned)) return null;
    return double.tryParse(cleaned);
  }
}

/// The academic year runs from a start month (July unless the admin changed
/// it on the desktop) to the month before, a year later.
class AcademicYear {
  /// The academic year (its starting calendar year) that contains the date.
  static int of(DateTime date, int startMonth) =>
      date.month >= startMonth ? date.year : date.year - 1;

  /// "2026-2027" (or "2026" when the year runs January to December).
  static String label(int year, int startMonth) =>
      startMonth == 1 ? '$year' : '$year-${year + 1}';
}
