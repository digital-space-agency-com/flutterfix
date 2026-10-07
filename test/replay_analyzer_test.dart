import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfix/src/replay/replay_analyzer.dart';
import 'package:flutterfix/src/replay/replay_models.dart';

ReplayEvent route(int t, String name, [String action = 'push']) =>
    ReplayEvent(t, 'route', {'action': action, 'name': name});

ReplayEvent sample(int t, {List<int> lists = const [], int text = 10}) =>
    ReplayEvent(t, 'sample', {'lists': lists, 'text': text});

ReplayEvent slow(int t, int ms) => ReplayEvent(t, 'slow', {'ms': ms});

void main() {
  test('a quiet replay says nothing stood out', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/home'),
      for (var t = 0; t <= 2000; t += 250) sample(t, lists: [12]),
    ]);
    expect(a.findings, isEmpty);
    expect(a.summaryFor(2), contains('Nothing stood out'));
  });

  test('reports slow frames with the worst one', () {
    final a = ReplayAnalyzer.analyze([
      sample(0),
      slow(500, 40),
      slow(1200, 180),
      slow(2000, 60),
    ]);
    expect(a.findings.single, contains('3 slow frames'));
    expect(a.findings.single, contains('worst 180ms at +1.2s'));
  });

  test('flags a list that stayed empty after the page opened', () {
    final a = ReplayAnalyzer.analyze([
      route(1000, '/liked'),
      for (var t = 1000; t <= 6000; t += 250) sample(t, lists: [0], text: 3),
    ]);
    expect(a.findings.single, contains('/liked opened at +1.0s'));
    expect(a.findings.single, contains('stayed empty'));
  });

  test('flags a list that filled in late, and says when', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/liked'),
      for (var t = 0; t < 3000; t += 250) sample(t, lists: [0]),
      for (var t = 3000; t <= 4000; t += 250) sample(t, lists: [8]),
    ]);
    expect(a.findings.single, contains('empty for 3.0s after opening'));
    expect(a.findings.single, contains('8 items at +3.0s'));
  });

  test('a list that fills within the grace period is fine', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/liked'),
      sample(0, lists: [0]),
      sample(500, lists: [0]),
      sample(1000, lists: [8]),
    ]);
    expect(a.findings, isEmpty);
  });

  test('notices items arriving in several steps', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/feed'),
      sample(0, lists: [0]),
      sample(250, lists: [4]),
      sample(1000, lists: [9]),
      sample(2200, lists: [15]),
      sample(3000, lists: [15]),
    ]);
    expect(a.findings.join(' '), contains('arrived gradually (4 → 9 → 15)'));
  });

  test('a page with no list but almost no text looks empty', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/profile'),
      for (var t = 0; t <= 4000; t += 500) sample(t, text: 1),
    ]);
    expect(a.findings.single, contains('/profile looked empty'));
  });

  test('a page whose text appears late is reported with the time', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/profile'),
      for (var t = 0; t < 2500; t += 500) sample(t, text: 1),
      sample(2500, text: 14),
      sample(3000, text: 14),
    ]);
    expect(a.findings.single, contains('content appeared at +2.5s'));
  });

  test('pops are not treated as screens opening', () {
    final a = ReplayAnalyzer.analyze([
      route(0, '/a', 'pop'),
      for (var t = 0; t <= 4000; t += 500) sample(t, text: 0),
    ]);
    expect(a.findings, isEmpty);
  });

  test('the timeline lists routes, list changes and slow frames in order', () {
    final a = ReplayAnalyzer.analyze([
      slow(900, 50),
      route(100, '/x'),
      sample(100, lists: [0]),
      sample(350, lists: [0]),
      sample(600, lists: [5]),
    ]);
    expect(a.timeline.map((e) => e['kind']), ['route', 'list', 'list', 'slow']);
    expect(a.timeline.map((e) => e['t']), [100, 100, 600, 900]);
  });
}
