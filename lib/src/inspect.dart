import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'fixable.dart';
import 'report.dart';

/// Finds what is under a touch point and describes it for a report.
class Inspector {
  const Inspector._();

  static const int _maxTexts = 8;

  /// [screen] is the app's full size; elements that fill it are ignored so a
  /// press on empty background still names something small if there is any.
  static ElementInfo? inspect(BuildContext context, Offset point, Size screen) {
    final result = HitTestResult();
    final viewId = View.of(context).viewId;
    WidgetsBinding.instance.hitTestInView(result, point, viewId);

    final boxes = <RenderBox>[
      for (final e in result.path)
        if (e.target is RenderBox && (e.target as RenderBox).hasSize)
          e.target as RenderBox,
    ];

    final marks = FixableRegistry.instance.at(point);
    final screenArea = screen.width * screen.height;

    RenderBox? picked;
    for (final b in boxes) {
      if (b.size.width * b.size.height < screenArea * 0.9) {
        picked = b;
        break;
      }
    }

    final mark = marks.isEmpty ? null : marks.first;
    if (picked == null && mark == null) return null;

    final Rect rect = mark != null &&
            (picked == null ||
                mark.rect.width * mark.rect.height <=
                    picked.size.width * picked.size.height * 1.0001)
        ? mark.rect
        : picked!.localToGlobal(Offset.zero) & picked.size;

    // Text inside the element, and text in its surroundings.
    final scopeBox = _ancestorWithin(picked, screenArea * 0.35) ?? picked;
    final inside = <String>[];
    final nearby = <String>[];
    if (scopeBox != null) {
      _collectParagraphs(scopeBox, (rp, bounds) {
        final text = rp.text.toPlainText().trim();
        if (text.isEmpty || _isIconGlyphs(text)) return;
        final into = bounds.overlaps(rect) ? inside : nearby;
        if (into.length < _maxTexts && !into.contains(text)) into.add(text);
      });
    }

    String? chain;
    if (kDebugMode && picked != null) {
      final creator = picked.debugCreator;
      if (creator is DebugCreator) {
        chain = creator.element.debugGetCreatorChain(8);
      }
    }

    return ElementInfo(
      rect: rect,
      kind: (picked ?? boxes.firstOrNull)?.runtimeType.toString() ?? 'unknown',
      name: mark?.name,
      location: mark?.location,
      texts: inside,
      nearbyTexts: nearby,
      creatorChain: chain,
    );
  }

  /// Icon fonts draw their icons as private-use characters; they are noise in
  /// a report.
  static bool _isIconGlyphs(String text) =>
      text.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000);

  static RenderBox? _ancestorWithin(RenderBox? start, double maxArea) {
    if (start == null) return null;
    RenderBox best = start;
    RenderObject? p = start.parent;
    for (var i = 0; i < 4 && p != null; i++, p = p.parent) {
      if (p is RenderBox &&
          p.hasSize &&
          p.size.width * p.size.height <= maxArea) {
        best = p;
      } else if (p is RenderBox && p.hasSize) {
        break;
      }
    }
    return best;
  }

  static void _collectParagraphs(
      RenderObject root, void Function(RenderParagraph, Rect) visit) {
    void walk(RenderObject o) {
      if (o is RenderParagraph && o.hasSize && o.attached) {
        visit(o, o.localToGlobal(Offset.zero) & o.size);
      }
      o.visitChildren(walk);
    }

    walk(root);
  }
}
