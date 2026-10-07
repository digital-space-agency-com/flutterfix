import 'package:flutter/rendering.dart';

/// What is on screen right now, in numbers.
class ScreenSample {
  const ScreenSample({required this.text, required this.lists});

  /// Pieces of text drawn on the visible page (icon glyphs excluded).
  final int text;

  /// Items currently built in each visible scrolling list or grid.
  final List<int> lists;
}

/// Reads the render tree. Only what is on stage is counted: pages hidden
/// behind the current one, or off stage, are skipped. Lists with no items are
/// still counted (as zero), which is how an empty list is noticed.
class TreeProbe {
  const TreeProbe._();

  static ScreenSample sample(Size screen) {
    var text = 0;
    final lists = <int>[];
    final screenRect = Offset.zero & screen;

    void walk(RenderObject o) {
      if (o is RenderOffstage && o.offstage) return;
      if (o is RenderParagraph) {
        if (_countsAsText(o, screenRect)) text++;
      } else if (o is RenderSliverMultiBoxAdaptor) {
        lists.add(o.childCount);
      }
      // A page stack keeps covered pages in the tree; its semantics visit
      // skips them. Everywhere else every child counts, so an empty list
      // (which draws nothing) is still seen.
      if (o.runtimeType.toString().contains('Theater')) {
        o.visitChildrenForSemantics(walk);
      } else {
        o.visitChildren(walk);
      }
    }

    for (final view in RendererBinding.instance.renderViews) {
      view.visitChildren(walk);
    }
    return ScreenSample(text: text, lists: lists);
  }

  static bool _countsAsText(RenderParagraph p, Rect screen) {
    if (!p.attached || !p.hasSize) return false;
    final t = p.text.toPlainText().trim();
    if (t.isEmpty) return false;
    if (t.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000)) {
      return false; // an icon font glyph
    }
    try {
      final rect = p.localToGlobal(Offset.zero) & p.size;
      return rect.overlaps(screen);
    } catch (_) {
      return false;
    }
  }
}
