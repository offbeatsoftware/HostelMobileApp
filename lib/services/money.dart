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

  /// "Rs. 1,25,000.00": the rupee sign is not in every PDF font, so PDFs and
  /// emails write Rs. (as the desktop does).
  static String rupees(double amount) =>
      'Rs. ${format(amount).replaceFirst('₹', '')}';

  /// The amount in words in the Indian system, as written on receipts:
  /// 125000.50 is "Rupees One Lakh Twenty Five Thousand and Fifty Paise Only".
  static String inWords(double amount) {
    final total = (amount.abs() * 100).round();
    final rupees = total ~/ 100;
    final paise = total % 100;
    var words = 'Rupees ${rupees == 0 ? 'Zero' : _indianWords(rupees)}';
    if (paise > 0) words += ' and ${_indianWords(paise)} Paise';
    return '$words Only';
  }

  static const _ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];

  static const _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String _indianWords(int number) {
    final parts = <String>[];
    for (final (size, name) in [
      (10000000, 'Crore'),
      (100000, 'Lakh'),
      (1000, 'Thousand'),
      (100, 'Hundred'),
    ]) {
      if (number >= size) {
        // Crores can exceed 99, so they are written in words recursively.
        parts.add('${_indianWords(number ~/ size)} $name');
        number %= size;
      }
    }
    if (number > 0) {
      parts.add(
        number < 20
            ? _ones[number]
            : '${_tens[number ~/ 10]} ${_ones[number % 10]}'.trim(),
      );
    }
    return parts.join(' ');
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

  /// The first day of the academic year.
  static DateTime start(int year, int startMonth) =>
      DateTime(year, startMonth, 1);

  /// The last day of the academic year.
  static DateTime end(int year, int startMonth) =>
      DateTime(year + 1, startMonth, 1).subtract(const Duration(days: 1));
}
