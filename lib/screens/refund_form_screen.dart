import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../models/payment.dart';
import '../services/billing_service.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Pay back all or part of what was paid on one of the fees (the desktop
/// RefundForm). Closes with a message when saved.
class RefundFormScreen extends StatefulWidget {
  const RefundFormScreen({
    super.key,
    required this.invoices,
    required this.startMonth,
    this.invoice,
    this.today,
  });

  /// The hostel's invoices (those with money paid are offered).
  final List<Invoice> invoices;
  final int startMonth;

  /// The fee to refund from, when known.
  final Invoice? invoice;
  final DateTime? today;

  @override
  State<RefundFormScreen> createState() => _RefundFormScreenState();
}

class _RefundFormScreenState extends State<RefundFormScreen> {
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late DateTime _date = _today;
  String _method = PaymentMethod.cash;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  Invoice? _invoice;
  String _message = '';
  bool _busy = false;

  List<Invoice> get _refundable =>
      BillingService.refundableInvoices(widget.invoices);

  @override
  void initState() {
    super.initState();
    _invoice = _refundable
        .where((i) => i.invoiceId == widget.invoice?.invoiceId)
        .firstOrNull;
  }

  @override
  void dispose() {
    for (final c in [_amount, _reference, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  String _year(int y) => AcademicYear.label(y, widget.startMonth);

  Future<bool> _confirm(Invoice invoice, String amountText) async {
    final amount = Money.tryParse(amountText);
    if (amount == null) return true; // the service explains what is wrong
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Refund'),
            content: Text(
              'Refund ${Money.format(amount)} from invoice '
              '${invoice.invoiceNumber}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('confirmRefund'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Refund'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final invoice = _invoice;
    if (invoice != null && Money.tryParse(_amount.text) != null) {
      if (!await _confirm(invoice, _amount.text) || !mounted) return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final number = await BillingService.recordRefund(
        invoice: invoice,
        date: _date,
        today: _today,
        amountText: _amount.text,
        method: _method,
        reference: _reference.text,
        reason: _reason.text,
      );
      if (mounted) Navigator.of(context).pop('Refund recorded: $number.');
    } on ValidationException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('The refund could not be saved. $e');
    }
  }

  void _show(String m) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = _invoice;
    final refName = PaymentMethod.referenceName(_method);
    return Scaffold(
      appBar: AppBar(title: const Text('Refund')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormDropdown<int>(
              key: const Key('refundInvoice'),
              label: 'From fee (invoice)',
              required: true,
              value: i?.invoiceId,
              enabled: !_busy,
              items: [
                for (final inv in _refundable)
                  DropdownMenuItem(
                    value: inv.invoiceId,
                    child: Text(
                      '${inv.studentName}  ·  ${inv.invoiceNumber}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => setState(() {
                _invoice = _refundable
                    .where((x) => x.invoiceId == id)
                    .firstOrNull;
                _amount.clear();
              }),
            ),
            if (i != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Fee ${_year(i.academicYear)}: ${Money.format(i.totalAmount)}, '
                  'paid ${Money.format(i.paidAmount)}'
                  '${i.refundedAmount > 0 ? ' (after ${Money.format(i.refundedAmount)} refunded)' : ''}'
                  ', pending ${Money.format(i.pendingAmount)}. '
                  'Can refund up to ${Money.format(i.paidAmount)}.',
                  key: const Key('refundInvoiceInfo'),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            DateField(
              key: const Key('refundDate'),
              label: 'Refund date',
              value: _date,
              required: true,
              enabled: !_busy,
              firstDate: DateTime(2000),
              lastDate: _today,
              onChanged: (d) => setState(() => _date = d ?? _date),
            ),
            FormTextField(
              key: const Key('refundAmount'),
              label: 'Amount',
              controller: _amount,
              maxLength: 15,
              required: true,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              enabled: !_busy,
            ),
            FormDropdown<String>(
              key: const Key('refundMethod'),
              label: 'Paid back by',
              required: true,
              value: _method,
              enabled: !_busy,
              items: [
                for (final m in PaymentMethod.all)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (m) => setState(() => _method = m ?? _method),
            ),
            FormTextField(
              key: const Key('refundReference'),
              label: PaymentMethod.requiresReference(_method)
                  ? refName
                  : 'Reference (optional for cash)',
              controller: _reference,
              maxLength: 100,
              required: PaymentMethod.requiresReference(_method),
              keyboard: TextInputType.text,
              enabled: !_busy,
            ),
            FormTextField(
              key: const Key('refundReason'),
              label: 'Reason (for example: left the hostel in December)',
              controller: _reason,
              maxLength: 255,
              required: true,
              maxLines: 2,
              keyboard: TextInputType.multiline,
              enabled: !_busy,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'A refund pays money back and lowers the fee by the same '
                'amount, so the pending amount does not change. It can be at '
                'most what is paid on the fee after earlier refunds.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            FormMessage(_message, key: const Key('refundMessage')),
            SaveButton(
              key: const Key('saveRefund'),
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
