import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class FilmFrame {
  const FilmFrame(this.t, this.image);

  /// Milliseconds from the start of the replay.
  final int t;
  final ui.Image image;
}

/// Lays frames out in one picture, each with its time, so a single image
/// shows how the screen changed.
class Filmstrip {
  const Filmstrip._();

  static const int maxFrames = 12;
  static const int columns = 4;

  /// Picks up to [max] frames spread evenly, always keeping the first and last.
  static List<T> pick<T>(List<T> items, {int max = maxFrames}) {
    if (items.length <= max) return List.of(items);
    final out = <T>[];
    for (var i = 0; i < max; i++) {
      out.add(items[(i * (items.length - 1) / (max - 1)).round()]);
    }
    return out;
  }

  static Future<Uint8List?> compose(List<FilmFrame> frames) async {
    if (frames.isEmpty) return null;
    final chosen = pick(frames);
    final w = chosen.first.image.width.toDouble();
    final h = chosen.first.image.height.toDouble();
    const gap = 8.0;
    const label = 22.0;
    final cols = chosen.length < columns ? chosen.length : columns;
    final rows = (chosen.length / columns).ceil();
    final width = cols * (w + gap) + gap;
    final height = rows * (h + label + gap) + gap;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xFF111111));

    for (var i = 0; i < chosen.length; i++) {
      final col = i % columns;
      final row = i ~/ columns;
      final x = gap + col * (w + gap);
      final y = gap + row * (h + label + gap);
      final f = chosen[i];

      final tp = TextPainter(
        text: TextSpan(
          text: '+${(f.t / 1000).toStringAsFixed(1)}s',
          style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y + (label - tp.height) / 2));

      final src = Rect.fromLTWH(
          0, 0, f.image.width.toDouble(), f.image.height.toDouble());
      canvas.drawImageRect(
          f.image, src, Rect.fromLTWH(x, y + label, w, h), Paint());
      canvas.drawRect(
        Rect.fromLTWH(x, y + label, w, h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF444444),
      );
    }

    final image =
        await recorder.endRecording().toImage(width.ceil(), height.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}
