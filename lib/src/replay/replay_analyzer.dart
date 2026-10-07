import 'replay_models.dart';

/// What the replay found. Pure logic over the event log, so it can be tested
/// without a screen.
class ReplayAnalysis {
  const ReplayAnalysis(this.findings, this.timeline);

  /// Plain-English problems (empty when nothing stood out).
  final List<String> findings;

  /// Condensed events for the report.
  final List<Map<String, Object?>> timeline;

  String summaryFor(double seconds) => findings.isEmpty
      ? 'Nothing stood out in the last ${seconds.toStringAsFixed(1)}s: no slow '
          'frames and no empty lists.'
      : findings.join('\n');
}

class ReplayAnalyzer {
  const ReplayAnalyzer._();

  /// A screen with this many or fewer pieces of text looks empty.
  static const int emptyTextThreshold = 2;

  /// How long a freshly opened screen may stay empty before it is worth a flag.
  static const int emptyGraceMs = 1500;

  /// Analyses [events] (already limited to the window of interest).
  static ReplayAnalysis analyze(List<ReplayEvent> events,
      {int slowFrameMs = 32, int maxTimeline = 120}) {
    final sorted = [...events]..sort((a, b) => a.t.compareTo(b.t));
    final findings = <String>[];
    final timeline = <Map<String, Object?>>[];

    final samples = sorted.where((e) => e.kind == 'sample').toList();
    final routes = sorted.where((e) => e.kind == 'route').toList();
    final slow = sorted.where((e) => e.kind == 'slow').toList();

    // ---- timeline: routes, list changes, slow frames ----
    for (final r in routes) {
      timeline.add(r.toJson());
    }
    int? lastTotal;
    for (final s in samples) {
      final total = _items(s);
      if (total != lastTotal) {
        timeline.add({'t': s.t, 'kind': 'list', 'items': total});
        lastTotal = total;
      }
    }
    for (final s in slow) {
      timeline.add(s.toJson());
    }
    timeline.sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));

    // ---- slow frames ----
    if (slow.isNotEmpty) {
      var worst = slow.first;
      for (final s in slow) {
        if (_ms(s) > _ms(worst)) worst = s;
      }
      findings.add('${slow.length} slow frame${slow.length == 1 ? '' : 's'} '
          '(over ${slowFrameMs}ms), worst ${_ms(worst)}ms at ${_at(worst.t)}.');
    }

    // ---- empty or slow screens after each page change ----
    final end = sorted.isEmpty ? 0 : sorted.last.t;
    for (var i = 0; i < routes.length; i++) {
      final r = routes[i];
      final action = r.data['action'];
      if (action != 'push' && action != 'replace') continue;
      final name = r.data['name'] ?? 'a page';
      final until = i + 1 < routes.length ? routes[i + 1].t : end;
      final after = samples.where((s) => s.t >= r.t && s.t <= until).toList();
      if (after.isEmpty) continue;

      final hasList =
          after.any((s) => (s.data['lists'] as List?)?.isNotEmpty ?? false);
      if (hasList) {
        final firstWithItems =
            after.where((s) => _items(s) > 0).cast<ReplayEvent?>().firstOrNull;
        if (firstWithItems == null) {
          final waited = until - r.t;
          if (waited >= emptyGraceMs) {
            findings.add('$name opened at ${_at(r.t)} and its list stayed '
                'empty for ${_secs(waited)} (to the end of the replay).');
          }
        } else {
          final wait = firstWithItems.t - r.t;
          if (wait >= emptyGraceMs) {
            findings.add('$name: its list was empty for ${_secs(wait)} after '
                'opening, then showed ${_items(firstWithItems)} items at '
                '${_at(firstWithItems.t)}.');
          }
          final steps = _steps(after);
          if (steps.length >= 3) {
            findings.add('$name: items arrived gradually '
                '(${steps.map((s) => s.$2).join(' → ')}) over '
                '${_secs(steps.last.$1 - steps.first.$1)}.');
          }
        }
      } else {
        // No list on this screen: judge by how much text it has.
        final firstFull = after
            .where((s) => _text(s) > emptyTextThreshold)
            .cast<ReplayEvent?>()
            .firstOrNull;
        final wait = (firstFull?.t ?? until) - r.t;
        if (wait >= emptyGraceMs) {
          findings.add(firstFull == null
              ? '$name looked empty (almost no text) for ${_secs(wait)} after '
                  'opening.'
              : '$name looked empty for ${_secs(wait)} after opening, content '
                  'appeared at ${_at(firstFull.t)}.');
        }
      }
    }

    if (timeline.length > maxTimeline) {
      timeline.removeRange(maxTimeline, timeline.length);
    }
    return ReplayAnalysis(findings, timeline);
  }

  static int _items(ReplayEvent s) {
    final lists = (s.data['lists'] as List?) ?? const [];
    return lists.fold<int>(0, (a, b) => a + (b as num).toInt());
  }

  static int _text(ReplayEvent s) => ((s.data['text'] as num?) ?? 0).toInt();

  static int _ms(ReplayEvent s) => ((s.data['ms'] as num?) ?? 0).toInt();

  /// Points where the item count changed upward: (time, count).
  static List<(int, int)> _steps(List<ReplayEvent> after) {
    final out = <(int, int)>[];
    var last = 0;
    for (final s in after) {
      final n = _items(s);
      if (n > last) {
        out.add((s.t, n));
        last = n;
      } else if (n < last) {
        last = n;
      }
    }
    return out;
  }

  static String _at(int ms) => '+${(ms / 1000).toStringAsFixed(1)}s';
  static String _secs(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';
}
