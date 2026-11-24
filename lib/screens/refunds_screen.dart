import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/refund.dart';
import '../services/billing_service.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'document_actions.dart';
import 'refund_form_screen.dart';

const _danger = Color(0xFFC0392B);

/// Refunds (the desktop Refunds window): all refunds of the hostel, newest
/// first; pay money back, and delete a refund entered by mistake.
class RefundsScreen extends StatefulWidget {
  const RefundsScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<RefundsScreen> createState() => _RefundsScreenState();
}

class _Data {
  const _Data(this.refunds, this.invoices, this.startMonth);

  final List<Refund> refunds;
  final List<Invoice> invoices;
  final int startMonth;
}

class _RefundsScreenState extends State<RefundsScreen> {
  final _search = TextEditingController();
  late Future<_Data> _data = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final repo = BillingRepository.instance;
    final id = widget.hostel.hostelId;
    final r = await Future.wait([
      repo.getRefunds(id),
      repo.getInvoices(id),
      repo.getAcademicYearStartMonth(),
    ]);
    return _Data(r[0] as List<Refund>, r[1] as List<Invoice>, r[2] as int);
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

  Future<void> _refund(_Data data) async {
    if (BillingService.refundableInvoices(data.invoices).isEmpty) {
      showToast(
        context,
        'Nothing has been paid (after refunds), so there is nothing to refund.',
      );
      return;
    }
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RefundFormScreen(
          invoices: data.invoices,
          startMonth: data.startMonth,
          today: widget.today,
        ),
      ),
    );
    if (done != null && mounted) {
      showToast(context, done);
      await _reload();
    }
  }

  Future<void> _delete(Refund r) async {
    final why = await showDialog<String>(
      context: context,
      builder: (context) => _DeleteRefundDialog(refund: r),
    );
    if (why == null || !mounted) return;
    try {
      await BillingService.deleteRefund(r, why);
      if (!mounted) return;
      showToast(context, 'Refund ${r.refundNumber} deleted.');
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The refund could not be deleted. $e');
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
            title: const Text('Refunds'),
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
          ),
          floatingActionButton: data == null
              ? null
              : FloatingActionButton.extended(
                  key: const Key('newRefund'),
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  onPressed: () => _refund(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Refund'),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('refundSearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search refund, invoice, student or reason',
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
        key: const Key('refundsError'),
        icon: Icons.cloud_off,
        text:
            'Could not load the refunds.\n${snapshot.error}\n\n'
            'Pull down to try again.',
      );
    }
    final data = snapshot.data!;
    if (data.refunds.isEmpty) {
      return const InfoView(
        key: Key('refundsEmpty'),
        icon: Icons.currency_exchange,
        text: 'No refunds yet. Tap "Refund" to pay money back.',
      );
    }
    final shown = BillingService.filterRefunds(data.refunds, _search.text);
    return ListView.separated(
      key: const Key('refundsList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: shown.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            BillingService.refundSummary(shown),
            key: const Key('refundSummary'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
        }
        return _card(shown[i - 1]);
      },
    );
  }

  Widget _card(Refund r) => Card(
    key: Key('refund_${r.refundId}'),
    margin: EdgeInsets.zero,
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
                        r.studentName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      Money.format(r.amount),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _danger,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${r.refundNumber}  ·  ${formatDate(r.refundDate)}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                Text(
                  '${r.refundMethod}'
                  '${r.reference == null ? '' : '  ·  ${r.reference}'}'
                  '  ·  invoice ${r.invoiceNumber}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                if (r.reason.isNotEmpty)
                  Text(
                    r.reason,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: Key('refundMenu_${r.refundId}'),
            tooltip: 'More',
            onSelected: (v) => switch (v) {
              'pdf' => DocumentActions.refundPdf(context, widget.hostel, r),
              'email' => DocumentActions.refundEmail(context, widget.hostel, r),
              _ => _delete(r),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Receipt PDF')),
              PopupMenuItem(value: 'email', child: Text('Email Receipt')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Asks for the reason before deleting a refund (required); closes with the
/// reason, or null when cancelled.
class _DeleteRefundDialog extends StatefulWidget {
  const _DeleteRefundDialog({required this.refund});

  final Refund refund;

  @override
  State<_DeleteRefundDialog> createState() => _DeleteRefundDialogState();
}

class _DeleteRefundDialogState extends State<_DeleteRefundDialog> {
  final _reason = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _delete() {
    if (_reason.text.trim().isEmpty) {
      setState(() {
        _error =
            'Please enter the reason, for example "entered twice by mistake".';
      });
      return;
    }
    Navigator.of(context).pop(_reason.text);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.refund;
    return AlertDialog(
      title: const Text('Delete refund'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete refund ${r.refundNumber} of ${Money.format(r.amount)} to '
            '${r.studentName}? Use this only for a refund entered by '
            'mistake. The fee and the paid amount go back up, and the '
            'deletion is kept in the change history.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('deleteRefundReason'),
            controller: _reason,
            maxLength: 255,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'For example: entered twice by mistake',
              counterText: '',
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error, style: const TextStyle(color: _danger)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmDeleteRefund'),
          style: TextButton.styleFrom(foregroundColor: _danger),
          onPressed: _delete,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
