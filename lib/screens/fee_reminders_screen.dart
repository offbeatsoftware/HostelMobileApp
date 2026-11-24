import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../data/reminder_repository.dart';
import '../data/settings_repository.dart';
import '../data/student_repository.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/student.dart';
import '../services/attendance_service.dart';
import '../services/date_format.dart';
import '../services/fee_reminder_service.dart';
import '../services/launcher.dart';
import '../services/message_text.dart';
import '../services/document_email.dart';
import '../services/document_share.dart';
import '../services/money.dart';
import '../services/payment_qr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'document_actions.dart';
import 'payment_form_screen.dart';

const _danger = Color(0xFFC0392B);
const _success = Color(0xFF198754);

/// Fee Reminders (the desktop screen): every student with a pending fee,
/// highest first; send the parent a WhatsApp reminder or record a payment.
class FeeRemindersScreen extends StatefulWidget {
  const FeeRemindersScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<FeeRemindersScreen> createState() => _FeeRemindersScreenState();
}

class _Data {
  const _Data(
    this.dues,
    this.invoices,
    this.startMonth,
    this.template,
    this.adminPhone,
    this.qr,
    this.students,
  );

  final List<FeeDue> dues;
  final List<Invoice> invoices;
  final int startMonth;
  final String template;
  final String? adminPhone;

  /// The payment QR image, when one is saved (Email Settings).
  final PaymentQr? qr;
  final List<Student> students;
}

class _FeeRemindersScreenState extends State<FeeRemindersScreen> {
  final _search = TextEditingController();
  late Future<_Data> _data = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final id = widget.hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      billing.getInvoices(id),
      StudentRepository.instance.getForHostel(id),
      ReminderRepository.instance.getLastReminders(id),
      billing.getAcademicYearStartMonth(),
      SettingsRepository.instance.getWhatsAppTexts(),
      SettingsRepository.instance.getAdminPhone(),
    ]);
    final invoices = r[0] as List<Invoice>;
    final students = r[1] as List<Student>;
    PaymentQr? qr;
    try {
      qr = await PaymentQrService.get();
    } catch (_) {
      // Reminders work without a QR image (or before script 014 is run).
    }
    return _Data(
      FeeReminderService.dues(
        invoices: invoices,
        students: students,
        lastReminders: r[2] as Map<int, DateTime>,
      ),
      invoices,
      r[3] as int,
      (r[4] as Map<String, String>)[MessageText.feeKey] ??
          MessageText.defaultFeeText,
      r[5] as String?,
      qr,
      students,
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

  Future<void> _send(_Data data, FeeDue due) async {
    final text = FeeReminderService.message(
      due: due,
      hostelName: widget.hostel.hostelName,
      startMonth: data.startMonth,
      hostelPhone: widget.hostel.phone,
      adminPhone: data.adminPhone,
      template: data.template,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reminder to ${due.parentRelation!.toLowerCase()}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${due.parentName}, +${due.parentMobile}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F6E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(text, key: const Key('reminderPreview')),
              ),
              if (data.qr != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A chat link can only carry the text. After sending '
                        'it, send the payment QR image to the same parent.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        key: const Key('sendQr'),
                        onPressed: () =>
                            DocumentShare.image(data.qr!.bytes, data.qr!.name),
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('Send QR Image'),
                      ),
                    ],
                  ),
                ),
              if (due.lastReminder != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Last reminder: ${formatDate(due.lastReminder!)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('openWhatsApp'),
            style: FilledButton.styleFrom(backgroundColor: _success),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.chat, size: 18),
            label: const Text('Open WhatsApp'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final opened = await Launcher.open(
      AttendanceService.whatsAppLink(due.parentMobile!, text),
    );
    if (!mounted) return;
    if (!opened) {
      showToast(context, 'WhatsApp could not be opened on this phone.');
      return;
    }
    try {
      await ReminderRepository.instance.logFeeReminder(
        due.studentId,
        due.parentMobile!,
        [for (final i in due.invoices) i.invoiceId],
      );
      if (!mounted) return;
      showToast(context, 'Reminder recorded for ${due.studentName}.');
      await _reload();
    } catch (e) {
      if (mounted) showToast(context, 'The reminder was not recorded. $e');
    }
  }

  Future<void> _pay(_Data data, FeeDue due) async {
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          invoices: data.invoices,
          startMonth: data.startMonth,
          // The oldest year first, as fees are usually paid.
          invoice: due.invoices.first,
          today: widget.today,
        ),
      ),
    );
    if (done != null && mounted) {
      showToast(context, done);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Reminders'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const Key('reminderSearch'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search student, room or father',
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
              child: FutureBuilder<_Data>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return InfoView(
                      key: const Key('remindersError'),
                      icon: Icons.cloud_off,
                      text:
                          'The pending fees could not be loaded.\n'
                          '${snapshot.error}\n\nPull down to try again.',
                    );
                  }
                  final data = snapshot.data!;
                  if (data.dues.isEmpty) {
                    return const InfoView(
                      key: Key('remindersEmpty'),
                      icon: Icons.verified_outlined,
                      text: 'No fees are pending. Nothing to remind.',
                    );
                  }
                  final shown = FeeReminderService.search(
                    data.dues,
                    _search.text,
                  );
                  return ListView.separated(
                    key: const Key('remindersList'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: shown.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Text(
                          FeeReminderService.summary(data.dues),
                          key: const Key('reminderSummary'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        );
                      }
                      return _card(data, shown[i - 1]);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  EmailContact? _emailContact(_Data data, FeeDue d) {
    final s = data.students.where((x) => x.studentId == d.studentId);
    return s.isEmpty ? null : DocumentEmail.feeContact(s.first);
  }

  Widget _card(_Data data, FeeDue d) {
    Widget amount(String label, double v, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          Text(
            Money.formatExact(v),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    return Card(
      key: Key('due_${d.studentId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.studentName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (d.roomNumber != null)
                  Text(
                    'Room ${d.roomNumber}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
              ],
            ),
            Text(
              FeeReminderService.years(d, data.startMonth),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                amount('Total fee', d.totalAmount),
                amount('Paid', d.paidAmount),
                amount('Pending', d.pendingAmount, color: _danger),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              d.parentMobile == null
                  ? 'Neither the father nor the mother has a valid mobile number.'
                  : '${d.parentRelation}: ${d.parentName}, +${d.parentMobile}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            Text(
              d.lastReminder == null
                  ? 'No reminder sent yet'
                  : 'Last reminder: ${formatDate(d.lastReminder!)}',
              key: Key('lastReminder_${d.studentId}'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            // Full width, so the buttons line up on the right.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: Key('pay_${d.studentId}'),
                    onPressed: () => _pay(data, d),
                    child: const Text('Record Payment'),
                  ),
                  if (_emailContact(data, d) != null)
                    OutlinedButton.icon(
                      key: Key('email_${d.studentId}'),
                      onPressed: () => DocumentActions.reminderEmail(
                        context,
                        widget.hostel,
                        d,
                      ),
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: const Text('Email'),
                    ),
                  if (d.parentMobile != null)
                    FilledButton.icon(
                      key: Key('remind_${d.studentId}'),
                      style: FilledButton.styleFrom(backgroundColor: _success),
                      onPressed: () => _send(data, d),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
