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
          'frames, no empty lists and no layout overflows.'
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
    final overflows = sorted.where((e) => e.kind == 'overflow').toList();

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

    // One timeline entry per place, with how many times it happened, instead of
    // the same line 36 times.
    final seen = <String, Map<String, Object?>>{};
    for (final o in overflows) {
      final key = '${o.data['file']}:${o.data['line']}:${o.data['widget']}';
      final existing = seen[key];
      if (existing == null) {
        final entry = o.toJson()..['count'] = 1;
        seen[key] = entry;
        timeline.add(entry);
      } else {
        existing['count'] = (existing['count'] as int) + 1;
        final amount = (o.data['amount'] as num?)?.toDouble() ?? 0;
        if (amount > ((existing['amount'] as num?)?.toDouble() ?? 0)) {
          existing['amount'] = amount;
        }
      }
    }
    timeline.sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));

    // ---- layout overflows: one finding per place, however often it repeats ----
    final byPlace = <String, List<ReplayEvent>>{};
    for (final o in overflows) {
      final key = '${o.data['file']}:${o.data['line']}:${o.data['widget']}';
      byPlace.putIfAbsent(key, () => []).add(o);
    }
    double worstOf(List<ReplayEvent> g) => g
        .map((e) => ((e.data['amount'] as num?) ?? 0).toDouble())
        .reduce((a, b) => a > b ? a : b);
    final groups = byPlace.values.toList()
      ..sort(
          (a, b) => worstOf(b).compareTo(worstOf(a))); // biggest overflow first
    for (final group in groups) {
      final first = group.first;
      final worst = group
          .map((e) => ((e.data['amount'] as num?) ?? 0).toDouble())
          .reduce((a, b) => a > b ? a : b);
      final px = worst == worst.roundToDouble()
          ? worst.toInt().toString()
          : worst.toStringAsFixed(1);
      final widget = first.data['widget'] as String?;
      final file = first.data['file'] as String?;
      final line = first.data['line'];
      final where = file == null
          ? ''
          : ' in ${widget ?? 'a widget'} at $file${line == null ? '' : ':$line'}';
      final times = group.length == 1 ? '' : ', seen ${group.length} times';
      findings.add('Layout overflow: ${first.data['edge']} edge overflowed by '
          '$px pixels$where (first at ${_at(first.t)}$times).');
    }

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
