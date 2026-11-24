import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../services/billing_service.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../widgets/common_widgets.dart';

/// Edit Fee: changes the room rent and transport of one invoice (the
/// desktop FeeEditForm). Closes with true when saved.
class FeeEditScreen extends StatefulWidget {
  const FeeEditScreen({
    super.key,
    required this.invoice,
    required this.yearText,
  });

  final Invoice invoice;

  /// "2026-2027".
  final String yearText;

  @override
  State<FeeEditScreen> createState() => _FeeEditScreenState();
}

class _FeeEditScreenState extends State<FeeEditScreen> {
  late final _rent = TextEditingController(
    text: widget.invoice.roomRent.toStringAsFixed(2),
  );
  late final _transport = TextEditingController(
    text: widget.invoice.transportAmount.toStringAsFixed(2),
  );
  late final _remarks = TextEditingController(text: widget.invoice.remarks);
  String _message = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rent.addListener(() => setState(() {}));
    _transport.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _rent.dispose();
    _transport.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await BillingService.updateFee(
        widget.invoice,
        _rent.text,
        _transport.text,
        _remarks.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('The fee could not be saved. $e');
    }
  }

  void _show(String m) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = m;
    });
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final i = widget.invoice;
    final rent = Money.tryParse(_rent.text);
    final transport = _transport.text.trim().isEmpty
        ? 0.0
        : Money.tryParse(_transport.text);
    final total = rent == null || transport == null
        ? null
        : rent + transport - i.waivedAmount - i.refundedAmount;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Fee')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _info('Invoice', '${i.invoiceNumber} (${widget.yearText})'),
            _info('Student', i.studentName),
            _info('Paid so far', Money.format(i.paidAmount)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FormTextField(
                    key: const Key('feeRent'),
                    label: 'Room rent / year',
                    controller: _rent,
                    maxLength: 15,
                    required: true,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FormTextField(
                    key: const Key('feeTransport'),
                    label: 'Transport / year',
                    controller: _transport,
                    maxLength: 15,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_busy,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                total == null
                    ? 'Total fee: enter the amounts'
                    : 'Total fee: ${Money.format(total)}   (pending '
                          '${Money.format((total - i.paidAmount).clamp(0, double.infinity))})',
                key: const Key('feeTotal'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            FormTextField(
              key: const Key('feeRemarks'),
              label: 'Remarks',
              controller: _remarks,
              maxLength: 255,
              maxLines: 2,
              keyboard: TextInputType.multiline,
              enabled: !_busy,
            ),
            FormMessage(_message, key: const Key('feeMessage')),
            SaveButton(
              key: const Key('saveFee'),
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
