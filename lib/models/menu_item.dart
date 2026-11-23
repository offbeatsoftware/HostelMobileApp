import 'package:flutter/material.dart';

/// One entry of the home menu (the desktop's left navigation menu).
class MenuItem {
  const MenuItem({
    required this.group,
    required this.title,
    required this.description,
    required this.icon,
    this.requiresHostel = false,
  });

  /// Menu section the entry appears under, for example HOSTEL.
  final String group;

  /// Text on the tile and in the screen header.
  final String title;

  /// One line shown on the screen.
  final String description;

  final IconData icon;

  /// True when the screen works on the selected hostel and cannot open without one.
  final bool requiresHostel;
}
