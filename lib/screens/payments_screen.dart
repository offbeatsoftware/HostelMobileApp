import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../services/billing_service.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'document_actions.dart';
import 'payment_form_screen.dart';
import 'payment_history_screen.dart';
import 'refunds_screen.dart';

/// Payments (the desktop screen): record payments in any number of
/// instalments, correct or delete them with a reason, and the change history.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _Data {
  const _Data(this.payments, this.invoices, this.startMonth);

  final List<Payment> payments;
  final List<Invoice> invoices;
  final int startMonth;
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _search = TextEditingController();
  String? _method;
  late Future<_Data> _data = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final repo = BillingRepository.instance;
    final id = widget.hostel.hostelId;
    final results = await Future.wait([
      repo.getPayments(id),
      repo.getInvoices(id),
      repo.getAcademicYearStartMonth(),
    ]);
    return _Data(
      results[0] as List<Payment>,
      results[1] as List<Invoice>,
      results[2] as int,
    );
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Future<void> _form(_Data data, [Payment? payment]) async {
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          invoices: data.invoices,
          startMonth: data.startMonth,
          payment: payment,
          today: widget.today,
        ),
      ),
    );
    if (done != null && mounted) {
      showToast(context, done);
      await _reload();
    }
  }

  Future<void> _delete(Payment p) async {
    // The dialog owns its text box, so it is cleaned up only once closed.
    final why = await showDialog<String>(
      context: context,
      builder: (context) => _DeletePaymentDialog(payment: p),
    );
    if (why == null || !mounted) return;
    try {
      await BillingService.deletePayment(p, why);
      if (!mounted) return;
      showToast(context, 'Payment ${p.receiptNumber} deleted.');
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The payment could not be deleted. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Data>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Payments'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.hostel.hostelName,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            actions: [
              IconButton(
                key: const Key('openRefunds'),
                tooltip: 'Refunds',
                icon: const Icon(Icons.currency_exchange),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RefundsScreen(
                        hostel: widget.hostel,
                        today: widget.today,
                      ),
                    ),
                  );
                  // Refunds change what is paid on the fees.
                  if (mounted) await _reload();
                },
              ),
              IconButton(
                key: const Key('changeHistory'),
                tooltip: 'Change history',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentHistoryScreen(
                      changes: BillingRepository.instance.getChanges(
                        widget.hostel.hostelId,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: data == null
              ? null
              : FloatingActionButton.extended(
                  key: const Key('recordPayment'),
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  onPressed: () => _form(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Record'),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('paymentSearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search receipt, invoice or student',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_search.clear),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in [null, ...PaymentMethod.all])
                      ChoiceChip(
                        key: Key('paymentMethod_${m ?? 'All'}'),
                        label: Text(m ?? 'All'),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selected: _method == m,
                        selectedColor: AppColors.terracotta,
                        labelStyle: TextStyle(
                          color: _method == m
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setState(() => _method = m),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: _buildList(snapshot),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(AsyncSnapshot<_Data> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return InfoView(
        key: const Key('paymentsError'),
        icon: Icons.cloud_off,
        text:
            'Could not load the payments.\n${snapshot.error}\n\n'
            'Pull down to try again.',
      );
    }
    final data = snapshot.data!;
    if (data.payments.isEmpty) {
      return const InfoView(
        key: Key('paymentsEmpty'),
        icon: Icons.payments_outlined,
        text: 'No payments yet. Tap "Record" to record the first payment.',
      );
    }
    final shown = BillingService.filterPayments(
      data.payments,
      _search.text,
      _method,
    );
    return ListView.separated(
      key: const Key('paymentsList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: shown.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            BillingService.paymentSummary(shown),
            key: const Key('paymentSummary'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
        }
        final p = shown[i - 1];
        return Card(
          key: Key('payment_${p.paymentId}'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _form(data, p),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.studentName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              Money.format(p.amount),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF198754),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${p.receiptNumber}  ·  ${formatDate(p.paymentDate)}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                        Text(
                          '${p.paymentMethod}'
                          '${p.reference == null ? '' : '  ·  ${p.reference}'}'
                          '  ·  invoice ${p.invoiceNumber}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        if (p.remarks != null)
                          Text(
                            p.remarks!,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  EditDeleteMenu(
                    key: Key('paymentMenu_${p.paymentId}'),
                    onEdit: () => _form(data, p),
                    extra: {
                      'Receipt PDF': () =>
                          DocumentActions.receiptPdf(context, widget.hostel, p),
                      'Email Receipt': () => DocumentActions.receiptEmail(
                        context,
                        widget.hostel,
                        p,
                      ),
                    },
                    onDelete: () => _delete(p),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Asks for the reason before deleting a payment; closes with the reason
/// (possibly empty), or null when cancelled.
class _DeletePaymentDialog extends StatefulWidget {
  const _DeletePaymentDialog({required this.payment});

  final Payment payment;

  @override
  State<_DeletePaymentDialog> createState() => _DeletePaymentDialogState();
}

class _DeletePaymentDialogState extends State<_DeletePaymentDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    return AlertDialog(
      title: const Text('Delete payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete payment ${p.receiptNumber} of '
            '${Money.format(p.amount)} from ${p.studentName}? The pending '
            'amount of invoice ${p.invoiceNumber} goes up again. The '
            'deletion is kept in the change history.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('deleteReason'),
            controller: _reason,
            maxLength: 255,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'For example: entered twice by mistake',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmDelete'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
          onPressed: () => Navigator.of(context).pop(_reason.text),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
