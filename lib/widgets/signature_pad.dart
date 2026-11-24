import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What is drawn in one signature box: the strokes, or a signature saved
/// earlier that is shown until the admin draws again or clears it.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Uint8List? _saved;
  Size _size = const Size(320, 150);

  /// Lets the automated tests skip the real drawing.
  @visibleForTesting
  static Future<Uint8List> Function(List<List<Offset>> strokes, Size size)?
  rasterizer;

  /// True when something is drawn or a saved signature is shown.
  bool get hasSignature => strokes.isNotEmpty || _saved != null;

  Uint8List? get saved => _saved;

  /// Shows a signature saved earlier.
  void showSaved(Uint8List? bytes) {
    strokes.clear();
    _saved = bytes;
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    _saved = null;
    notifyListeners();
  }

  void _start(Offset p) {
    // Drawing again replaces a saved signature.
    _saved = null;
    strokes.add([p]);
    notifyListeners();
  }

  void _add(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.add(p);
    notifyListeners();
  }

  /// The signature as a PNG: what is drawn, else the saved one, else null.
  Future<Uint8List?> toPng() async {
    if (strokes.isEmpty) return _saved;
    return (rasterizer ?? _rasterize)(strokes, _size);
  }

  static Future<Uint8List> _rasterize(
    List<List<Offset>> strokes,
    Size size,
  ) async {
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    _paintStrokes(canvas, strokes, Colors.black);
    final image = await recorder.endRecording().toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final stroke in strokes) {
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, 1.25, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final p in stroke.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.controller) : super(repaint: controller);

  final SignatureController controller;

  @override
  void paint(Canvas canvas, Size size) {
    controller._size = size;
    _paintStrokes(canvas, controller.strokes, Colors.black);
  }

  @override
  bool shouldRepaint(_StrokePainter old) => false;
}

/// A box to sign in with a finger or pen. It takes over touches inside it,
/// so the page behind does not scroll while signing.
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 150});

  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new,
              (_) {},
            ),
      },
      child: Listener(
        onPointerDown: (e) => controller._start(e.localPosition),
        onPointerMove: (e) => controller._add(e.localPosition),
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.textMuted),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Stack(
                fit: StackFit.expand,
                children: [
                  if (controller.saved != null)
                    Image.memory(
                      controller.saved!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  CustomPaint(painter: _StrokePainter(controller)),
                  if (!controller.hasSignature)
                    const Center(
                      child: Text(
                        'Sign here',
                        style: TextStyle(color: AppColors.tileDisabled),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
