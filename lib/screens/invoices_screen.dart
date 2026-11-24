import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../services/billing_service.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'fee_edit_screen.dart';
import 'new_year_fees_screen.dart';
import 'payment_form_screen.dart';

const _danger = Color(0xFFC0392B);
const _success = Color(0xFF198754);

/// Invoices (the desktop screen): each student's yearly fee, paid and
/// pending; Record Payment, Edit Fee, Delete and New Year Fees.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _Data {
  const _Data(this.invoices, this.startMonth);

  final List<Invoice> invoices;
  final int startMonth;
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final _search = TextEditingController();
  String? _status;
  int? _year;
  late Future<_Data> _data = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final repo = BillingRepository.instance;
    final results = await Future.wait([
      repo.getInvoices(widget.hostel.hostelId),
      repo.getAcademicYearStartMonth(),
    ]);
    return _Data(results[0] as List<Invoice>, results[1] as int);
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

  Future<void> _push(Widget screen) async {
    final result = await Navigator.of(
      context,
    ).push<Object>(MaterialPageRoute(builder: (_) => screen));
    if (result != null && mounted) {
      if (result is String) showToast(context, result);
      if (result == true) showToast(context, 'Fee saved.');
      await _reload();
    }
  }

  Future<void> _delete(Invoice i) async {
    if (!await confirmDelete(
          context,
          'Delete invoice',
          'Delete invoice ${i.invoiceNumber} for ${i.studentName}?',
        ) ||
        !mounted) {
      return;
    }
    try {
      await BillingService.deleteInvoice(i);
      if (!mounted) return;
      showToast(context, 'Invoice deleted.');
      await _reload();
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The invoice could not be deleted. $e');
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
            title: const Text('Invoices'),
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
                  key: const Key('newYearFees'),
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  onPressed: () => _push(
                    NewYearFeesScreen(
                      hostel: widget.hostel,
                      invoices: data.invoices,
                      startMonth: data.startMonth,
                      today: widget.today,
                    ),
                  ),
                  icon: const Icon(Icons.event_repeat),
                  label: const Text('New Year Fees'),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('invoiceSearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search invoice no. or student',
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
              if (data != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final s in [null, ...InvoiceStatus.all])
                        ChoiceChip(
                          key: Key('invoiceStatus_${s ?? 'All'}'),
                          label: Text(s ?? 'All'),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          selected: _status == s,
                          selectedColor: AppColors.terracotta,
                          labelStyle: TextStyle(
                            color: _status == s
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                          onSelected: (_) => setState(() => _status = s),
                        ),
                      DropdownButton<int?>(
                        key: const Key('invoiceYear'),
                        value: _year,
                        underline: const SizedBox.shrink(),
                        hint: const Text('All years'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All years'),
                          ),
                          for (final y in BillingService.years(data.invoices))
                            DropdownMenuItem<int?>(
                              value: y,
                              child: Text(
                                AcademicYear.label(y, data.startMonth),
                              ),
                            ),
                        ],
                        onChanged: (y) => setState(() => _year = y),
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
        key: const Key('invoicesError'),
        icon: Icons.cloud_off,
        text:
            'Could not load the invoices.\n${snapshot.error}\n\n'
            'Pull down to try again.',
      );
    }
    final data = snapshot.data!;
    if (data.invoices.isEmpty) {
      return const InfoView(
        key: Key('invoicesEmpty'),
        icon: Icons.receipt_long_outlined,
        text:
            'No invoices yet. A fee is entered when a student is checked '
            'in on Room Allocation, or with New Year Fees.',
      );
    }
    final shown = BillingService.filterInvoices(
      data.invoices,
      _search.text,
      _status,
      _year,
    );
    return ListView.separated(
      key: const Key('invoicesList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: shown.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            BillingService.invoiceSummary(shown),
            key: const Key('invoiceSummary'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
        }
        final inv = shown[i - 1];
        final yearText = AcademicYear.label(inv.academicYear, data.startMonth);
        return _InvoiceCard(
          invoice: inv,
          yearText: yearText,
          onPay: () => _push(
            PaymentFormScreen(
              invoices: data.invoices,
              startMonth: data.startMonth,
              invoice: inv,
              today: widget.today,
            ),
          ),
          onEditFee: () =>
              _push(FeeEditScreen(invoice: inv, yearText: yearText)),
          onDelete: () => _delete(inv),
        );
      },
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.yearText,
    required this.onPay,
    required this.onEditFee,
    required this.onDelete,
  });

  final Invoice invoice;
  final String yearText;
  final VoidCallback onPay;
  final VoidCallback onEditFee;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final colour = switch (i.status) {
      InvoiceStatus.paid => _success,
      InvoiceStatus.unpaid => _danger,
      _ => AppColors.terracotta,
    };
    Widget amount(String label, double value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          Text(
            Money.format(value),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    return Card(
      key: Key('invoice_${i.invoiceId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: i.pendingAmount > 0 ? onPay : onEditFee,
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
                            i.studentName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          key: Key('invoiceStatusChip_${i.invoiceId}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colour,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            i.status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${i.invoiceNumber}  ·  $yearText',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        amount('Total fee', i.totalAmount),
                        amount('Paid', i.paidAmount),
                        amount(
                          'Pending',
                          i.pendingAmount,
                          color: i.pendingAmount > 0 ? _danger : _success,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('invoiceMenu_${i.invoiceId}'),
                tooltip: 'More',
                onSelected: (v) => switch (v) {
                  'pay' => onPay(),
                  'fee' => onEditFee(),
                  _ => onDelete(),
                },
                itemBuilder: (_) => [
                  if (i.pendingAmount > 0)
                    const PopupMenuItem(
                      value: 'pay',
                      child: Text('Record Payment'),
                    ),
                  const PopupMenuItem(value: 'fee', child: Text('Edit Fee')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
