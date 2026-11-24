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

  /// Whole rupees for headline figures, for example ₹2,68,500.
  static String formatWhole(double amount) {
    final text = format(amount.roundToDouble());
    return text.substring(0, text.length - 3);
  }

  /// Whole rupees when the amount has no paise (₹85,000), otherwise with
  /// the paise (₹39,999.50), so figures shown side by side add up.
  static String formatExact(double amount) =>
      amount == amount.roundToDouble() ? formatWhole(amount) : format(amount);

  /// Short amount for chart axes in the Indian system: ₹850, ₹45K, ₹1.2L,
  /// ₹2.5Cr.
  static String compact(double amount) {
    String one(double v) {
      final t = v.toStringAsFixed(1);
      return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
    }

    if (amount >= 10000000) return '₹${one(amount / 10000000)}Cr';
    if (amount >= 100000) return '₹${one(amount / 100000)}L';
    if (amount >= 1000) return '₹${one(amount / 1000)}K';
    return '₹${amount.toStringAsFixed(0)}';
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
