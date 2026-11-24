import '../models/allocation.dart';
import '../models/attendance.dart';
import '../models/student.dart';
import 'date_format.dart';
import 'message_text.dart';
import 'natural_order.dart';

/// Night attendance, as the desktop AttendanceService: the students in a
/// room of the hostel that night, everyone present unless marked absent;
/// earlier dates can be corrected, future dates cannot be marked. The parent
/// of an absent student (the mother, else the father) can be sent a WhatsApp
/// message with the desktop's wording.
class AttendanceService {
  /// The night's sheet, sorted by room (2 before 10), bed and name.
  static List<AttendanceEntry> buildSheet({
    required DateTime date,
    required List<Student> students,
    required List<RoomAllocation> allocations,
    required List<SavedAttendance> saved,
    required Set<int> messaged,
  }) {
    final day = dateOnly(date);
    final byId = {for (final s in students) s.studentId: s};
    final records = {for (final r in saved) r.studentId: r};

    // In the room that night: checked in on or before the date and not
    // checked out or transferred that day; the latest stay counts.
    final night = <int, RoomAllocation>{};
    for (final a in allocations) {
      final inRoom =
          !a.checkInDate.isAfter(day) &&
          (a.checkOutDate == null || a.checkOutDate!.isAfter(day));
      if (!inRoom) continue;
      final other = night[a.studentId];
      if (other == null || a.checkInDate.isAfter(other.checkInDate)) {
        night[a.studentId] = a;
      }
    }

    final entries = <AttendanceEntry>[];
    for (final a in night.values) {
      final s = byId[a.studentId];
      if (s == null) continue;
      final record = records[a.studentId];
      final parent = recipient(s);
      entries.add(
        AttendanceEntry(
          studentId: s.studentId,
          studentName: s.studentName,
          roomNumber: a.roomNumber,
          bedNumber: a.bedNumber,
          parentName: parent?.$1,
          parentMobile: parent?.$2,
          parentRelation: parent?.$3,
          isPresent: record?.isPresent ?? true,
          remarks: record?.remarks ?? '',
          isSaved: record != null,
          messaged: messaged.contains(s.studentId),
        ),
      );
    }
    entries.sort((a, b) {
      final room = naturalCompare(a.roomNumber, b.roomNumber);
      if (room != 0) return room;
      final bed = (a.bedNumber ?? 1 << 30).compareTo(b.bedNumber ?? 1 << 30);
      if (bed != 0) return bed;
      return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
    });
    return entries;
  }

  /// "Saved: 10 present, 2 absent" (or "Not saved yet", "Not marked yet").
  static String status(List<AttendanceEntry> entries, {required bool dirty}) {
    final absent = entries.where((e) => !e.isPresent).length;
    final marked = entries.any((e) => e.isSaved);
    final state = dirty
        ? 'Not saved yet'
        : (marked ? 'Saved' : 'Not marked yet');
    return '$state: ${entries.length - absent} present, $absent absent';
  }

  /// The subject the desktop keeps in the message history for the night.
  static String historySubject(DateTime date) =>
      'attendance ${formatDate(date)}';

  /// A mobile number as WhatsApp needs it: country code and digits only. A
  /// 10 digit Indian mobile gets 91 in front; a leading 0 or +91 is handled.
  /// Null when it is not a usable mobile number (as the desktop).
  static String? toWhatsAppNumber(String? mobile) {
    final text = mobile ?? '';
    var digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final international = text.trimLeft().startsWith('+');
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    bool mobileStart(String d) => '6789'.contains(d);
    if (digits.length == 10 && mobileStart(digits[0])) return '91$digits';
    if (digits.length == 12 &&
        digits.startsWith('91') &&
        mobileStart(digits[2])) {
      return digits;
    }
    return international &&
            digits.length >= 11 &&
            digits.length <= 15 &&
            !digits.startsWith('91')
        ? digits
        : null;
  }

  /// Who is told about an absence: the mother's mobile, else the father's.
  /// (name, WhatsApp number, relation), or null when neither has a mobile.
  static (String, String, String)? recipient(Student s) {
    for (final (name, mobile, relation) in [
      (s.motherName, s.motherMobile, 'Mother'),
      (s.fatherName, s.fatherMobile, 'Father'),
    ]) {
      final number = toWhatsAppNumber(mobile);
      if (number != null) {
        return (
          (name ?? '').trim().isEmpty ? 'Parent' : name!.trim(),
          number,
          relation,
        );
      }
    }
    return null;
  }

  /// The desktop's attendance message ([template] is the text saved on the
  /// desktop, or its default wording).
  static String message({
    required String parentName,
    required String studentName,
    required String hostelName,
    required DateTime date,
    String? hostelPhone,
    String? adminPhone,
    String template = MessageText.defaultAttendanceText,
  }) => MessageText.fill(template, {
    'ParentName': parentName,
    'StudentName': studentName,
    'HostelName': hostelName,
    'AttendanceDate': formatDate(date),
    'HostelPhone': MessageText.contactNumber(hostelPhone, adminPhone),
  });

  /// The WhatsApp link that opens the chat with the message typed in.
  static Uri whatsAppLink(String number, String text) =>
      Uri.https('wa.me', '/$number', {'text': text});
}
