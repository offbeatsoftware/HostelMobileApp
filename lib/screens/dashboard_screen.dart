import 'package:flutter/material.dart';

import '../data/allocation_repository.dart';
import '../data/billing_repository.dart';
import '../data/room_repository.dart';
import '../data/student_repository.dart';
import '../models/allocation.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/refund.dart';
import '../models/room.dart';
import '../models/student.dart';
import '../services/dashboard_service.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/month_bar_chart.dart';

const _danger = Color(0xFFC0392B);
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Dashboard of the selected hostel (the desktop Dashboard): students, beds,
/// fees, money received, pending fees, payments per month and the latest
/// activity.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _data = _load();

  Future<DashboardData> _load() async {
    final id = widget.hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      StudentRepository.instance.getForHostel(id),
      RoomRepository.instance.getForHostel(id),
      billing.getInvoices(id),
      billing.getPayments(id),
      billing.getRefunds(id),
      AllocationRepository.instance.getForHostel(id, includeHistory: true),
      billing.getAcademicYearStartMonth(),
    ]);
    return DashboardService.compute(
      today: widget.today ?? DateTime.now(),
      startMonth: r[6] as int,
      students: r[0] as List<Student>,
      rooms: r[1] as List<Room>,
      invoices: r[2] as List<Invoice>,
      payments: r[3] as List<Payment>,
      refunds: r[4] as List<Refund>,
      allocations: r[5] as List<RoomAllocation>,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
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
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<DashboardData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return InfoView(
                key: const Key('dashboardError'),
                icon: Icons.cloud_off,
                text:
                    'The dashboard could not be loaded.\n${snapshot.error}'
                    '\n\nPull down to try again.',
              );
            }
            return _build(context, snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _build(BuildContext context, DashboardData d) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : 2;
    final month = '${_monthNames[d.asOf.month - 1]} ${d.asOf.year}';
    final since =
        '${d.yearStart.day} ${_monthNames[d.yearStart.month - 1].substring(0, 3)}';
    final tiles = [
      _Tile(
        'Students',
        '${d.activeStudents}',
        'active, ${d.leftStudents} left',
      ),
      _Tile(
        'Beds occupied',
        '${d.occupiedBeds} / ${d.totalBeds}',
        '${d.freeBeds} free',
      ),
      _Tile(
        'Fees',
        Money.formatWhole(d.invoicedThisYear),
        'for ${d.academicYear}',
      ),
      _Tile('Received', Money.formatWhole(d.receivedThisMonth), 'in $month'),
      _Tile(
        'Year to date',
        Money.formatWhole(d.receivedThisYear),
        'received since $since',
      ),
      _Tile(
        'Pending',
        Money.formatWhole(d.pendingAmount),
        '${d.pendingStudents} ${d.pendingStudents == 1 ? 'student' : 'students'}',
        warning: d.pendingAmount > 0,
      ),
    ];

    return ListView(
      key: const Key('dashboard'),
      padding: const EdgeInsets.all(16),
      children: [
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // Tall enough for caption, figure and note at the phone's text
            // size (larger font settings get taller tiles).
            mainAxisExtent: MediaQuery.textScalerOf(context).scale(108),
          ),
          children: [for (final t in tiles) _TileCard(t)],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Payments received per month, academic year ${d.academicYear}',
          child: MonthBarChart(months: d.paymentsPerMonth),
        ),
        _Section(
          title: 'Highest pending fees',
          empty: 'No fees are pending.',
          rows: [
            for (final due in d.highestPending)
              _Row(
                due.studentName,
                Money.formatWhole(due.pendingAmount),
                valueColor: _danger,
              ),
          ],
        ),
        _Section(
          title: 'Latest payments',
          empty: 'No payments yet.',
          rows: [
            for (final p in d.latestPayments)
              _Row(
                '${_short(p.paymentDate)}   ${p.studentName}',
                Money.formatWhole(p.amount),
              ),
          ],
        ),
        _Section(
          title: 'Latest check-ins',
          empty: 'No check-ins yet.',
          rows: [
            for (final a in d.recentCheckIns)
              _Row(
                '${_short(a.checkInDate)}   ${a.studentName}',
                'Room ${a.roomNumber}',
              ),
          ],
        ),
      ],
    );
  }

  /// "05 Jul".
  static String _short(DateTime d) => formatDate(d).substring(0, 6);
}

class _Tile {
  const _Tile(this.caption, this.value, this.note, {this.warning = false});

  final String caption;
  final String value;
  final String note;
  final bool warning;
}

class _TileCard extends StatelessWidget {
  const _TileCard(this.tile);

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('tile_${tile.caption}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (tile.warning) ...[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: _danger,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    tile.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                tile.value,
                key: Key('tileValue_${tile.caption}'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: tile.warning ? _danger : AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              tile.note,
              key: Key('tileNote_${tile.caption}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.child, this.rows, this.empty});

  final String title;
  final Widget? child;
  final List<_Row>? rows;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            if (child != null) child!,
            if (rows != null && rows!.isEmpty)
              Text(
                empty ?? '',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            if (rows != null)
              for (final r in rows!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r.label, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.value,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: r.valueColor ?? AppColors.textPrimary,
                        ),
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
