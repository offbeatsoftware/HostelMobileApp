import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../models/payment.dart';
import '../services/billing_service.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Record a payment against an invoice, or correct one (the desktop
/// PaymentForm and PaymentEditForm). Closes with a message when saved.
class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({
    super.key,
    required this.invoices,
    required this.startMonth,
    this.invoice,
    this.payment,
    this.today,
  });

  /// The hostel's invoices (those with a pending amount are offered).
  final List<Invoice> invoices;
  final int startMonth;

  /// The invoice to pay, when opened from the Invoices screen.
  final Invoice? invoice;

  /// The payment to correct, or null to record a new one.
  final Payment? payment;
  final DateTime? today;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late final Payment? _p = widget.payment;
  late DateTime _date = _p?.paymentDate ?? _today;
  late String _method = _p?.paymentMethod ?? PaymentMethod.cash;
  late final _amount = TextEditingController(
    text: _p?.amount.toStringAsFixed(2),
  );
  late final _reference = TextEditingController(text: _p?.reference);
  late final _remarks = TextEditingController(text: _p?.remarks);
  final _reason = TextEditingController();
  Invoice? _invoice;
  String _message = '';
  bool _busy = false;

  bool get _isEdit => _p != null;

  List<Invoice> get _pending =>
      BillingService.invoicesWithPending(widget.invoices);

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _invoice = widget.invoices
          .where((i) => i.invoiceId == _p!.invoiceId)
          .firstOrNull;
    } else if (widget.invoice != null) {
      _chooseInvoice(widget.invoice);
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _reference, _remarks, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Shows the invoice's amounts and suggests paying the full pending amount.
  void _chooseInvoice(Invoice? i) {
    _invoice = i;
    if (i != null) _amount.text = i.pendingAmount.toStringAsFixed(2);
  }

  String _year(int y) => AcademicYear.label(y, widget.startMonth);

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      if (_isEdit) {
        await BillingService.editPayment(
          payment: _p!,
          date: _date,
          today: _today,
          amountText: _amount.text,
          method: _method,
          reference: _reference.text,
          remarks: _remarks.text,
          reason: _reason.text,
        );
        if (mounted) {
          Navigator.of(context).pop('Payment ${_p.receiptNumber} saved.');
        }
      } else {
        final receipt = await BillingService.recordPayment(
          invoice: _invoice,
          date: _date,
          today: _today,
          amountText: _amount.text,
          method: _method,
          reference: _reference.text,
          remarks: _remarks.text,
        );
        if (mounted) {
          Navigator.of(context).pop('Payment recorded: receipt $receipt.');
        }
      }
    } on ValidationException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('The payment could not be saved. $e');
    }
  }

  void _show(String m) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = m;
    });
  }

  Widget _info(String label, String value, {Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value, key: key),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final i = _invoice;
    final refName = PaymentMethod.referenceName(_method);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Payment' : 'Record Payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isEdit) ...[
              _info('Receipt', '${_p!.receiptNumber}   ${_p.studentName}'),
              _info('Invoice', _p.invoiceNumber),
            ] else
              FormDropdown<int>(
                key: const Key('payInvoice'),
                label: 'Invoice',
                required: true,
                value: i?.invoiceId,
                enabled: !_busy,
                items: [
                  for (final inv in _pending)
                    DropdownMenuItem(
                      value: inv.invoiceId,
                      child: Text(
                        '${inv.studentName}  ·  ${inv.invoiceNumber}  '
                        '(pending ${Money.format(inv.pendingAmount)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(
                  () => _chooseInvoice(
                    _pending.where((x) => x.invoiceId == id).firstOrNull,
                  ),
                ),
              ),
            if (i != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Fee ${_year(i.academicYear)}:  total '
                  '${Money.format(i.totalAmount)},  paid '
                  '${Money.format(i.paidAmount)},  pending '
                  '${Money.format(i.pendingAmount)}',
                  key: const Key('payInvoiceInfo'),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            DateField(
              key: const Key('payDate'),
              label: 'Payment date',
              value: _date,
              required: true,
              enabled: !_busy,
              firstDate: DateTime(2000),
              lastDate: _today,
              onChanged: (d) => setState(() => _date = d ?? _date),
            ),
            FormTextField(
              key: const Key('payAmount'),
              label: 'Amount',
              controller: _amount,
              maxLength: 15,
              required: true,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              enabled: !_busy,
            ),
            FormDropdown<String>(
              key: const Key('payMethod'),
              label: 'Paid by',
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
              key: const Key('payReference'),
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
              key: const Key('payRemarks'),
              label: 'Remarks',
              controller: _remarks,
              maxLength: 255,
              maxLines: 2,
              keyboard: TextInputType.multiline,
              enabled: !_busy,
            ),
            if (_isEdit)
              FormTextField(
                key: const Key('payReason'),
                label: 'Reason for change (for example: wrong amount typed)',
                controller: _reason,
                maxLength: 255,
                keyboard: TextInputType.text,
                enabled: !_busy,
              ),
            FormMessage(_message, key: const Key('payMessage')),
            SaveButton(
              key: const Key('savePayment'),
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
