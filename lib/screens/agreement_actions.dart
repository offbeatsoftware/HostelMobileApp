import 'package:flutter/material.dart';

import '../models/hostel.dart';
import '../models/student.dart';
import '../services/agreement_pdf.dart';
import '../services/agreement_service.dart';
import '../services/document_share.dart';
import '../services/validators.dart';
import '../widgets/common_widgets.dart';
import 'agreement_sign_screen.dart';

/// Agreement PDF and Sign Agreement, used by the Students and Room
/// Allocation screens (the desktop AgreementActions).
class AgreementActions {
  /// Makes the student's agreement PDF and opens the share sheet.
  static Future<void> pdf(
    BuildContext context,
    Hostel hostel,
    Student student, {
    DateTime? today,
  }) async {
    try {
      final date = today ?? DateTime.now();
      final doc = await AgreementService.prepare(
        hostel,
        student.studentId,
        date,
      );
      await DocumentShare.pdf(
        await AgreementPdf.build(doc),
        AgreementService.fileName(doc, date),
      );
    } on ValidationException catch (e) {
      if (context.mounted) showToast(context, e.message);
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'The agreement PDF could not be created. $e');
      }
    }
  }

  /// Opens Sign Agreement for a checked-in student; after Save and Make PDF
  /// the agreement PDF follows.
  static Future<void> sign(
    BuildContext context,
    Hostel hostel,
    Student student, {
    DateTime? today,
  }) async {
    try {
      // The agreement needs the student's room: check that first, so nobody
      // signs for nothing.
      await AgreementService.prepare(
        hostel,
        student.studentId,
        today ?? DateTime.now(),
      );
    } on ValidationException catch (e) {
      if (context.mounted) showToast(context, e.message);
      return;
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'The agreement could not be signed. $e');
      }
      return;
    }
    if (!context.mounted) return;
    final makePdf = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AgreementSignScreen(hostel: hostel, student: student, today: today),
      ),
    );
    if (makePdf == null || !context.mounted) return;
    showToast(context, 'The signatures were saved.');
    if (makePdf) await pdf(context, hostel, student, today: today);
  }
}
