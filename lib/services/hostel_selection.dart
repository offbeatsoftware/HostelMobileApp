import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/hostel_repository.dart';
import '../models/hostel.dart';

/// The hostel the admin is working on, like the desktop HostelContext.
/// The choice is remembered on the phone, so the app opens on the same hostel
/// next time. An unknown or missing choice selects the first hostel.
class HostelSelection extends ChangeNotifier {
  static const _prefsKey = 'selectedHostelId';

  List<Hostel> _hostels = const [];
  Hostel? _current;

  /// All hostels, by name.
  List<Hostel> get hostels => _hostels;

  /// The selected hostel, or null when there are no hostels.
  Hostel? get current => _current;

  /// Loads the hostels from the database and selects the remembered one.
  Future<void> load() async {
    _hostels = await HostelRepository.instance.getAll();
    final prefs = await SharedPreferences.getInstance();
    _current =
        _find(prefs.getInt(_prefsKey)) ??
        (_hostels.isEmpty ? null : _hostels.first);
    notifyListeners();
  }

  /// Selects a hostel and remembers it.
  Future<void> select(int hostelId) async {
    final hostel = _find(hostelId);
    if (hostel == null || hostel.hostelId == _current?.hostelId) return;
    _current = hostel;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, hostelId);
  }

  Hostel? _find(int? hostelId) {
    for (final hostel in _hostels) {
      if (hostel.hostelId == hostelId) return hostel;
    }
    return null;
  }
}
