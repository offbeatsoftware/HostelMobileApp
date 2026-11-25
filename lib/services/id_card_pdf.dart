import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/id_card.dart';
import 'date_format.dart';

/// I-cards in the usual card size (85.6 x 54 mm), eight on an A4 page with
/// cutting space between them, as the desktop IdCardPdfWriter. A student
/// card has a terracotta band, a transport card a blue one with "TRANSPORT
/// PASS".
class IdCardPdf {
  static const businessName = 'Shri Balaji Hostel';

  static const _mm = 72 / 25.4;
  static const _cardWidth = 85.6 * _mm;
  static const _cardHeight = 54 * _mm;
  static const _gap = 8 * _mm;
  static const _columns = 2;
  static const _rows = 4;

  static const _terracotta = PdfColor.fromInt(0xFFC0652B);
  static const _transportBlue = PdfColor.fromInt(0xFF0066AA);
  static const _muted = PdfColor.fromInt(0xFF646464);
  static const _line = PdfColor.fromInt(0xFFD2C8B9);

  static pw.MemoryImage? _image(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static pw.TextStyle _s(double size, {bool bold = false, PdfColor? color}) =>
      pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  static pw.Widget _text(
    String text,
    pw.TextStyle style, {
    double? width,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.SizedBox(
    width: width,
    child: pw.Text(
      text,
      style: style,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      textAlign: align,
    ),
  );

  static pw.Widget _card(IdCard card, bool transport) {
    final colour = transport ? _transportBlue : _terracotta;
    const band = 30.0;
    const photoW = 58.0;
    const photoH = 72.0;
    const photoX = 8.0;
    const photoY = band + 6;
    const textX = photoX + photoW + 8;
    final textW = _cardWidth - 8 - textX;

    final lines = <(String, String)>[
      if (!transport) ('Father', card.fatherName),
      ('College', card.collegeName),
      ('Room', card.roomText.replaceFirst('Room ', '')),
      ('Mobile', card.studentMobile),
      if (!transport) ('Father mob.', card.fatherMobile),
    ].where((l) => l.$2.isNotEmpty).toList();

    final photo = _image(card.photo);
    return pw.Container(
      width: _cardWidth,
      height: _cardHeight,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: colour),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Stack(
        children: [
          // Band: hostel name and card title.
          pw.Positioned(
            left: 0,
            top: 0,
            child: pw.Container(
              width: _cardWidth - 2,
              height: band,
              decoration: pw.BoxDecoration(
                color: colour,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(9),
                  topRight: pw.Radius.circular(9),
                ),
              ),
            ),
          ),
          pw.Positioned(
            left: 8,
            top: 4,
            child: _text(
              card.hostelName,
              _s(9, bold: true, color: PdfColors.white),
              width: _cardWidth - 18,
              align: pw.TextAlign.center,
            ),
          ),
          pw.Positioned(
            left: 8,
            top: 17,
            child: _text(
              transport
                  ? 'TRANSPORT PASS  ${card.academicYear}'
                  : 'STUDENT IDENTITY CARD',
              _s(7, bold: true, color: PdfColors.white),
              width: _cardWidth - 18,
              align: pw.TextAlign.center,
            ),
          ),
          // Photo.
          pw.Positioned(
            left: photoX,
            top: photoY,
            child: pw.Container(
              width: photoW,
              height: photoH,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line, width: 0.8),
              ),
              alignment: pw.Alignment.center,
              child: photo == null
                  ? pw.Text('PHOTO', style: _s(7, color: _muted))
                  : pw.Image(photo, fit: pw.BoxFit.cover),
            ),
          ),
          // Details.
          pw.Positioned(
            left: textX,
            top: photoY,
            child: _text(card.studentName, _s(9, bold: true), width: textW),
          ),
          for (var i = 0; i < lines.length; i++)
            pw.Positioned(
              left: textX,
              top: photoY + 15 + i * 10,
              child: pw.Row(
                children: [
                  _text(lines[i].$1, _s(6.5, color: _muted), width: 40),
                  _text(lines[i].$2, _s(6.5, bold: true), width: textW - 40),
                ],
              ),
            ),
          // Footer: validity and signature.
          pw.Positioned(
            left: photoX,
            top: _cardHeight - 13,
            child: pw.Text(
              'Valid till ${formatDate(card.validTill)}',
              style: _s(6.5, bold: true, color: colour),
            ),
          ),
          if (card.hostelPhone.isNotEmpty)
            pw.Positioned(
              left: 8,
              top: _cardHeight - 13,
              child: _text(
                'Ph. ${card.hostelPhone}',
                _s(6, color: _muted),
                width: _cardWidth - 100,
                align: pw.TextAlign.right,
              ),
            ),
          pw.Positioned(
            left: _cardWidth - 80,
            top: _cardHeight - 13,
            child: pw.Container(width: 70, height: 0.5, color: _muted),
          ),
          pw.Positioned(
            left: _cardWidth - 80,
            top: _cardHeight - 11,
            child: _text(
              'Hostel Management',
              _s(6, color: _muted),
              width: 70,
              align: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> build(
    List<IdCard> cards, {
    required bool transport,
  }) {
    final doc = pw.Document(
      title: transport ? 'Transport I-cards' : 'Student I-cards',
      author: businessName,
    );
    final left =
        (PdfPageFormat.a4.width -
            (_columns * _cardWidth + (_columns - 1) * _gap)) /
        2;
    final top =
        (PdfPageFormat.a4.height - (_rows * _cardHeight + (_rows - 1) * _gap)) /
        2;
    const perPage = _columns * _rows;
    for (var start = 0; start < cards.length; start += perPage) {
      final page = cards.skip(start).take(perPage).toList();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              for (var i = 0; i < page.length; i++)
                pw.Positioned(
                  left: left + (i % _columns) * (_cardWidth + _gap),
                  top: top + (i ~/ _columns) * (_cardHeight + _gap),
                  child: _card(page[i], transport),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }
}
