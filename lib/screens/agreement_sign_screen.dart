import 'package:flutter/material.dart';

import '../models/agreement.dart';
import '../models/hostel.dart';
import '../models/student.dart';
import '../services/agreement_signature_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/signature_pad.dart';

/// Sign Agreement (the desktop AgreementSignForm): the student, the parent or
/// guardian, the hostel owner and a witness sign on screen. The owner's
/// signature can be kept for the hostel and is then filled in on every
/// agreement. Closes with true after Save and Make PDF, false after Save,
/// and null when left without saving.
class AgreementSignScreen extends StatefulWidget {
  const AgreementSignScreen({
    super.key,
    required this.hostel,
    required this.student,
    this.today,
  });

  final Hostel hostel;
  final Student student;
  final DateTime? today;

  @override
  State<AgreementSignScreen> createState() => _AgreementSignScreenState();
}

class _AgreementSignScreenState extends State<AgreementSignScreen> {
  final _pads = {
    for (final s in AgreementSigner.values) s: SignatureController(),
  };
  final _witnessName = TextEditingController();
  bool _keepOwner = true;
  late final Future<void> _loaded = _load();
  String _message = '';
  bool _busy = false;

  @override
  void dispose() {
    for (final p in _pads.values) {
      p.dispose();
    }
    _witnessName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await AgreementSignatureService.get(
      widget.student.studentId,
      widget.student.hostelId,
    );
    for (final e in _pads.entries) {
      e.value.showSaved(saved.of(e.key));
    }
    _witnessName.text = saved.witnessName;
  }

  Future<void> _save(bool makePdf) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final images = {
        for (final e in _pads.entries) e.key: await e.value.toPng(),
      };
      await AgreementSignatureService.save(
        widget.student.studentId,
        widget.student.hostelId,
        images,
        _witnessName.text,
        widget.today ?? DateTime.now(),
        keepOwnerForHostel: _keepOwner,
      );
      if (mounted) Navigator.of(context).pop(makePdf);
    } on ValidationException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('The signatures could not be saved. $e');
    }
  }

  void _show(String m) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = m;
    });
  }

  Widget _box(AgreementSigner signer, String title, {Widget? extra}) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SignaturePad(
            key: Key('pad_${signer.name}'),
            controller: _pads[signer]!,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton(
                key: Key('clear_${signer.name}'),
                onPressed: _busy ? null : _pads[signer]!.clear,
                child: const Text('Clear'),
              ),
            ],
          ),
          if (extra != null) ...[const SizedBox(height: 8), extra],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final parent = (s.fatherName ?? '').trim().isNotEmpty
        ? s.fatherName!.trim()
        : (s.motherName ?? '').trim();
    return Scaffold(
      appBar: AppBar(title: Text('Sign Agreement: ${s.studentName}')),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return SafeArea(
            child: ListView(
              key: const Key('signView'),
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Each person signs in their box with a finger or pen. '
                    'Clear starts a box again. The signatures are printed on '
                    'the agreement PDF above the names, with today\'s date.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                _box(
                  AgreementSigner.student,
                  'Second Party (Student): ${s.studentName}',
                ),
                _box(
                  AgreementSigner.parent,
                  'Parent / Guardian${parent.isEmpty ? '' : ': $parent'}',
                ),
                _box(
                  AgreementSigner.owner,
                  'First Party (Hostel owner)',
                  extra: CheckboxListTile(
                    key: const Key('keepOwner'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Use for every agreement of this hostel'),
                    value: _keepOwner,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _keepOwner = v ?? true),
                  ),
                ),
                _box(
                  AgreementSigner.witness,
                  'Witness',
                  extra: TextField(
                    key: const Key('witnessName'),
                    controller: _witnessName,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Witness name',
                      counterText: '',
                    ),
                  ),
                ),
                FormMessage(_message, key: const Key('signMessage')),
                SaveButton(
                  key: const Key('saveAndPdf'),
                  busy: _busy,
                  label: 'Save and Make PDF',
                  onPressed: () => _save(true),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('saveSignatures'),
                  onPressed: _busy ? null : () => _save(false),
                  child: const Text('Save without PDF'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
