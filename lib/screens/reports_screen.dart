import 'package:flutter/material.dart';

import '../data/allocation_repository.dart';
import '../data/billing_repository.dart';
import '../data/college_repository.dart';
import '../data/room_repository.dart';
import '../data/student_repository.dart';
import '../models/allocation.dart';
import '../models/college.dart';
import '../models/hostel.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/report_table.dart';
import '../models/room.dart';
import '../models/student.dart';
import '../services/date_format.dart';
import '../services/money.dart';
import '../services/report_export.dart';
import '../services/report_service.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

enum ReportKind {
  students('Students'),
  rooms('Rooms'),
  payments('Payments'),
  fees('Fees'),
  pending('Pending fees');

  const ReportKind(this.label);

  final String label;
}

/// Reports (the desktop Reports screen): student list, room occupancy,
/// payments received, fees and pending fees, with the desktop's filters,
/// subtotals and totals; shared as PDF or Excel (CSV).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.hostel, this.today});

  final Hostel hostel;
  final DateTime? today;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late final Future<ReportData> _data = _load();
  ReportKind _kind = ReportKind.students;

  // Filters, with the desktop's defaults.
  String? _studentStatus = StudentStatus.active;
  int? _collegeId;
  late DateTime _from = DateTime(_today.year, _today.month, 1);
  late DateTime _to = _today;
  String? _method;
  int? _year; // set to this academic year once loaded
  bool _yearChosen = false;
  String? _invoiceStatus;
  bool _sharing = false;

  Future<ReportData> _load() async {
    final id = widget.hostel.hostelId;
    final billing = BillingRepository.instance;
    final r = await Future.wait([
      StudentRepository.instance.getForHostel(id),
      CollegeRepository.instance.getForHostel(id),
      RoomRepository.instance.getForHostel(id),
      AllocationRepository.instance.getForHostel(id),
      billing.getPayments(id),
      billing.getInvoices(id),
      billing.getAcademicYearStartMonth(),
    ]);
    return ReportData(
      students: r[0] as List<Student>,
      colleges: r[1] as List<College>,
      rooms: r[2] as List<Room>,
      allocations: r[3] as List<RoomAllocation>,
      payments: r[4] as List<Payment>,
      invoices: r[5] as List<Invoice>,
      startMonth: r[6] as int,
    );
  }

  DateTime get _now => widget.today == null
      ? DateTime.now()
      : DateTime(_today.year, _today.month, _today.day, 10, 30);

  ReportTable _build(ReportData data) {
    final h = widget.hostel;
    return switch (_kind) {
      ReportKind.students => ReportService.studentList(
        h,
        data,
        _now,
        status: _studentStatus,
        collegeId: _collegeId,
      ),
      ReportKind.rooms => ReportService.roomOccupancy(h, data, _now),
      ReportKind.payments => ReportService.paymentsReceived(
        h,
        data,
        _now,
        _from,
        _to,
        method: _method,
      ),
      ReportKind.fees => ReportService.invoices(
        h,
        data,
        _now,
        year: _year,
        status: _invoiceStatus,
      ),
      ReportKind.pending => ReportService.pendingDues(h, data, _now),
    };
  }

  Future<void> _share(ReportData data, {required bool pdf}) async {
    if (_sharing) return;
    try {
      final report = _build(data);
      setState(() => _sharing = true);
      if (pdf) {
        await ReportExport.sharePdf(report);
      } else {
        await ReportExport.shareCsv(report);
      }
    } on ValidationException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'The report could not be shared. $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReportData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null && !_yearChosen) {
          _year = AcademicYear.of(_today, data.startMonth);
          _yearChosen = true;
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
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
                key: const Key('sharePdf'),
                tooltip: 'Share as PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: data == null || _sharing
                    ? null
                    : () => _share(data, pdf: true),
              ),
              IconButton(
                key: const Key('shareExcel'),
                tooltip: 'Share as Excel (CSV)',
                icon: const Icon(Icons.table_view_outlined),
                onPressed: data == null || _sharing
                    ? null
                    : () => _share(data, pdf: false),
              ),
            ],
          ),
          body: _body(snapshot),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<ReportData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return InfoView(
        key: const Key('reportsError'),
        icon: Icons.cloud_off,
        text: 'The report data could not be loaded.\n${snapshot.error}',
      );
    }
    final data = snapshot.data!;
    ReportTable? report;
    String? problem;
    try {
      report = _build(data);
    } on ValidationException catch (e) {
      problem = e.message;
    }

    return ListView(
      key: const Key('reportView'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final k in ReportKind.values)
              ChoiceChip(
                key: Key('report_${k.name}'),
                label: Text(k.label),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selected: _kind == k,
                selectedColor: AppColors.terracotta,
                labelStyle: TextStyle(
                  color: _kind == k ? Colors.white : AppColors.textPrimary,
                ),
                onSelected: (_) => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ..._filters(data),
        if (problem != null)
          FormMessage(problem, key: const Key('reportProblem'))
        else
          _ReportView(report: report!),
      ],
    );
  }

  List<Widget> _filters(ReportData data) {
    Widget row(List<Widget> children) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
    DropdownMenuItem<T> item<T>(T value, String text) =>
        DropdownMenuItem<T>(value: value, child: Text(text));
    String label(int y) => AcademicYear.label(y, data.startMonth);
    final current = AcademicYear.of(_today, data.startMonth);

    switch (_kind) {
      case ReportKind.students:
        return [
          row([
            FormDropdown<String?>(
              key: const Key('filterStudentStatus'),
              label: 'Status',
              value: _studentStatus,
              items: [
                item<String?>(null, 'All'),
                item<String?>(StudentStatus.active, 'Active'),
                item<String?>(StudentStatus.left, 'Left'),
              ],
              onChanged: (v) => setState(() => _studentStatus = v),
            ),
            FormDropdown<int?>(
              key: const Key('filterCollege'),
              label: 'College',
              value: _collegeId,
              items: [
                item<int?>(null, 'All colleges'),
                for (final c in data.colleges)
                  item<int?>(c.collegeId, c.collegeName),
              ],
              onChanged: (v) => setState(() => _collegeId = v),
            ),
          ]),
        ];
      case ReportKind.payments:
        return [
          row([
            DateField(
              key: const Key('filterFrom'),
              label: 'From',
              value: _from,
              firstDate: DateTime(2000),
              lastDate: _today,
              onChanged: (d) => setState(() => _from = d ?? _from),
            ),
            DateField(
              key: const Key('filterTo'),
              label: 'To',
              value: _to,
              firstDate: DateTime(2000),
              lastDate: _today,
              onChanged: (d) => setState(() => _to = d ?? _to),
            ),
          ]),
          FormDropdown<String?>(
            key: const Key('filterMethod'),
            label: 'Paid by',
            value: _method,
            items: [
              item<String?>(null, 'All'),
              for (final m in PaymentMethod.all) item<String?>(m, m),
            ],
            onChanged: (v) => setState(() => _method = v),
          ),
        ];
      case ReportKind.fees:
        return [
          row([
            FormDropdown<int?>(
              key: const Key('filterYear'),
              label: 'Year',
              value: _year,
              // This academic year first, then the next and the earlier ones.
              items: [
                item<int?>(current, label(current)),
                item<int?>(current + 1, label(current + 1)),
                for (var i = 1; i <= 5; i++)
                  item<int?>(current - i, label(current - i)),
                item<int?>(null, 'All'),
              ],
              onChanged: (v) => setState(() => _year = v),
            ),
            FormDropdown<String?>(
              key: const Key('filterInvoiceStatus'),
              label: 'Status',
              value: _invoiceStatus,
              items: [
                item<String?>(null, 'All'),
                for (final s in InvoiceStatus.all) item<String?>(s, s),
              ],
              onChanged: (v) => setState(() => _invoiceStatus = v),
            ),
          ]),
        ];
      case ReportKind.rooms:
      case ReportKind.pending:
        return const [];
    }
  }
}

/// The report: title, filters and the table (scrolls sideways on a phone).
class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final ReportTable report;

  @override
  Widget build(BuildContext context) {
    const unit = 125.0; // pixels per unit of column width
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.title,
              key: const Key('reportTitle'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.terracotta,
              ),
            ),
            for (final s in report.subtitles.take(2))
              Text(s, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              key: const Key('reportTable'),
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                columnWidths: {
                  for (var i = 0; i < report.columns.length; i++)
                    i: FixedColumnWidth(
                      (report.columns[i].width * unit).clamp(64, 480),
                    ),
                },
                border: const TableBorder(
                  horizontalInside: BorderSide(
                    color: Color(0xFFE7DFD2),
                    width: 1,
                  ),
                ),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppColors.terracotta,
                    ),
                    children: [
                      for (final c in report.columns)
                        _cell(
                          c.title,
                          c.alignRight,
                          bold: true,
                          color: Colors.white,
                        ),
                    ],
                  ),
                  for (final r in report.rows)
                    TableRow(
                      decoration: switch (r.style) {
                        ReportRowStyle.total => const BoxDecoration(
                          color: AppColors.contentBackground,
                        ),
                        ReportRowStyle.normal => null,
                        _ => const BoxDecoration(color: Color(0xFFFBF7F0)),
                      },
                      children: [
                        for (var i = 0; i < report.columns.length; i++)
                          _cell(
                            ReportService.format(r.values[i]),
                            report.columns[i].alignRight,
                            bold: r.style != ReportRowStyle.normal,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, bool right, {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          text,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 13,
            color: color ?? AppColors.textPrimary,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
}
