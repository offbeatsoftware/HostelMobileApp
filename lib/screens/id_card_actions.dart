import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../models/hostel.dart';
import '../services/date_format.dart';
import '../services/document_share.dart';
import '../services/id_card_pdf.dart';
import '../services/id_card_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Student and transport I-cards of the chosen students as one PDF, shared
/// for printing (the desktop IdCardActions).
class IdCardActions {
  static Future<void> make(
    BuildContext context,
    Hostel hostel,
    List<int> studentIds, {
    required bool transport,
    DateTime? today,
  }) async {
    if (studentIds.isEmpty) {
      showToast(context, 'Please select one or more students.');
      return;
    }
    try {
      final now = dateOnly(today ?? DateTime.now());
      final startMonth = await BillingRepository.instance
          .getAcademicYearStartMonth();
      if (!context.mounted) return;
      final validTill = await showDialog<DateTime>(
        context: context,
        builder: (_) => _ValidTillDialog(
          transport: transport,
          count: studentIds.length,
          today: now,
          suggested: IdCardService.defaultValidTill(now, startMonth),
        ),
      );
      if (validTill == null || !context.mounted) return;

      final result = await IdCardService.prepare(
        hostel,
        studentIds,
        transport: transport,
        today: now,
        validTill: validTill,
      );
      if (!context.mounted) return;
      if (result.cards.isEmpty) {
        await _note(
          context,
          transport,
          'No I-card could be made:',
          result.problems,
        );
        return;
      }
      final pdf = await IdCardPdf.build(result.cards, transport: transport);
      if (result.problems.isNotEmpty && context.mounted) {
        await _note(
          context,
          transport,
          '${result.cards.length} I-card(s) were made. Please note:',
          result.problems,
        );
      }
      await DocumentShare.pdf(pdf, IdCardService.fileName(transport, now));
    } on ValidationException catch (e) {
      if (context.mounted) showToast(context, e.message);
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'The I-cards could not be created. $e');
      }
    }
  }

  static Future<void> _note(
    BuildContext context,
    bool transport,
    String heading,
    List<String> problems,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(transport ? 'Transport I-Cards' : 'Student I-Cards'),
      content: SingleChildScrollView(
        child: Text(
          '$heading\n\n${problems.map((p) => '• $p').join('\n')}',
          key: const Key('idCardNote'),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('idCardNoteOk'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Asks for the "Valid till" date printed on the cards; it starts as the end
/// of the academic year.
class _ValidTillDialog extends StatefulWidget {
  const _ValidTillDialog({
    required this.transport,
    required this.count,
    required this.today,
    required this.suggested,
  });

  final bool transport;
  final int count;
  final DateTime today;
  final DateTime suggested;

  @override
  State<_ValidTillDialog> createState() => _ValidTillDialogState();
}

class _ValidTillDialogState extends State<_ValidTillDialog> {
  late DateTime _date = widget.suggested.isBefore(widget.today)
      ? widget.today
      : widget.suggested;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.transport ? 'Transport I-Cards' : 'Student I-Cards'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'I-cards for ${widget.count} student(s). Enter the date printed '
            'after "Valid till" on the cards.',
            key: const Key('validTillIntro'),
          ),
          const SizedBox(height: 14),
          DateField(
            key: const Key('validTill'),
            label: 'Valid till',
            value: _date,
            required: true,
            firstDate: widget.today,
            lastDate: DateTime(widget.today.year + 10),
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('makeCards'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.terracotta),
          onPressed: () => Navigator.of(context).pop(_date),
          child: const Text('Make Cards'),
        ),
      ],
    );
  }
}
