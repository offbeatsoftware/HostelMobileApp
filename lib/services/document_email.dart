import '../data/admin_repository.dart';
import '../models/email_settings.dart';
import '../models/print_data.dart';
import '../models/student.dart';
import 'auth_service.dart';
import 'date_format.dart';
import 'email_settings_service.dart';
import 'money.dart';
import 'validators.dart';

/// A parent who receives an email: the name used in the greeting, the
/// address and Father or Mother.
class EmailContact {
  const EmailContact(this.name, this.email, this.relation);

  final String name;
  final String email;
  final String relation;
}

/// An email ready to share: who it is for, its text and the PDF's name.
class EmailDraft {
  const EmailDraft({
    required this.to,
    required this.relation,
    required this.parentName,
    required this.copyTo,
    required this.subject,
    required this.body,
  });

  final String to;
  final String relation;
  final String parentName;

  /// The admin's address, which gets a copy of every email to a parent
  /// (empty when not set or when it is the parent's own address).
  final String copyTo;
  final String subject;
  final String body;
}

/// The invoice, receipt and refund receipt emails, with the texts of Email
/// Settings, as the desktop EmailService.Prepare*. The phone does not send
/// them itself (the Gmail app password stays on the desktop): the draft is
/// shared with the PDF to the phone's mail app.
class DocumentEmail {
  /// The refund receipt email (fixed wording, as the desktop).
  static const refundTemplate = EmailTemplate(
    'Refund receipt {RefundNumber} for {StudentName}',
    'Dear {ParentName},\n\n'
        'We have refunded {RefundAmount} for {StudentName} on {RefundDate} '
        '({RefundMethod}), from the hostel fee for the academic year '
        '{AcademicYear} (invoice {InvoiceNumber}).\n'
        'The refund receipt is attached.\n\n'
        'Regards,\n{HostelName}\n{HostelPhone}',
  );

  static String _t(String? s) => (s ?? '').trim();

  /// Who receives fee emails: the father, or the mother when the father has
  /// no email. Null when neither has an email.
  static EmailContact? feeContact(Student s) {
    if (_t(s.fatherEmail).isNotEmpty) {
      return EmailContact(_t(s.fatherName), _t(s.fatherEmail), 'Father');
    }
    if (_t(s.motherEmail).isNotEmpty) {
      return EmailContact(
        _t(s.motherName).isEmpty ? 'Parent' : _t(s.motherName),
        _t(s.motherEmail),
        'Mother',
      );
    }
    return null;
  }

  static EmailContact _requireContact(Student s) =>
      feeContact(s) ??
      (throw ValidationException(
        'Neither the father nor the mother of ${s.studentName} has an email '
        'address. Add one on the Students screen.',
      ));

  /// Replaces each {Field} with its value; unknown fields stay as they are.
  static String fill(String template, Map<String, String> values) =>
      template.replaceAllMapped(
        RegExp(r'\{([A-Za-z]+)\}'),
        (m) => values[m.group(1)] ?? m.group(0)!,
      );

  static Future<Map<String, String>> _common(
    Student student,
    EmailContact contact,
    String hostelName,
    String? hostelPhone,
  ) async {
    final admin = await AdminRepository.instance.getCurrent(
      AuthService.currentUser?.uid,
    );
    return {
      'StudentName': student.studentName,
      'ParentName': contact.name,
      'HostelName': hostelName,
      'HostelPhone': _t(hostelPhone),
      'AdminEmail': admin?.email ?? '',
      'AdminPhone': admin?.phone ?? '',
    };
  }

  static EmailDraft _build(
    EmailTemplate template,
    Map<String, String> values,
    EmailContact contact,
    String adminEmail,
  ) => EmailDraft(
    to: contact.email,
    relation: contact.relation,
    parentName: contact.name,
    copyTo: adminEmail.toLowerCase() == contact.email.toLowerCase()
        ? ''
        : adminEmail,
    subject: fill(
      template.subject,
      values,
    ).replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim(),
    body: fill(template.body, values).trim(),
  );

  static Future<EmailDraft> invoice(InvoicePrintData d) async {
    final settings = await EmailSettingsService.get();
    final contact = _requireContact(d.student);
    final i = d.invoice;
    final values = await _common(
      d.student,
      contact,
      d.hostel.hostelName,
      d.hostel.phone,
    );
    values['InvoiceNumber'] = i.invoiceNumber;
    values['AcademicYear'] = AcademicYear.label(i.academicYear, d.startMonth);
    values['RoomRent'] = Money.rupees(i.roomRent);
    values['Transport'] = Money.rupees(i.transportAmount);
    values['Amount'] = Money.rupees(i.totalAmount);
    values['PaidAmount'] = Money.rupees(i.paidAmount);
    values['Pending'] = Money.rupees(i.pendingAmount);
    return _build(settings.invoice, values, contact, values['AdminEmail']!);
  }

  static Future<EmailDraft> receipt(ReceiptPrintData d) async {
    final settings = await EmailSettingsService.get();
    final contact = _requireContact(d.student);
    final p = d.payment;
    final values = await _common(
      d.student,
      contact,
      d.hostel.hostelName,
      d.hostel.phone,
    );
    values['InvoiceNumber'] = d.invoice.invoiceNumber;
    values['AcademicYear'] = AcademicYear.label(
      d.invoice.academicYear,
      d.startMonth,
    );
    values['ReceiptNumber'] = p.receiptNumber;
    values['PaidAmount'] = Money.rupees(p.amount);
    values['PaymentDate'] = formatDate(p.paymentDate);
    values['PaymentMethod'] = p.paymentMethod;
    values['TotalAmount'] = Money.rupees(d.invoice.totalAmount);
    values['Pending'] = Money.rupees(d.invoice.pendingAmount);
    return _build(settings.receipt, values, contact, values['AdminEmail']!);
  }

  static Future<EmailDraft> refund(RefundPrintData d) async {
    final contact = _requireContact(d.student);
    final r = d.refund;
    final values = await _common(
      d.student,
      contact,
      d.hostel.hostelName,
      d.hostel.phone,
    );
    values['RefundNumber'] = r.refundNumber;
    values['RefundAmount'] = Money.rupees(r.amount);
    values['RefundDate'] = formatDate(r.refundDate);
    values['RefundMethod'] = r.refundMethod;
    values['InvoiceNumber'] = d.invoice.invoiceNumber;
    values['AcademicYear'] = AcademicYear.label(
      d.invoice.academicYear,
      d.startMonth,
    );
    return _build(refundTemplate, values, contact, values['AdminEmail']!);
  }
}
