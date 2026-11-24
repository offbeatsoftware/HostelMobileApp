import 'package:flutter/material.dart';

import '../data/allocation_repository.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../services/billing_service.dart';
import '../services/money.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../data/billing_repository.dart';

/// New Year Fees (the desktop NewYearFeesForm): the fee for the academic
/// year for every student in a room who has none, with last year's fee for
/// reference. Closes with a message when fees were created.
class NewYearFeesScreen extends StatefulWidget {
  const NewYearFeesScreen({
    super.key,
    required this.hostel,
    required this.invoices,
    required this.startMonth,
    this.today,
  });

  final Hostel hostel;
  final List<Invoice> invoices;
  final int startMonth;
  final DateTime? today;

  @override
  State<NewYearFeesScreen> createState() => _NewYearFeesScreenState();
}

class _NewYearFeesScreenState extends State<NewYearFeesScreen> {
  late final DateTime _today = widget.today ?? DateTime.now();
  late final int _current = AcademicYear.of(_today, widget.startMonth);
  late int _year = BillingService.defaultNewYear(_today, widget.startMonth);
  late Future<List<NewYearCandidate>> _candidates = _load();
  final _rent = <int, TextEditingController>{};
  final _transport = <int, TextEditingController>{};
  String _message = '';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._rent.values, ..._transport.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<List<NewYearCandidate>> _load() async {
    final current = await AllocationRepository.instance.getForHostel(
      widget.hostel.hostelId,
    );
    return BillingService.newYearCandidates(current, widget.invoices, _year);
  }

  String _label(int year) => AcademicYear.label(year, widget.startMonth);

  TextEditingController _box(Map<int, TextEditingController> map, int id) =>
      map.putIfAbsent(id, TextEditingController.new);

  Future<void> _create(List<NewYearCandidate> candidates) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _message = '');
    try {
      final fees = BillingService.readYearFees(candidates, {
        for (final c in candidates)
          c.studentId: (
            _box(_rent, c.studentId).text,
            _box(_transport, c.studentId).text,
          ),
      });
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            'Create the ${_label(_year)} fee for '
            '${fees.length} student(s)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirmYearFees'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create Fees'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final count = await BillingRepository.instance.createYearFees(
        _year,
        fees,
      );
      if (mounted) {
        Navigator.of(
          context,
        ).pop('Created the ${_label(_year)} fee for $count student(s).');
      }
    } on ValidationException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('The fees could not be created. $e');
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
    return Scaffold(
      appBar: AppBar(title: const Text('New Year Fees')),
      body: FutureBuilder<List<NewYearCandidate>>(
        future: _candidates,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return InfoView(
              icon: Icons.cloud_off,
              text: 'Could not load the students.\n${snapshot.error}',
            );
          }
          final candidates = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormDropdown<int>(
                key: const Key('newYear'),
                label: 'Academic year',
                value: _year,
                enabled: !_busy,
                items: [
                  for (final y in [_current, _current + 1])
                    DropdownMenuItem(value: y, child: Text(_label(y))),
                ],
                onChanged: (y) => setState(() {
                  _year = y ?? _year;
                  _message = '';
                  _candidates = _load();
                }),
              ),
              Text(
                candidates.isEmpty
                    ? 'Every student in a room already has a fee for '
                          '${_label(_year)}.'
                    : '${candidates.length} students without a fee for '
                          '${_label(_year)}. Type the room rent and transport for '
                          'each student staying on. Leave a row empty to skip the '
                          'student.',
                key: const Key('newYearInfo'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              for (final c in candidates)
                Card(
                  key: Key('newYear_${c.studentId}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.studentName}   ·   Room ${c.roomText}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 10),
                          child: Text(
                            c.lastYear == null
                                ? 'No fee last year'
                                : 'Last year: rent '
                                      '${Money.format(c.lastYear!.roomRent)}, transport '
                                      '${Money.format(c.lastYear!.transportAmount)}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: FormTextField(
                                key: Key('newRent_${c.studentId}'),
                                label: 'Room rent / year',
                                controller: _box(_rent, c.studentId),
                                maxLength: 15,
                                keyboard: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                enabled: !_busy,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FormTextField(
                                key: Key('newTransport_${c.studentId}'),
                                label: 'Transport / year',
                                controller: _box(_transport, c.studentId),
                                maxLength: 15,
                                keyboard: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                enabled: !_busy,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              FormMessage(_message, key: const Key('newYearMessage')),
              if (candidates.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const Key('createYearFees'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.terracotta,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: _busy ? null : () => _create(candidates),
                    child: const Text(
                      'Create Fees',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
