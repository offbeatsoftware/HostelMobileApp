import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/report_table.dart';
import 'report_service.dart';

/// Makes the PDF and the Excel (CSV) file of a report, as the desktop's
/// Export PDF and Export Excel, and hands them to the phone's share sheet.
class ReportExport {
  /// A landscape A4 PDF: title, hostel and filters, then the table with
  /// subtotals and totals in bold.
  static Future<Uint8List> pdf(ReportTable report) async {
    final doc = pw.Document(title: report.title);
    final widths = {
      for (var i = 0; i < report.columns.length; i++)
        i: pw.FlexColumnWidth(report.columns[i].width),
    };
    const terracotta = PdfColor.fromInt(0xFFC0652B);
    pw.Widget cell(
      String text, {
      bool bold = false,
      bool right = false,
      PdfColor? color,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(
        text,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              report.title,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: terracotta,
              ),
            ),
            for (final s in report.subtitles)
              pw.Text(s, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Table(
            columnWidths: widths,
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.5,
              ),
            ),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: terracotta),
                children: [
                  for (final c in report.columns)
                    cell(
                      c.title,
                      bold: true,
                      right: c.alignRight,
                      color: PdfColors.white,
                    ),
                ],
              ),
              for (final r in report.rows)
                pw.TableRow(
                  decoration: r.style == ReportRowStyle.normal
                      ? null
                      : pw.BoxDecoration(
                          color: r.style == ReportRowStyle.total
                              ? PdfColor.fromInt(0xFFF5ECDC)
                              : PdfColor.fromInt(0xFFFBF7F0),
                        ),
                  children: [
                    for (var i = 0; i < report.columns.length; i++)
                      cell(
                        ReportService.format(r.values[i], pdf: true),
                        bold: r.style != ReportRowStyle.normal,
                        right: report.columns[i].alignRight,
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// The report as a CSV file Excel opens: amounts as plain numbers so they
  /// can be added up, dates as 24 Nov 2026.
  static String csv(ReportTable report) {
    String quote(String v) =>
        RegExp(r'[",\n\r]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    String value(Object? v) => switch (v) {
      null => '',
      double d => d.toStringAsFixed(2),
      DateTime _ => ReportService.format(v),
      _ => '$v'.trim(),
    };
    final lines = <String>[
      quote(report.title),
      for (final s in report.subtitles) quote(s),
      '',
      report.columns.map((c) => quote(c.title)).join(','),
      for (final r in report.rows)
        r.values.map((v) => quote(value(v))).join(','),
    ];
    return '${lines.join('\r\n')}\r\n';
  }

  static Future<void> Function(Uint8List bytes, String fileName) _sharePdf =
      (bytes, name) => Printing.sharePdf(bytes: bytes, filename: name);

  static Future<void> Function(Uint8List bytes, String fileName) _shareCsv =
      (bytes, name) => SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'text/csv', name: name)],
          fileNameOverrides: [name],
        ),
      );

  static Future<void> sharePdf(ReportTable report) async =>
      _sharePdf(await pdf(report), '${report.fileName}.pdf');

  /// UTF-8 with a byte order mark, so Excel shows ₹ and Hindi names right.
  static Future<void> shareCsv(ReportTable report) => _shareCsv(
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv(report))]),
    '${report.fileName}.csv',
  );

  @visibleForTesting
  static void useForTests({
    Future<void> Function(Uint8List, String)? sharePdf,
    Future<void> Function(Uint8List, String)? shareCsv,
  }) {
    _sharePdf =
        sharePdf ??
        (bytes, name) => Printing.sharePdf(bytes: bytes, filename: name);
    _shareCsv =
        shareCsv ??
        (bytes, name) => SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'text/csv', name: name)],
            fileNameOverrides: [name],
          ),
        );
  }
}
