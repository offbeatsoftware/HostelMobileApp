import 'package:flutter/material.dart';

import '../data/email_settings_repository.dart';
import '../models/email_settings.dart';
import '../services/date_format.dart';
import '../services/email_sender.dart';
import '../services/email_settings_service.dart';
import '../services/message_text.dart';
import '../services/payment_qr_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

const _danger = Color(0xFFC0392B);
const _success = Color(0xFF198754);

/// Email Settings (the desktop screen): the Gmail account, the WhatsApp
/// texts, the four editable email texts and the history of messages sent.
///
/// The Gmail app password and the WhatsApp API settings stay on the desktop,
/// and emails are not sent from the phone yet.
class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _Template {
  _Template(this.type, this.title, this.defaults);

  final String type;
  final String title;
  final EmailTemplate defaults;
  final subject = TextEditingController();
  final body = TextEditingController();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this)
    ..addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {});
      if (_tabs.index == 6 && _history == null) _loadHistory();
    });

  late final Future<EmailSettings> _settings = _load();
  final _senderEmail = TextEditingController();
  final _senderName = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _password = TextEditingController();
  final _testTo = TextEditingController();
  bool _passwordSaved = false;
  final _whatsAppFee = TextEditingController();
  final _whatsAppAttendance = TextEditingController();
  final _templates = [
    _Template(
      EmailType.invoice,
      'Invoice email',
      EmailSettingsService.defaultInvoice,
    ),
    _Template(
      EmailType.receipt,
      'Receipt email',
      EmailSettingsService.defaultReceipt,
    ),
    _Template(
      EmailType.dueReminder,
      'Fee reminder email',
      EmailSettingsService.defaultReminder,
    ),
    _Template(
      EmailType.absence,
      'Attendance email',
      EmailSettingsService.defaultAbsence,
    ),
  ];

  PaymentQr? _qr;
  String _qrProblem = '';
  bool _qrBusy = false;
  String _message = '';
  bool _messageOk = false;
  bool _saving = false;
  Future<List<EmailHistoryEntry>>? _history;

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _senderEmail,
      _senderName,
      _host,
      _port,
      _password,
      _testTo,
      _whatsAppFee,
      _whatsAppAttendance,
    ]) {
      c.dispose();
    }
    for (final t in _templates) {
      t.subject.dispose();
      t.body.dispose();
    }
    super.dispose();
  }

  Future<EmailSettings> _load() async {
    final s = await EmailSettingsService.get();
    _senderEmail.text = s.senderEmail;
    _senderName.text = s.senderName;
    _host.text = s.smtpHost;
    _port.text = '${s.smtpPort}';
    _whatsAppFee.text = s.whatsAppFeeText;
    _whatsAppAttendance.text = s.whatsAppAttendanceText;
    _passwordSaved = await EmailSender.isConfigured();
    try {
      _qr = await PaymentQrService.get();
    } catch (_) {
      // Without the storage script (014) there is no QR image to show.
      _qr = null;
      _qrProblem =
          'The payment QR image could not be loaded. Run '
          'supabase/014_payment_qr_storage.sql first.';
    }
    final saved = [s.invoice, s.receipt, s.reminder, s.absence];
    for (var i = 0; i < _templates.length; i++) {
      _templates[i].subject.text = saved[i].subject;
      _templates[i].body.text = saved[i].body;
    }
    return s;
  }

  void _loadHistory() {
    final next = EmailSettingsRepository.instance.getHistory();
    // The error is shown by the list; this only stops it being reported twice.
    next.ignore();
    setState(() {
      _history = next;
    });
  }

  Future<void> _run(Future<String> Function() save, String failure) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      final done = await save();
      if (!mounted) return;
      setState(() {
        _messageOk = true;
        _message = done;
      });
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _messageOk = false;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) showToast(context, '$failure $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves the Gmail account and texts, and the app password when one was
  /// typed (it is kept encrypted in Supabase and never shown again).
  Future<void> _saveAll() async {
    await EmailSettingsService.saveEmail(
      senderEmail: _senderEmail.text,
      senderName: _senderName.text,
      smtpHost: _host.text,
      port: _port.text,
      invoice: _read(0),
      receipt: _read(1),
      reminder: _read(2),
      absence: _read(3),
    );
    if (_password.text.trim().isNotEmpty) {
      await EmailSender.savePassword(_password.text);
      _password.clear();
      if (mounted) setState(() => _passwordSaved = true);
    }
  }

  Future<void> _saveEmail() => _run(() async {
    await _saveAll();
    return 'Saved.';
  }, 'The email settings could not be saved.');

  /// Saves, then sends a test email to the address typed (or to the Gmail
  /// address itself).
  Future<void> _sendTest() => _run(() async {
    await _saveAll();
    if (!_passwordSaved) {
      throw const ValidationException('Please enter the Gmail app password.');
    }
    final to = Validators.clean(_testTo.text);
    await EmailSender.sendTest(to);
    final where = to.isEmpty ? Validators.clean(_senderEmail.text) : to;
    return 'Test email sent to $where. Check its inbox.';
  }, 'The test email could not be sent.');

  Future<void> _saveWhatsApp() => _run(() async {
    await EmailSettingsService.saveWhatsApp(
      feeText: _whatsAppFee.text,
      attendanceText: _whatsAppAttendance.text,
    );
    return 'Saved.';
  }, 'The WhatsApp settings could not be saved.');

  Future<void> _chooseQr() async {
    if (_qrBusy) return;
    setState(() {
      _qrBusy = true;
      _message = '';
    });
    try {
      final picked = await PaymentQrService.pick();
      if (picked == null) return;
      final saved = await PaymentQrService.save(picked.name, picked.bytes);
      if (!mounted) return;
      setState(() {
        _qr = saved;
        _qrProblem = '';
        _messageOk = true;
        _message = 'The payment QR image was saved.';
      });
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _messageOk = false;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) showToast(context, 'The QR image could not be saved. $e');
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  Future<void> _removeQr() async {
    if (_qrBusy) return;
    setState(() {
      _qrBusy = true;
      _message = '';
    });
    try {
      await PaymentQrService.remove();
      if (!mounted) return;
      setState(() {
        _qr = null;
        _messageOk = true;
        _message = 'The payment QR image was removed.';
      });
    } catch (e) {
      if (mounted) showToast(context, 'The QR image could not be removed. $e');
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  Widget _qrSection() => Column(
    key: const Key('qrSection'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Payment QR image',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      if (_qr != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.memory(
              _qr!.bytes,
              key: const Key('qrPreview'),
              width: 96,
              height: 96,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(_qr!.name)),
          ],
        )
      else
        const Text('None', key: Key('qrNone')),
      if (_qrProblem.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _qrProblem,
            key: const Key('qrProblem'),
            style: const TextStyle(color: _danger),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            key: const Key('chooseQr'),
            onPressed: _qrBusy ? null : _chooseQr,
            child: const Text('Choose QR...'),
          ),
          OutlinedButton(
            key: const Key('removeQr'),
            onPressed: _qrBusy || _qr == null ? null : _removeQr,
            child: const Text('Remove'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _note(
        'Saved at once, without the Save button. The Fee Reminders screen '
        'then offers to send this image after the reminder text, because a '
        'WhatsApp chat link can only carry text.',
      ),
    ],
  );

  EmailTemplate _read(int i) =>
      EmailTemplate(_templates[i].subject.text, _templates[i].body.text);

  @override
  Widget build(BuildContext context) {
    final onWhatsApp = _tabs.index == 1;
    final onHistory = _tabs.index == 6;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Settings'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: 'Gmail account'),
            const Tab(text: 'WhatsApp'),
            for (final t in _templates) Tab(text: t.title),
            const Tab(text: 'Email history'),
          ],
        ),
      ),
      body: FutureBuilder<EmailSettings>(
        future: _settings,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return InfoView(
              key: const Key('emailSettingsError'),
              icon: Icons.cloud_off,
              text:
                  'The email settings could not be loaded.\n'
                  '${snapshot.error}\n\n'
                  'Close this screen and open it again to try again.',
            );
          }
          return Column(
            children: [
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _gmailTab(),
                    _whatsAppTab(),
                    for (var i = 0; i < _templates.length; i++) _templateTab(i),
                    _historyTab(),
                  ],
                ),
              ),
              if (!onHistory)
                Material(
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_message.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _message,
                              key: const Key('emailMessage'),
                              style: TextStyle(
                                color: _messageOk ? _success : _danger,
                              ),
                            ),
                          ),
                        // The WhatsApp tab has its own Save, as on the
                        // desktop; this one saves the Gmail account and the
                        // email texts.
                        if (onWhatsApp)
                          _button(
                            const Key('saveWhatsApp'),
                            'Save WhatsApp Texts',
                            _saveWhatsApp,
                          )
                        else
                          _button(const Key('saveEmail'), 'Save', _saveEmail),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _button(Key key, String text, Future<void> Function() onPressed) =>
      SizedBox(
        height: 48,
        child: FilledButton(
          key: key,
          style: FilledButton.styleFrom(backgroundColor: AppColors.terracotta),
          onPressed: _saving ? null : onPressed,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
  );

  Widget _gmailTab() => ListView(
    key: const Key('gmailTab'),
    padding: const EdgeInsets.all(16),
    children: [
      FormTextField(
        key: const Key('senderEmail'),
        label: 'Gmail address',
        controller: _senderEmail,
        maxLength: 150,
        required: true,
        keyboard: TextInputType.emailAddress,
      ),
      FormTextField(
        key: const Key('senderName'),
        label: 'Sender name',
        controller: _senderName,
        maxLength: 100,
      ),
      FormTextField(
        key: const Key('smtpHost'),
        label: 'SMTP server',
        controller: _host,
        maxLength: 100,
        required: true,
      ),
      FormTextField(
        key: const Key('smtpPort'),
        label: 'Port',
        controller: _port,
        maxLength: 5,
        required: true,
        keyboard: TextInputType.number,
      ),
      FormTextField(
        key: const Key('appPassword'),
        label: _passwordSaved
            ? 'App password (saved; type a new one to replace it)'
            : 'App password',
        controller: _password,
        maxLength: 100,
        obscure: true,
      ),
      _note(
        'Gmail needs an app password, not the normal password:\n'
        '1. Sign in to the Gmail account and turn on 2-Step Verification '
        '(Google Account > Security).\n'
        '2. Open myaccount.google.com/apppasswords, create an app password '
        'named "Hostel Management".\n'
        '3. Copy the 16 letters here and click Save, then Send Test Email.',
      ),
      _note(
        'The password is kept encrypted in Supabase and is never shown '
        'again; leave the box empty to keep it. It is separate from the '
        'desktop program\'s own copy. The phone connects to Gmail on port '
        '465 (Supabase blocks port 587) with the same account. Emails are '
        'sent through the send-email function (see the README). The sender '
        'name is empty to use Shri Balaji Hostel.',
      ),
      FormTextField(
        key: const Key('testTo'),
        label: 'Send test to (empty: the Gmail address above)',
        controller: _testTo,
        maxLength: 150,
        keyboard: TextInputType.emailAddress,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const Key('sendTest'),
          onPressed: _saving ? null : _sendTest,
          child: const Text('Send Test Email'),
        ),
      ),
    ],
  );

  Widget _whatsAppTab() => ListView(
    key: const Key('whatsAppTab'),
    padding: const EdgeInsets.all(16),
    children: [
      FormTextField(
        key: const Key('whatsAppFeeText'),
        label: 'Fee reminder message',
        controller: _whatsAppFee,
        maxLength: 1500,
        required: true,
        maxLines: 12,
        keyboard: TextInputType.multiline,
      ),
      FormTextField(
        key: const Key('whatsAppAttendanceText'),
        label: 'Attendance message',
        controller: _whatsAppAttendance,
        maxLength: 1500,
        required: true,
        maxLines: 6,
        keyboard: TextInputType.multiline,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const Key('restoreWhatsApp'),
          onPressed: () {
            _whatsAppFee.text = MessageText.defaultFeeText;
            _whatsAppAttendance.text = MessageText.defaultAttendanceText;
          },
          child: const Text('Restore Default Texts'),
        ),
      ),
      const SizedBox(height: 12),
      _qrSection(),
      const SizedBox(height: 12),
      _note(
        'Fields filled in for each parent: fee reminder '
        '${EmailSettingsService.whatsAppFeeFields.map((f) => '{$f}').join(' ')}'
        '; attendance '
        '${EmailSettingsService.whatsAppAttendanceFields.map((f) => '{$f}').join(' ')}.'
        '\nThe Fee Reminders and Attendance screens open each parent\'s chat '
        'in WhatsApp with this text; you press Send. Meta\'s WhatsApp API and '
        'the desktop\'s own copy of the QR image are set on the desktop.',
      ),
    ],
  );

  Widget _templateTab(int i) {
    final t = _templates[i];
    return ListView(
      key: Key('template_${t.type}'),
      padding: const EdgeInsets.all(16),
      children: [
        FormTextField(
          key: Key('subject_${t.type}'),
          label: 'Subject',
          controller: t.subject,
          maxLength: 255,
          required: true,
        ),
        FormTextField(
          key: Key('body_${t.type}'),
          label: 'Message',
          controller: t.body,
          maxLength: 4000,
          required: true,
          maxLines: 14,
          keyboard: TextInputType.multiline,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: Key('restore_${t.type}'),
            onPressed: () {
              t.subject.text = t.defaults.subject;
              t.body.text = t.defaults.body;
            },
            child: const Text('Restore Default'),
          ),
        ),
        const SizedBox(height: 12),
        _note(
          'Fields filled in when the email is sent: '
          '${EmailSettingsService.fields[t.type]!.map((f) => '{$f}').join('  ')}',
        ),
      ],
    );
  }

  Widget _historyTab() {
    final history = _history;
    if (history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async {
        final next = EmailSettingsRepository.instance.getHistory();
        setState(() {
          _history = next;
        });
        try {
          await next;
        } catch (_) {
          // Shown below.
        }
      },
      child: FutureBuilder<List<EmailHistoryEntry>>(
        future: history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return InfoView(
              key: const Key('historyError'),
              icon: Icons.cloud_off,
              text:
                  'The email history could not be loaded.\n${snapshot.error}'
                  '\n\nPull down to try again.',
            );
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const InfoView(
              key: Key('historyEmpty'),
              icon: Icons.mail_outline,
              text: 'No emails or WhatsApp messages have been sent yet.',
            );
          }
          return ListView.separated(
            key: const Key('historyList'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: rows.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Text(
                  'The latest 500 emails and WhatsApp messages of all '
                  'hostels. Fee reminders list one row per invoice.',
                  style: TextStyle(color: AppColors.textMuted),
                );
              }
              return _historyCard(rows[i - 1]);
            },
          );
        },
      ),
    );
  }

  Widget _historyCard(EmailHistoryEntry e) {
    final d = e.sentDate;
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final color = e.failed ? _danger : AppColors.textPrimary;
    return Card(
      key: Key('history_${e.emailHistoryId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.studentName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  e.status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Text(
              '${e.typeText}'
              '${e.invoiceNumber.isEmpty ? '' : ', ${e.invoiceNumber}'}',
              style: TextStyle(color: color),
            ),
            Text(
              '${formatDate(d)} $time, to ${e.recipientEmail}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            if (e.errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  e.errorMessage,
                  style: const TextStyle(color: _danger, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
