import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Marks a widget so reports name it, and (in debug builds) point at the line
/// that created it.
///
/// ```dart
/// Text(card.number).fixable('card.number')  // via the extension
/// Fixable('home.walletCard', child: WalletCard())
/// ```
///
/// Put the mark on the view whose code you want Claude to open: the `Text`
/// itself for a typo or colour, the container for spacing or layout. Nested
/// marks resolve to the innermost one under the finger.
class Fixable extends StatefulWidget {
  Fixable(this.name, {super.key, required this.child})
      : location = kDebugMode ? _callSite() : null;

  final String name;
  final Widget child;

  /// `lib/foo.dart:12` of the call site; null outside debug builds.
  final String? location;

  @override
  State<Fixable> createState() => _FixableState();

  static final RegExp _frame =
      RegExp(r'\(?(package:[^\s)]+|file:///[^\s)]+):(\d+):\d+\)?$');

  static String? _callSite() {
    for (final line in StackTrace.current.toString().split('\n')) {
      if (line.contains('flutterfix/src/') ||
          line.contains('flutterfix/lib/')) {
        continue;
      }
      final m = _frame.firstMatch(line.trim());
      if (m == null) continue;
      var path = m.group(1)!;
      if (path.startsWith('package:')) {
        path = path.replaceFirst(RegExp(r'^package:[^/]+/'), 'lib/');
      } else {
        final i = path.indexOf('/lib/');
        path = i >= 0 ? path.substring(i + 1) : path.split('/').last;
      }
      return '$path:${m.group(2)}';
    }
    return null;
  }
}

/// Lets any widget be marked with `.fixable('name')`.
extension FixableX on Widget {
  Widget fixable(String name) => Fixable(name, child: this);
}

/// The marked elements that are currently on screen.
class FixableRegistry {
  FixableRegistry._();
  static final FixableRegistry instance = FixableRegistry._();

  final Set<_FixableState> _items = {};

  /// Marked elements whose bounds contain [point], innermost (smallest) first.
  List<FixableHit> at(Offset point) {
    final hits = <FixableHit>[];
    for (final s in _items) {
      final ro = s.context.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final rect = ro.localToGlobal(Offset.zero) & ro.size;
      if (rect.contains(point)) {
        hits.add(FixableHit(s.widget.name, s.widget.location, rect));
      }
    }
    hits.sort((a, b) =>
        (a.rect.width * a.rect.height).compareTo(b.rect.width * b.rect.height));
    return hits;
  }

  @visibleForTesting
  int get count => _items.length;
}

@immutable
class FixableHit {
  const FixableHit(this.name, this.location, this.rect);
  final String name;
  final String? location;
  final Rect rect;
}

class _FixableState extends State<Fixable> {
  @override
  void initState() {
    super.initState();
    FixableRegistry.instance._items.add(this);
  }

  @override
  void dispose() {
    FixableRegistry.instance._items.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
