import 'package:flutter/material.dart';

import '../services/agreement_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Agreement Text (the desktop AgreementTextForm): edit the agreement
/// wording. {Fields} are filled in for each student; a line starting with
/// "# " is the title and "## " a heading.
class AgreementTextScreen extends StatefulWidget {
  const AgreementTextScreen({super.key});

  @override
  State<AgreementTextScreen> createState() => _AgreementTextScreenState();
}

class _AgreementTextScreenState extends State<AgreementTextScreen> {
  final _text = TextEditingController();
  late final Future<void> _loaded = _load();
  String _message = '';
  bool _ok = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _text.text = await AgreementService.getTemplate();
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await AgreementService.saveTemplate(_text.text);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = 'Saved.';
      });
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'The agreement text could not be saved. \$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agreement Text')),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return InfoView(
              key: const Key('agreementTextError'),
              icon: Icons.cloud_off,
              text:
                  'The agreement text could not be loaded.\n${snapshot.error}',
            );
          }
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Each line is a paragraph. A line starting with "# " is '
                    'the title and "## " a heading. These fields are filled '
                    'in for each student (in bold): '
                    '${AgreementService.fields.map((f) => '{$f}').join('  ')}',
                    key: const Key('agreementHelp'),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: const Key('agreementText'),
                      controller: _text,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _message,
                            key: const Key('agreementMessage'),
                            style: TextStyle(
                              color: _ok
                                  ? const Color(0xFF198754)
                                  : const Color(0xFFC0392B),
                            ),
                          ),
                        ),
                      SaveButton(
                        key: const Key('saveAgreementText'),
                        busy: _busy,
                        onPressed: _save,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('restoreAgreement'),
                        onPressed: _busy
                            ? null
                            : () =>
                                  _text.text = AgreementService.defaultTemplate,
                        child: const Text('Restore Default'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
