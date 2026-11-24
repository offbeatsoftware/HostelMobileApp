import 'package:flutter/foundation.dart';

import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/refund.dart';
import 'database.dart';

/// Invoices and payments in the Supabase database, using the functions in
/// supabase/008_billing_functions.sql.
class BillingRepository {
  static BillingRepository? _testInstance;

  /// The repository the screens use.
  static BillingRepository get instance => _testInstance ?? BillingRepository();

  /// Lets the automated tests use a fake instead of the real database.
  @visibleForTesting
  static void useInstance(BillingRepository? repository) =>
      _testInstance = repository;

  /// The hostel's invoices, newest first.
  Future<List<Invoice>> getInvoices(int hostelId) async {
    final rows = await Database.client
        .from('invoice_list')
        .select()
        .eq('hostel_id', hostelId)
        .order('invoice_date', ascending: false)
        .order('invoice_id', ascending: false);
    return rows.map(Invoice.fromMap).toList();
  }

  /// The hostel's payments, newest first.
  Future<List<Payment>> getPayments(int hostelId) async {
    final rows = await Database.client
        .from('payment_list')
        .select()
        .eq('hostel_id', hostelId)
        .order('payment_date', ascending: false)
        .order('payment_id', ascending: false);
    return rows.map(Payment.fromMap).toList();
  }

  /// The hostel's refunds (supabase/009_dashboard.sql), newest first.
  Future<List<Refund>> getRefunds(int hostelId) async {
    final rows = await Database.client
        .from('refund_list')
        .select()
        .eq('hostel_id', hostelId)
        .order('refund_date', ascending: false);
    return rows.map(Refund.fromMap).toList();
  }

  /// Every correction and deletion of the hostel's payments, newest first.
  Future<List<PaymentChange>> getChanges(int hostelId) async {
    final rows = await Database.client
        .from('payment_change_list')
        .select()
        .eq('hostel_id', hostelId)
        .order('changed_date', ascending: false)
        .order('payment_change_id', ascending: false);
    return rows.map(PaymentChange.fromMap).toList();
  }

  /// The month the academic year starts (July unless changed on the desktop).
  Future<int> getAcademicYearStartMonth() async =>
      await Database.client.rpc('academic_year_start_month') as int;

  Future<void> updateFee({
    required int invoiceId,
    required double roomRent,
    required double transport,
    required String remarks,
  }) => Database.run(() async {
    await Database.client.rpc(
      'update_fee',
      params: {
        'p_invoice_id': invoiceId,
        'p_room_rent': roomRent,
        'p_transport': transport,
        'p_remarks': remarks,
      },
    );
  });

  Future<void> deleteInvoice(int invoiceId) => Database.run(() async {
    await Database.client.rpc(
      'delete_invoice',
      params: {'p_invoice_id': invoiceId},
    );
  });

  /// Creates a fee for each student (studentId -> rent, transport); returns
  /// how many were created.
  Future<int> createYearFees(
    int year,
    Map<int, (double rent, double transport)> fees,
  ) => Database.run(
    () async =>
        await Database.client.rpc(
              'create_year_fees',
              params: {
                'p_year': year,
                'p_fees': [
                  for (final e in fees.entries)
                    {
                      'student_id': e.key,
                      'room_rent': e.value.$1,
                      'transport': e.value.$2,
                    },
                ],
              },
            )
            as int,
  );

  /// Records a payment; returns its receipt number.
  Future<String> recordPayment({
    required int invoiceId,
    required String date,
    required double amount,
    required String method,
    required String reference,
    required String remarks,
  }) => Database.run(
    () async =>
        await Database.client.rpc(
              'record_payment',
              params: {
                'p_invoice_id': invoiceId,
                'p_date': date,
                'p_amount': amount,
                'p_method': method,
                'p_reference': reference,
                'p_remarks': remarks,
              },
            )
            as String,
  );

  Future<void> editPayment({
    required int paymentId,
    required String date,
    required double amount,
    required String method,
    required String reference,
    required String remarks,
    required String reason,
  }) => Database.run(() async {
    await Database.client.rpc(
      'edit_payment',
      params: {
        'p_payment_id': paymentId,
        'p_date': date,
        'p_amount': amount,
        'p_method': method,
        'p_reference': reference,
        'p_remarks': remarks,
        'p_reason': reason,
      },
    );
  });

  Future<void> deletePayment(int paymentId, String reason) =>
      Database.run(() async {
        await Database.client.rpc(
          'delete_payment',
          params: {'p_payment_id': paymentId, 'p_reason': reason},
        );
      });

  /// Records a refund (supabase/012_refund_functions.sql); returns its
  /// number.
  Future<String> recordRefund({
    required int invoiceId,
    required String date,
    required double amount,
    required String method,
    required String reference,
    required String reason,
  }) => Database.run(
    () async =>
        await Database.client.rpc(
              'record_refund',
              params: {
                'p_invoice_id': invoiceId,
                'p_date': date,
                'p_amount': amount,
                'p_method': method,
                'p_reference': reference,
                'p_reason': reason,
              },
            )
            as String,
  );

  Future<void> deleteRefund(int refundId, String reason) =>
      Database.run(() async {
        await Database.client.rpc(
          'delete_refund',
          params: {'p_refund_id': refundId, 'p_reason': reason},
        );
      });
}
