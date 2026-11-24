import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/print_data.dart';
import '../models/student.dart';
import 'date_format.dart';
import 'money.dart';

/// The invoice, payment receipt and refund receipt PDFs, laid out as the
/// desktop's InvoicePdfWriter, ReceiptPdfWriter and RefundReceiptPdfWriter.
/// Amounts are written Rs. (the rupee sign is not in the PDF font).
class DocumentPdf {
  static const businessName = 'Shri Balaji Hostel';
  static const productName = 'Hostel Management System';

  static const _terracotta = PdfColor.fromInt(0xFFC0652B);
  static const _muted = PdfColor.fromInt(0xFF646464);
  static const _line = PdfColor.fromInt(0xFFD2C8B9);
  static const _fill = PdfColor.fromInt(0xFFF5ECDC);

  static const _body = 9.5;

  /// "Invoice_SBH-2026-2027-0001.pdf".
  static String invoiceFileName(Invoice i) =>
      'Invoice_${i.invoiceNumber.replaceAll('/', '-')}.pdf';

  /// "Receipt_SBH-R-2026-2027-0001.pdf".
  static String receiptFileName(Payment p) =>
      'Receipt_${p.receiptNumber.replaceAll('/', '-')}.pdf';

  /// "Refund_SBH-RF-2026-2027-0001.pdf".
  static String refundFileName(String refundNumber) =>
      'Refund_${refundNumber.replaceAll('/', '-')}.pdf';

  /// Joins label and value pairs, leaving out pairs whose value is empty.
  static String join(List<String?> labelValuePairs) {
    final parts = <String>[];
    for (var i = 0; i + 1 < labelValuePairs.length; i += 2) {
      final value = (labelValuePairs[i + 1] ?? '').trim();
      if (value.isNotEmpty) parts.add('${labelValuePairs[i]}$value');
    }
    return parts.join().replaceAll(RegExp(r'^[ ,]+|[ ,]+$'), '');
  }

  // ---- shared pieces ----

  static pw.TextStyle _s(double size, {bool bold = false, PdfColor? color}) =>
      pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  static pw.Widget _header(String title, Hostel hostel) {
    final lines = [
      hostel.address ?? '',
      join(['Phone: ', hostel.phone, '   Email: ', hostel.email]),
    ].where((l) => l.isNotEmpty);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              businessName,
              style: _s(20, bold: true, color: _terracotta),
            ),
            pw.Text(title, style: _s(20, bold: true)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(hostel.hostelName, style: _s(11, bold: true)),
        for (final l in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(l, style: _s(_body, color: _muted)),
          ),
        pw.SizedBox(height: 8),
        pw.Container(height: 1.5, color: _terracotta),
        pw.SizedBox(height: 14),
      ],
    );
  }

  /// A heading and lines on the left, label and value pairs on the right.
  static pw.Widget _parties(
    String heading,
    List<(String, bool)> left,
    List<(String, String)> right,
  ) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(heading, style: _s(11, bold: true)),
            pw.SizedBox(height: 6),
            for (final (text, bold) in left)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(text, style: _s(_body, bold: bold)),
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 20),
      pw.Expanded(
        child: pw.Column(
          children: [
            for (final (label, value) in right)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 100,
                      child: pw.Text(label, style: _s(_body, color: _muted)),
                    ),
                    pw.Expanded(
                      child: pw.Text(value, style: _s(_body, bold: true)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  /// The student's lines: a receipt shows the college, mobile and father;
  /// an invoice ([roomText] given) also the room, course, class and mother.
  static List<(String, bool)> _studentLines(Student s, {String? roomText}) {
    final invoice = roomText != null;
    return [
      (s.studentName, true),
      if (invoice)
        (join(['', roomText, ', ', s.collegeName]), false)
      else
        (s.collegeName ?? '', false),
      if (invoice)
        (join(['Course: ', s.course, '   Class: ', s.className]), false),
      (join(['Mobile: ', s.mobile]), false),
      (
        invoice
            ? join(['Father: ', s.fatherName, ', ', s.fatherMobile])
            : join(['Father: ', s.fatherName]),
        false,
      ),
      if (invoice)
        (join(['Mother: ', s.motherName, ', ', s.motherMobile]), false),
    ].where((l) => l.$1.isNotEmpty).toList();
  }

  static pw.Widget _table(
    List<pw.TableColumnWidth> widths,
    List<String> header,
    List<List<String>> rows, {
    int leftColumns = 1,
  }) {
    pw.Widget cell(String text, int i, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: i < leftColumns ? pw.TextAlign.left : pw.TextAlign.right,
        style: _s(_body, bold: bold),
      ),
    );
    return pw.Table(
      columnWidths: {for (var i = 0; i < widths.length; i++) i: widths[i]},
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.5),
        bottom: pw.BorderSide(color: _line, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _fill),
          children: [
            for (var i = 0; i < header.length; i++)
              cell(header[i], i, bold: true),
          ],
        ),
        for (final r in rows)
          pw.TableRow(
            children: [for (var i = 0; i < r.length; i++) cell(r[i], i)],
          ),
      ],
    );
  }

  /// Label and amount lines, right aligned.
  static pw.Widget _amounts(List<(String, double, bool)> lines) => pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 280,
      child: pw.Column(
        children: [
          for (final (label, amount, bold) in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      label,
                      textAlign: pw.TextAlign.right,
                      style: _s(bold ? 11 : _body, bold: bold),
                    ),
                  ),
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      Money.rupees(amount),
                      textAlign: pw.TextAlign.right,
                      style: _s(bold ? 11 : _body, bold: bold),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  static pw.Widget _amountBox(String label, double amount) => pw.Container(
    color: _fill,
    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: _s(_body, color: _muted)),
            pw.Text(Money.rupees(amount), style: _s(16, bold: true)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(Money.inWords(amount), style: _s(_body, bold: true)),
      ],
    ),
  );

  static pw.Widget _signature(String footer) => pw.Column(
    children: [
      pw.SizedBox(height: 30),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 160,
          child: pw.Column(
            children: [
              pw.Container(height: 0.5, color: _line),
              pw.SizedBox(height: 3),
              pw.Text('Authorised signatory', style: _s(8, color: _muted)),
            ],
          ),
        ),
      ),
      pw.SizedBox(height: 20),
      pw.Container(height: 0.5, color: _line),
      pw.SizedBox(height: 8),
      pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(footer, style: _s(8, color: _muted)),
      ),
    ],
  );

  static Future<Uint8List> _save(
    String title,
    List<pw.Widget> Function() build, {
    pw.Widget Function(pw.Context)? footer,
  }) {
    final doc = pw.Document(title: title, author: businessName);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: footer,
        build: (_) => build(),
      ),
    );
    return doc.save();
  }

  // ---- the documents ----

  /// The yearly invoice: the fee, every payment received, refunds given and
  /// the amount pending.
  static Future<Uint8List> invoice(InvoicePrintData d) {
    final i = d.invoice;
    final year = AcademicYear.label(i.academicYear, d.startMonth);
    final fee = <(String, double)>[
      ('Room rent${d.roomText.isEmpty ? '' : ' (${d.roomText})'}', i.roomRent),
      if (i.transportAmount > 0) ('Transport', i.transportAmount),
    ];
    return _save(
      'Invoice ${i.invoiceNumber}',
      () => [
        _header('INVOICE', d.hostel),
        _parties('Bill to', _studentLines(d.student, roomText: d.roomText), [
          ('Invoice number', i.invoiceNumber),
          (
            'Invoice date',
            i.invoiceDate == null ? '' : formatDate(i.invoiceDate!),
          ),
          ('Academic year', year),
          ('Status', i.status),
        ]),
        pw.SizedBox(height: 16),
        _table(
          [const pw.FlexColumnWidth(), const pw.FixedColumnWidth(140)],
          ['Fee for the academic year $year', 'Amount'],
          [
            for (final (text, amount) in fee) [text, Money.rupees(amount)],
            ['Total fee', Money.rupees(i.feeAmount)],
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Text('Payments received', style: _s(11, bold: true)),
        pw.SizedBox(height: 6),
        _table(
          [
            const pw.FixedColumnWidth(80),
            const pw.FixedColumnWidth(130),
            const pw.FixedColumnWidth(95),
            const pw.FlexColumnWidth(),
            const pw.FixedColumnWidth(110),
          ],
          ['Date', 'Receipt', 'Method', 'Reference', 'Amount'],
          d.payments.isEmpty
              ? [
                  ['No payment received yet.', '', '', '', ''],
                ]
              : [
                  for (final p in d.payments)
                    [
                      formatDate(p.paymentDate),
                      p.receiptNumber,
                      p.paymentMethod,
                      p.reference ?? '',
                      Money.rupees(p.amount),
                    ],
                ],
          leftColumns: 4,
        ),
        if (d.refunds.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text('Refunds given', style: _s(11, bold: true)),
          pw.SizedBox(height: 6),
          _table(
            [
              const pw.FixedColumnWidth(80),
              const pw.FixedColumnWidth(130),
              const pw.FixedColumnWidth(95),
              const pw.FlexColumnWidth(),
              const pw.FixedColumnWidth(110),
            ],
            ['Date', 'Refund no.', 'Method', 'Reason', 'Amount'],
            [
              for (final r in d.refunds)
                [
                  formatDate(r.refundDate),
                  r.refundNumber,
                  r.refundMethod,
                  r.reason,
                  Money.rupees(r.amount),
                ],
            ],
            leftColumns: 4,
          ),
        ],
        pw.SizedBox(height: 14),
        _amounts([
          ('Total fee', i.feeAmount, false),
          if (i.waivedAmount > 0)
            ('Waived at check-out', i.waivedAmount, false),
          ('Total paid', i.receivedAmount, false),
          if (i.refundedAmount > 0) ...[
            ('Refunded', i.refundedAmount, false),
            ('Paid after refunds', i.paidAmount, false),
          ],
          ('Pending', i.pendingAmount, true),
        ]),
        if (i.pendingAmount > 0)
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Pending: ${Money.inWords(i.pendingAmount)}',
                style: _s(8, color: _muted),
              ),
            ),
          ),
      ],
      footer: (context) => pw.Column(
        children: [
          pw.Container(height: 0.5, color: _line),
          pw.SizedBox(height: 6),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              'Computer generated invoice from the $productName.',
              style: _s(8, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  /// The payment receipt.
  static Future<Uint8List> receipt(ReceiptPrintData d) {
    final p = d.payment;
    final i = d.invoice;
    final year = AcademicYear.label(i.academicYear, d.startMonth);
    return _save(
      'Receipt ${p.receiptNumber}',
      () => [
        _header('RECEIPT', d.hostel),
        _parties('Received from', _studentLines(d.student), [
          ('Receipt number', p.receiptNumber),
          ('Payment date', formatDate(p.paymentDate)),
          ('Paid by', p.paymentMethod),
          if ((p.reference ?? '').isNotEmpty)
            (PaymentMethod.referenceName(p.paymentMethod), p.reference!),
        ]),
        pw.SizedBox(height: 14),
        _amountBox('Amount received', p.amount),
        pw.SizedBox(height: 12),
        pw.Text(
          'Towards the hostel fee for the academic year $year (invoice '
          '${i.invoiceNumber}, total fee ${Money.rupees(i.totalAmount)}).',
          style: _s(_body),
        ),
        // Payment remarks are notes for the hostel only and are not printed.
        pw.SizedBox(height: 12),
        _amounts([
          ('Invoice total', i.totalAmount, false),
          ('Paid till date', i.paidAmount, false),
          ('Balance pending', i.pendingAmount, true),
        ]),
        _signature('Computer generated receipt from the $productName.'),
      ],
    );
  }

  /// The refund receipt.
  static Future<Uint8List> refundReceipt(RefundPrintData d) {
    final r = d.refund;
    final i = d.invoice;
    final year = AcademicYear.label(i.academicYear, d.startMonth);
    return _save(
      'Refund receipt ${r.refundNumber}',
      () => [
        _header('REFUND RECEIPT', d.hostel),
        _parties('Refunded to', _studentLines(d.student), [
          ('Refund number', r.refundNumber),
          ('Refund date', formatDate(r.refundDate)),
          ('Paid back by', r.refundMethod),
          if ((r.reference ?? '').isNotEmpty)
            (PaymentMethod.referenceName(r.refundMethod), r.reference!),
        ]),
        pw.SizedBox(height: 14),
        _amountBox('Amount refunded', r.amount),
        pw.SizedBox(height: 12),
        pw.Text(
          'From the hostel fee for the academic year $year (invoice '
          '${i.invoiceNumber}).',
          style: _s(_body),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Reason: ${r.reason}', style: _s(_body)),
        pw.SizedBox(height: 12),
        // A refund lowers the fee and the paid amount alike.
        _amounts([
          ('Fee agreed', i.feeAmount, false),
          if (i.waivedAmount > 0) ('Waived', i.waivedAmount, false),
          ('Refunded in total', i.refundedAmount, false),
          ('Fee after refunds', i.totalAmount, false),
          ('Paid after refunds', i.paidAmount, false),
          ('Balance pending', i.pendingAmount, true),
        ]),
        _signature('Computer generated refund receipt from the $productName.'),
      ],
    );
  }
}
