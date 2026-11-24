import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/refund.dart';
import '../services/document_data.dart';
import '../services/document_email.dart';
import '../services/document_pdf.dart';
import '../services/document_share.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// "Invoice PDF", "Email receipt" and the like, used by the Invoices,
/// Payments and Refunds screens: makes the PDF (and the email text), then
/// opens the share sheet.
class DocumentActions {
  static Future<void> _run(
    BuildContext context,
    String failure,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on ValidationException catch (e) {
      if (context.mounted) showToast(context, e.message);
    } catch (e) {
      if (context.mounted) showToast(context, '$failure $e');
    }
  }

  static Future<void> invoicePdf(
    BuildContext context,
    Hostel hostel,
    Invoice invoice,
  ) => _run(context, 'The invoice PDF could not be made.', () async {
    final data = await DocumentData.invoice(hostel, invoice.invoiceId);
    await DocumentShare.pdf(
      await DocumentPdf.invoice(data),
      DocumentPdf.invoiceFileName(data.invoice),
    );
  });

  static Future<void> invoiceEmail(
    BuildContext context,
    Hostel hostel,
    Invoice invoice,
  ) => _run(context, 'The invoice email could not be prepared.', () async {
    final data = await DocumentData.invoice(hostel, invoice.invoiceId);
    final draft = await DocumentEmail.invoice(data);
    final pdf = await DocumentPdf.invoice(data);
    if (!context.mounted) return;
    await _share(
      context,
      draft,
      pdf,
      DocumentPdf.invoiceFileName(data.invoice),
    );
  });

  static Future<void> receiptPdf(
    BuildContext context,
    Hostel hostel,
    Payment payment,
  ) => _run(context, 'The receipt PDF could not be made.', () async {
    final data = await DocumentData.receipt(hostel, payment.paymentId);
    await DocumentShare.pdf(
      await DocumentPdf.receipt(data),
      DocumentPdf.receiptFileName(data.payment),
    );
  });

  static Future<void> receiptEmail(
    BuildContext context,
    Hostel hostel,
    Payment payment,
  ) => _run(context, 'The receipt email could not be prepared.', () async {
    final data = await DocumentData.receipt(hostel, payment.paymentId);
    final draft = await DocumentEmail.receipt(data);
    final pdf = await DocumentPdf.receipt(data);
    if (!context.mounted) return;
    await _share(
      context,
      draft,
      pdf,
      DocumentPdf.receiptFileName(data.payment),
    );
  });

  static Future<void> refundPdf(
    BuildContext context,
    Hostel hostel,
    Refund refund,
  ) => _run(context, 'The refund receipt could not be made.', () async {
    final data = await DocumentData.refund(hostel, refund.refundId);
    await DocumentShare.pdf(
      await DocumentPdf.refundReceipt(data),
      DocumentPdf.refundFileName(data.refund.refundNumber),
    );
  });

  static Future<void> refundEmail(
    BuildContext context,
    Hostel hostel,
    Refund refund,
  ) => _run(
    context,
    'The refund receipt email could not be prepared.',
    () async {
      final data = await DocumentData.refund(hostel, refund.refundId);
      final draft = await DocumentEmail.refund(data);
      final pdf = await DocumentPdf.refundReceipt(data);
      if (!context.mounted) return;
      await _share(
        context,
        draft,
        pdf,
        DocumentPdf.refundFileName(data.refund.refundNumber),
      );
    },
  );

  /// Shows who the email is for and its text, then shares it with the PDF.
  static Future<void> _share(
    BuildContext context,
    EmailDraft draft,
    Uint8List pdf,
    String fileName,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _EmailDraftDialog(draft: draft, fileName: fileName),
    );
    if (ok == true) {
      await DocumentShare.email(pdf, fileName, draft.subject, draft.body);
    }
  }
}

class _EmailDraftDialog extends StatelessWidget {
  const _EmailDraftDialog({required this.draft, required this.fileName});

  final EmailDraft draft;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    );
    return AlertDialog(
      title: const Text('Email'),
      content: SingleChildScrollView(
        child: Column(
          key: const Key('emailDraft'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('To (${draft.relation}: ${draft.parentName})'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.to,
                    key: const Key('draftTo'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const Key('copyAddress'),
                  tooltip: 'Copy address',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: draft.to));
                    if (context.mounted) {
                      showToast(context, 'Address copied.');
                    }
                  },
                ),
              ],
            ),
            if (draft.copyTo.isNotEmpty) ...[
              label('Copy to the admin'),
              Text(draft.copyTo, key: const Key('draftCopyTo')),
            ],
            label('Subject'),
            Text(draft.subject, key: const Key('draftSubject')),
            label('Message'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F0E8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(draft.body, key: const Key('draftBody')),
            ),
            label('Attachment'),
            Text(fileName),
            const SizedBox(height: 12),
            const Text(
              'Choose your mail app on the next screen, then paste the '
              'address (copy it first) and send.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('shareEmail'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.terracotta),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Open Mail App'),
        ),
      ],
    );
  }
}
