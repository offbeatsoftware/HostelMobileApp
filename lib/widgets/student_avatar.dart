import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/student_file_service.dart';
import '../theme/app_theme.dart';

/// The student's photo in a circle, or the first letter of the name when
/// there is no photo (or it cannot be loaded).
class StudentAvatar extends StatefulWidget {
  const StudentAvatar({
    super.key,
    required this.name,
    required this.photoPath,
    this.size = 44,
    this.onTap,
    this.placeholderColor = AppColors.terracotta,
  });

  final String name;
  final String? photoPath;
  final double size;

  /// The colour of the letter circle (grey for a student who has left).
  final Color placeholderColor;

  /// Called with the photo when it is tapped (to show it full size).
  final void Function(Uint8List photo)? onTap;

  @override
  State<StudentAvatar> createState() => _StudentAvatarState();
}

class _StudentAvatarState extends State<StudentAvatar> {
  late Future<Uint8List?> _photo = StudentFileService.load(widget.photoPath);

  @override
  void didUpdateWidget(StudentAvatar old) {
    super.didUpdateWidget(old);
    if (old.photoPath != widget.photoPath) {
      _photo = StudentFileService.load(widget.photoPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim().characters.first.toUpperCase();
    final placeholder = CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: widget.placeholderColor,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (widget.photoPath == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        final avatar = CircleAvatar(
          key: const Key('studentPhoto'),
          radius: widget.size / 2,
          backgroundColor: AppColors.contentBackground,
          backgroundImage: MemoryImage(bytes),
          onBackgroundImageError: (_, _) {},
        );
        return widget.onTap == null
            ? avatar
            : GestureDetector(onTap: () => widget.onTap!(bytes), child: avatar);
      },
    );
  }
}

/// A picture shown full size, to pinch and zoom (a photo or an Aadhaar card
/// scan).
class PictureViewScreen extends StatelessWidget {
  const PictureViewScreen({
    super.key,
    required this.title,
    required this.bytes,
  });

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.memory(
            bytes,
            key: const Key('pictureView'),
            errorBuilder: (_, _, _) => const Text(
              'The picture could not be shown.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
