import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/agreement.dart';
import 'date_format.dart';

/// The residency agreement as an A4 PDF, as the desktop AgreementPdfWriter:
/// the title in red as on the client's form, wrapped paragraphs over as many
/// pages as needed, filled in values in bold, the student's photo (or a box
/// to paste one) at the top right, and the signature lines at the end with
/// any signatures made on screen above them.
class AgreementPdf {
  static const businessName = 'Shri Balaji Hostel';

  static const _titleRed = PdfColor.fromInt(0xFFDC1E1E);
  static const _muted = PdfColor.fromInt(0xFF646464);

  static const _photoWidth = 84.0;
  static const _photoHeight = 105.0;

  /// The text split into words with bold marked, for one paragraph.
  static List<pw.InlineSpan> _spans(String line) {
    final spans = <pw.InlineSpan>[];
    final buffer = StringBuffer();
    var bold = false;
    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        pw.TextSpan(
          text: buffer.toString(),
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
      buffer.clear();
    }

    for (final c in line.split('')) {
      if (c == AgreementDocument.valueStart ||
          c == AgreementDocument.valueEnd) {
        flush();
        bold = c == AgreementDocument.valueStart;
      } else {
        buffer.write(c);
      }
    }
    flush();
    return spans;
  }

  static String _plain(String text) => text
      .replaceAll(AgreementDocument.valueStart, '')
      .replaceAll(AgreementDocument.valueEnd, '');

  /// The image, or null when the bytes are not a readable image (the
  /// agreement is still made, without it).
  static pw.MemoryImage? _image(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _photoBox(Uint8List? photo) {
    final image = _image(photo);
    return _photoFrame(image);
  }

  static pw.Widget _photoFrame(pw.MemoryImage? image) => pw.Container(
    width: _photoWidth,
    height: _photoHeight,
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
    alignment: pw.Alignment.center,
    child: image == null
        ? pw.Text(
            'Paste photo',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          )
        : pw.Image(image, fit: pw.BoxFit.cover),
  );

  static pw.Widget _signature(Uint8List? image, String label, String name) =>
      pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(right: 20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                height: 42,
                alignment: pw.Alignment.bottomLeft,
                child: _image(image) == null
                    ? null
                    : pw.Image(_image(image)!, fit: pw.BoxFit.contain),
              ),
              pw.Container(height: 0.6, color: PdfColors.black),
              pw.SizedBox(height: 4),
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(name, style: const pw.TextStyle(fontSize: 10.5)),
            ],
          ),
        ),
      );

  static Future<Uint8List> build(AgreementDocument d) {
    final doc = pw.Document(
      title: 'Residency agreement, ${d.studentName}',
      author: businessName,
    );
    final signed = d.signatures;
    final lines = d.filledText.split('\n').map((l) => l.trimRight());

    final body = <pw.Widget>[];
    String? title;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        body.add(pw.SizedBox(height: 5));
      } else if (line.startsWith('# ')) {
        title ??= _plain(line.substring(2));
        if (title != _plain(line.substring(2))) {
          body.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Center(
                child: pw.Text(
                  _plain(line.substring(2)),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _titleRed,
                  ),
                ),
              ),
            ),
          );
        }
      } else if (line.startsWith('## ')) {
        body.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
            child: pw.Text(
              _plain(line.substring(3)),
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );
      } else {
        body.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2.5),
                children: _spans(line),
              ),
            ),
          ),
        );
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(56),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        build: (context) => [
          // The title sits beside the photo box, top right.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6, right: 14),
                  child: pw.Center(
                    child: pw.Text(
                      title ?? '',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _titleRed,
                      ),
                    ),
                  ),
                ),
              ),
              _photoBox(d.photo),
            ],
          ),
          pw.SizedBox(height: 10),
          ...body,
          pw.SizedBox(height: 24),
          pw.Wrap(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _signature(signed?.owner, 'First Party (Owner)', ''),
                  _signature(
                    signed?.student,
                    'Second Party (Student)',
                    d.studentName,
                  ),
                ],
              ),
              pw.SizedBox(height: 14, width: 500),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _signature(signed?.parent, 'Parent / Guardian', d.parentName),
                  _signature(
                    signed?.witness,
                    'Witness',
                    signed?.witnessName ?? '',
                  ),
                ],
              ),
              if (signed?.signedDate != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 14),
                  child: pw.Text(
                    'Signed on ${formatDate(signed!.signedDate!)}',
                    style: const pw.TextStyle(fontSize: 10.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}
