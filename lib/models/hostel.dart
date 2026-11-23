/// A row of the hostel table.
class Hostel {
  const Hostel({
    required this.hostelId,
    required this.hostelName,
    this.address,
    this.phone,
  });

  final int hostelId;
  final String hostelName;
  final String? address;
  final String? phone;

  factory Hostel.fromMap(Map<String, dynamic> map) => Hostel(
    hostelId: map['hostel_id'] as int,
    hostelName: map['hostel_name'] as String,
    address: map['address'] as String?,
    phone: map['phone'] as String?,
  );
}
