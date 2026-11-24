/// How a report value is shown.
enum ReportValueKind { text, number, money, date }

/// How a report row is shown: a normal line, a subtotal, a group heading
/// (a student on Pending Fees) or the grand total.
enum ReportRowStyle { normal, subtotal, group, total }

class ReportColumn {
  const ReportColumn(
    this.title, {
    this.kind = ReportValueKind.text,
    this.width = 1,
  });

  final String title;
  final ReportValueKind kind;

  /// Relative width in the PDF.
  final double width;

  bool get alignRight =>
      kind == ReportValueKind.money || kind == ReportValueKind.number;
}

class ReportRow {
  const ReportRow(this.values, [this.style = ReportRowStyle.normal]);

  /// One value per column: String, int, double (money) or DateTime; null
  /// for an empty cell.
  final List<Object?> values;
  final ReportRowStyle style;
}

/// A report as the desktop ReportTable: shown on screen and exported.
class ReportTable {
  const ReportTable({
    required this.title,
    required this.subtitles,
    required this.columns,
    required this.rows,
    required this.fileName,
  });

  final String title;

  /// Hostel, filters and when it was made.
  final List<String> subtitles;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;

  /// Without extension, for example "Payments_Shri-Balaji-Hostel_2026-11-01_to_2026-11-24".
  final String fileName;
}
