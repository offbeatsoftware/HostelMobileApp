import 'package:flutter/material.dart';

import '../models/payment.dart';
import '../services/date_format.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Every correction and deletion of the hostel's payments, newest first
/// (the desktop Change History).
class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key, required this.changes});

  final Future<List<PaymentChange>> changes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change History')),
      body: FutureBuilder<List<PaymentChange>>(
        future: changes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return InfoView(
              icon: Icons.cloud_off,
              text: 'Could not load the change history.\n${snapshot.error}',
            );
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const InfoView(
              key: Key('historyEmpty'),
              icon: Icons.history,
              text: 'No payment has been corrected or deleted.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  '${list.length} change(s), newest first.',
                  style: const TextStyle(color: AppColors.textMuted),
                );
              }
              final c = list[i - 1];
              final t = c.changedDate;
              final time =
                  '${formatDate(t)} '
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: c.changeType == 'Deleted'
                                  ? const Color(0xFFC0392B)
                                  : AppColors.terracotta,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              c.changeType,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${c.receiptNumber}  ·  ${c.studentName}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(c.details),
                      if (c.reason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Reason: ${c.reason}',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          time,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
