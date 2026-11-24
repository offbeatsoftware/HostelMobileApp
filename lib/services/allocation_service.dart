import '../data/allocation_repository.dart';
import '../models/allocation.dart';
import '../models/invoice.dart';
import '../models/room.dart';
import '../models/student.dart';
import 'date_format.dart';
import 'money.dart';
import 'natural_order.dart';
import 'validators.dart';

/// The yearly fee typed at check-in.
class YearFee {
  const YearFee(this.roomRent, this.transport);

  final double roomRent;
  final double transport;

  double get total => roomRent + transport;
}

/// Room allocation rules, as in the desktop AllocationService: a student is
/// in one room at a time, of their hostel and gender, with a free bed; a
/// transfer leaves the old room and enters the new one on the same date;
/// check-out sets the student's status to Left. The database checks every
/// rule again when saving.
class AllocationService {
  static const maxAmount = 10000000.0;

  /// Sorted by room (2 before 10), then student, then check-in date.
  static List<RoomAllocation> sorted(List<RoomAllocation> list) =>
      [...list]..sort((a, b) {
        final room = naturalCompare(a.roomNumber, b.roomNumber);
        if (room != 0) return room;
        final name = a.studentName.toLowerCase().compareTo(
          b.studentName.toLowerCase(),
        );
        return name != 0 ? name : a.checkInDate.compareTo(b.checkInDate);
      });

  /// Allocations whose student name, room or mobile contains the text.
  static List<RoomAllocation> search(List<RoomAllocation> list, String? text) {
    final s = Validators.clean(text).toLowerCase();
    if (s.isEmpty) return list;
    return list
        .where(
          (a) =>
              a.studentName.toLowerCase().contains(s) ||
              a.roomNumber.toLowerCase().contains(s) ||
              (a.studentMobile ?? '').toLowerCase().contains(s),
        )
        .toList();
  }

  /// Active students who are not in a room, sorted by name.
  static List<Student> studentsWithoutRoom(
    List<Student> students,
    List<RoomAllocation> allocations,
  ) {
    final inRoom = {
      for (final a in allocations)
        if (a.isCurrent) a.studentId,
    };
    return students
        .where((s) => s.isActive && !inRoom.contains(s.studentId))
        .toList()
      ..sort(
        (a, b) =>
            a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()),
      );
  }

  /// Active rooms for the gender with a free bed, except one room (for
  /// transfers), sorted by room number.
  static List<Room> roomsFor(
    List<Room> rooms,
    String? gender, {
    int? exceptRoomId,
  }) =>
      rooms
          .where(
            (r) =>
                r.gender == gender &&
                r.available > 0 &&
                r.roomId != exceptRoomId,
          )
          .toList()
        ..sort((a, b) => naturalCompare(a.roomNumber, b.roomNumber));

  /// The free beds of a room (1 up to its number of beds).
  static List<int> freeBeds(Room room, List<RoomAllocation> allocations) {
    final taken = {
      for (final a in allocations)
        if (a.isCurrent && a.roomId == room.roomId && a.bedNumber != null)
          a.bedNumber!,
    };
    return [
      for (var bed = 1; bed <= room.capacity; bed++)
        if (!taken.contains(bed)) bed,
    ];
  }

  /// Why no room can be offered: rooms with free beds for the other gender,
  /// or switched off, so the admin knows what to correct.
  static String explainNoRoom(
    List<Room> rooms,
    Student student, {
    int? exceptRoomId,
  }) {
    final forWhom = RoomGender.displayName(student.gender ?? '').toLowerCase();
    final others = rooms.where((r) => r.roomId != exceptRoomId).toList()
      ..sort((a, b) => naturalCompare(a.roomNumber, b.roomNumber));
    final otherGender = others
        .where(
          (r) =>
              r.isActive &&
              r.gender != student.gender &&
              r.capacity > r.occupied,
        )
        .toList();
    final switchedOff = others
        .where(
          (r) =>
              !r.isActive &&
              r.gender == student.gender &&
              r.capacity > r.occupied,
        )
        .toList();

    var message =
        'There is no free bed in a room for $forWhom: '
        '${student.studentName} is saved as ${student.gender}.';
    if (otherGender.isNotEmpty) {
      message +=
          " Free beds in "
          "${RoomGender.displayName(otherGender.first.gender).toLowerCase()}' rooms: "
          "${otherGender.map((r) => '${r.roomNumber} (${r.capacity - r.occupied})').join(', ')}.";
    }
    if (switchedOff.isNotEmpty) {
      message +=
          ' Switched off: ${switchedOff.map((r) => r.roomNumber).join(', ')}.';
    }
    return '$message If a gender is wrong, correct it on the Students screen '
        '(student) or the Rooms screen (room).';
  }

  /// The student's fee for the academic year, if any.
  static Invoice? feeForYear(List<Invoice> invoices, int year) {
    for (final i in invoices) {
      if (i.academicYear == year) return i;
    }
    return null;
  }

  /// The fee still pending on all of the student's invoices.
  static double pendingFee(List<Invoice> invoices) => invoices.fold(
    0,
    (t, i) => t + (i.pendingAmount > 0 ? i.pendingAmount : 0),
  );

  /// Reads the typed fee; throws [ValidationException] when it is not valid.
  static YearFee readFee(String rentText, String transportText) {
    final rent = Money.tryParse(rentText);
    if (rent == null || rent <= 0) {
      throw const ValidationException(
        'Please enter the room rent for the year agreed with the student.',
      );
    }
    var transport = 0.0;
    if (transportText.trim().isNotEmpty) {
      final t = Money.tryParse(transportText);
      if (t == null) {
        throw const ValidationException(
          'Please enter the transport amount for the year, or leave it empty.',
        );
      }
      transport = t;
    }
    _checkAmount(rent, 'room rent');
    _checkAmount(transport, 'transport amount');
    return YearFee(rent, transport);
  }

  static void _checkAmount(double amount, String name) {
    if (amount < 0) {
      throw ValidationException('The $name cannot be negative.');
    }
    if (amount > maxAmount) {
      throw ValidationException(
        'The $name cannot be more than ${Money.format(maxAmount)}.',
      );
    }
    if (((amount * 100) - (amount * 100).round()).abs() > 1e-6) {
      throw ValidationException(
        'The $name can have at most two decimal places (paise).',
      );
    }
  }

  static void _checkDate(DateTime date, DateTime today, String action) {
    if (dateOnly(date).isAfter(dateOnly(today))) {
      throw ValidationException('The $action date cannot be in the future.');
    }
  }

  static String _remarks(String? remarks) {
    final clean = Validators.clean(remarks);
    Validators.checkLength(clean, 255, 'Remarks');
    return clean;
  }

  /// Checks a student in; [fee] is null when the student already has a fee
  /// for the academic year.
  static Future<void> checkIn({
    required Student? student,
    required Room? room,
    required DateTime date,
    required DateTime today,
    String? remarks,
    int? bed,
    YearFee? fee,
  }) async {
    if (student == null) {
      throw const ValidationException('Please select the student.');
    }
    if (room == null) {
      throw const ValidationException('Please select the room.');
    }
    if (dateOnly(date).isBefore(dateOnly(student.admissionDate))) {
      throw ValidationException(
        'The check-in date cannot be before the '
        'admission date (${formatDate(student.admissionDate)}).',
      );
    }
    _checkDate(date, today, 'check-in');
    await AllocationRepository.instance.checkIn(
      studentId: student.studentId,
      roomId: room.roomId,
      date: isoDate(date),
      remarks: _remarks(remarks),
      bed: bed,
      roomRent: fee?.roomRent,
      transport: fee?.transport,
    );
  }

  static Future<void> transfer({
    required RoomAllocation current,
    required Room? newRoom,
    required DateTime date,
    required DateTime today,
    String? remarks,
    int? bed,
  }) async {
    if (newRoom == null) {
      throw const ValidationException('Please select the room.');
    }
    if (dateOnly(date).isBefore(current.checkInDate)) {
      throw ValidationException(
        'The transfer date cannot be before the '
        'check-in date (${formatDate(current.checkInDate)}).',
      );
    }
    _checkDate(date, today, 'transfer');
    await AllocationRepository.instance.transfer(
      studentId: current.studentId,
      newRoomId: newRoom.roomId,
      date: isoDate(date),
      remarks: _remarks(remarks),
      bed: bed,
    );
  }

  static Future<void> checkOut({
    required RoomAllocation current,
    required DateTime date,
    required DateTime today,
    String? remarks,
    bool waivePending = false,
  }) async {
    if (dateOnly(date).isBefore(current.checkInDate)) {
      throw ValidationException(
        'The check-out date cannot be before the '
        'check-in date (${formatDate(current.checkInDate)}).',
      );
    }
    _checkDate(date, today, 'check-out');
    await AllocationRepository.instance.checkOut(
      studentId: current.studentId,
      date: isoDate(date),
      remarks: _remarks(remarks),
      waive: waivePending,
    );
  }
}
