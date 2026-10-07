import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfix/flutterfix.dart';
import 'package:flutterfix/src/replay/filmstrip.dart';
import 'package:flutterfix/src/replay/overflow_parser.dart';
import 'package:flutterfix/src/replay/recorder.dart';
import 'package:flutterfix/src/replay/replay_analyzer.dart';
import 'package:flutterfix/src/replay/replay_models.dart';

/// The text Flutter printed for a real overflow in ReelMatch's card.
const realError = '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 156 pixels on the bottom.

The relevant error-causing widget was:
  Column
  Column:file:///Users/dave/Development/02_personal/01_reelmatch/reelmatch_project/lib/screens/home/card_front.dart:418:26

To inspect this widget in Flutter DevTools, visit:
''';

void main() {
  group('OverflowParser', () {
    test('reads the size, edge, widget, file and line from a real error', () {
      final o = OverflowParser.parse(
          'A RenderFlex overflowed by 156 pixels on the bottom.', realError)!;
      expect(o['amount'], 156);
      expect(o['edge'], 'bottom');
      expect(o['widget'], 'Column');
      expect(o['file'], 'lib/screens/home/card_front.dart');
      expect(o['line'], 418);
    });

    test('handles fractions and other edges', () {
      final o = OverflowParser.parse(
          'A RenderFlex overflowed by 12.5 pixels on the right.', '')!;
      expect(o['amount'], 12.5);
      expect(o['edge'], 'right');
      expect(o.containsKey('file'), isFalse);
    });

    test('ignores errors that are not overflows', () {
      expect(
          OverflowParser.parse('Null check operator used on a null value', ''),
          isNull);
    });
  });

  group('analysis', () {
    test('one finding per place, with the worst size and the count', () {
      final a = ReplayAnalyzer.analyze([
        const ReplayEvent(2100, 'overflow', {
          'amount': 156.0,
          'edge': 'bottom',
          'widget': 'Column',
          'file': 'lib/card.dart',
          'line': 418
        }),
        const ReplayEvent(2400, 'overflow', {
          'amount': 188.0,
          'edge': 'bottom',
          'widget': 'Column',
          'file': 'lib/card.dart',
          'line': 418
        }),
        const ReplayEvent(2600, 'overflow', {
          'amount': 20.0,
          'edge': 'right',
          'widget': 'Row',
          'file': 'lib/other.dart',
          'line': 9
        }),
      ]);
      expect(a.findings, hasLength(2));
      expect(a.findings.first,
          'Layout overflow: bottom edge overflowed by 188 pixels in Column at lib/card.dart:418 (first at +2.1s, seen 2 times).');
      expect(a.findings.last, contains('lib/other.dart:9'));
      expect(a.timeline.where((e) => e['kind'] == 'overflow'), hasLength(3));
    });
  });

  group('film strip picking', () {
    final frames = [for (var i = 0; i < 100; i++) i * 100]; // one every 100 ms

    test(
        'keeps frames around a page change that evenly spaced picks would miss',
        () {
      final plain = Filmstrip.pick(frames);
      final key = Filmstrip.pickKey<int>(frames, (t) => t, anchors: [5030]);
      expect(key.length, 12);
      expect(key.first, 0);
      expect(key.last, 9900);
      expect(key, containsAll([5000, 5100, 5200]));
      expect(plain.contains(5100), isFalse, reason: 'even spacing misses it');
      expect(key, orderedEquals([...key]..sort()));
    });

    test('with many anchors it still returns at most max frames', () {
      final key = Filmstrip.pickKey<int>(frames, (t) => t,
          anchors: [for (var i = 1; i < 20; i++) i * 450]);
      expect(key.length, lessThanOrEqualTo(12));
      expect(key.first, 0);
      expect(key.last, 9900);
    });

    test('a short recording is returned whole', () {
      expect(
          Filmstrip.pickKey<int>([1, 2, 3], (t) => t, anchors: [2]), [1, 2, 3]);
    });
  });

  testWidgets('a real overflow in a running app shows up in the replay',
      (tester) async {
    final oldOnError = FlutterError.onError;
    final reported = <FlutterErrorDetails>[];
    FlutterError.onError =
        reported.add; // what the app (or the test) already had

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: MemorySink(),
        replay: const ReplayConfig(),
        frameCapturer: (_) async => null,
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));
    final recorder = ReplayRecorder.current!;
    await tester.pump(const Duration(seconds: 1));

    // A column that is too tall for its box: Flutter reports an overflow.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: MemorySink(),
        replay: const ReplayConfig(),
        frameCapturer: (_) async => null,
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          height: 50,
          child: Column(children: [
            for (var i = 0; i < 6; i++)
              const SizedBox(height: 40, child: Text('row')),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    final replay =
        await tester.runAsync(() => ReplayRecorder.current!.snapshotRolling());
    expect(recorder, isNotNull);
    expect(replay, isNotNull);
    expect(replay!.summary, contains('Layout overflow'));
    expect(replay.summary, contains('bottom edge overflowed by'));
    expect(replay.timeline.any((e) => e['kind'] == 'overflow'), isTrue);
    // The app's own handler still saw the error.
    expect(reported.any((d) => d.exceptionAsString().contains('overflowed')),
        isTrue);

    await tester.pumpWidget(const SizedBox());
    FlutterError.onError = oldOnError;
  });
}
