import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../services/money.dart';
import '../theme/app_theme.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Payments received per month as thin bars on one axis. Tapping a bar
/// shows its exact amount; "Show as table" lists the same figures.
class MonthBarChart extends StatefulWidget {
  const MonthBarChart({super.key, required this.months, this.height = 170});

  final List<MonthTotal> months;
  final double height;

  @override
  State<MonthBarChart> createState() => _MonthBarChartState();
}

class _MonthBarChartState extends State<MonthBarChart> {
  int? _selected;
  bool _table = false;

  String _name(DateTime m) => '${_monthNames[m.month - 1]} ${m.year}';

  @override
  Widget build(BuildContext context) {
    final months = widget.months;
    final max = months.fold(0.0, (t, m) => m.amount > t ? m.amount : t);
    final selected = _selected == null ? null : months[_selected!];
    final caption = selected == null
        ? 'Tap a bar to see the amount.'
        : '${_name(selected.month)}: ${Money.format(selected.amount)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                key: const Key('chartCaption'),
                style: TextStyle(
                  color: selected == null
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                  fontWeight: selected == null
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              key: const Key('chartTable'),
              onPressed: () => setState(() => _table = !_table),
              child: Text(_table ? 'Show as chart' : 'Show as table'),
            ),
          ],
        ),
        if (_table)
          Column(
            key: const Key('chartAsTable'),
            children: [
              for (final m in months)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(_name(m.month))),
                      Text(
                        Money.format(m.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          )
        else
          SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One recessive axis: the highest month and zero.
                SizedBox(
                  width: 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        max == 0 ? '' : Money.compact(max),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '₹0',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < months.length; i++)
                        Expanded(child: _bar(i, months[i], max)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bar(int i, MonthTotal m, double max) {
    final isSelected = _selected == i;
    return Semantics(
      label: '${_name(m.month)}: ${Money.format(m.amount)}',
      button: true,
      child: GestureDetector(
        key: Key('bar_$i'),
        behavior: HitTestBehavior.opaque, // the whole column is the target
        onTap: () => setState(() => _selected = isSelected ? null : i),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFD9D2C5), width: 1),
                  ),
                ),
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: max == 0 ? 0 : (m.amount / max).clamp(0, 1),
                  child: Container(
                    // 2px gap on each side keeps neighbouring bars apart.
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.terracottaDark
                          : AppColors.terracotta,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 18,
              child: Center(
                child: Text(
                  _monthNames[m.month.month - 1].substring(0, 1),
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
