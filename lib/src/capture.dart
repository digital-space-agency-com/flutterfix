import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Takes a screenshot of [boundary] with [highlight] outlined (global coords).
Future<Uint8List?> captureScreenshot(
    RenderRepaintBoundary boundary, Rect? highlight,
    {double maxPixelRatio = 2.0}) async {
  try {
    final views = ui.PlatformDispatcher.instance.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final ratio = dpr > maxPixelRatio ? maxPixelRatio : dpr;
    final image = await boundary.toImage(pixelRatio: ratio);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    if (highlight != null) {
      final r = Rect.fromLTRB(highlight.left * ratio, highlight.top * ratio,
          highlight.right * ratio, highlight.bottom * ratio);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            r.inflate(3 * ratio), Radius.circular(8 * ratio)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * ratio
          ..color = const Color(0xFFFF2D55),
      );
    }
    final out =
        await recorder.endRecording().toImage(image.width, image.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
