import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfix/flutterfix.dart';

Widget app(MemorySink sink, {bool enabled = true}) => MaterialApp(
      builder: (context, child) => FlutterFix(
        enabled: enabled,
        sink: sink,
        appVersion: '1.0.0+1',
        screenName: () => 'Wallet',
        screenshotter: (_) async => Uint8List.fromList([1, 2, 3]),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: Fixable(
            'card',
            child: Container(
              width: 240,
              height: 120,
              color: Colors.blue,
              alignment: Alignment.center,
              child: Fixable('card.number', child: const Text('4242 4242')),
            ),
          ),
        ),
      ),
    );

void main() {
  optimisticTests();
  promptTests();
  stateTests();
  testWidgets('long press, type, send delivers a report with the element',
      (tester) async {
    final sink = MemorySink();
    await tester.pumpWidget(app(sink));

    await tester.longPress(find.text('4242 4242'));
    await tester.pumpAndSettle();
    expect(find.text('What is wrong here?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Number is too small');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(sink.reports, hasLength(1));
    final r = sink.reports.single;
    expect(r.comment, 'Number is too small');
    expect(r.element?.name, 'card.number'); // innermost mark wins
    expect(r.element?.texts, contains('4242 4242'));
    expect(r.screenName, 'Wallet');
    expect(r.appVersion, '1.0.0+1');
    expect(r.screenshotPng, [1, 2, 3]);
    expect(find.text('Sent r1 to Claude'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('pressing the card edge names the outer mark', (tester) async {
    final sink = MemorySink();
    await tester.pumpWidget(app(sink));

    final card = tester.getTopLeft(find.byType(Container).first);
    await tester.longPressAt(card + const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Corners');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(sink.reports.single.element?.name, 'card');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a normal tap still reaches the app and nothing is sent',
      (tester) async {
    final sink = MemorySink();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => FlutterFix(sink: sink, child: child!),
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
              onPressed: () => taps++, child: const Text('Tap me')),
        ),
      ),
    ));
    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('What is wrong here?'), findsNothing);
  });

  testWidgets('disabled returns the child untouched', (tester) async {
    final sink = MemorySink();
    await tester.pumpWidget(app(sink, enabled: false));
    await tester.longPress(find.text('4242 4242'));
    await tester.pumpAndSettle();
    expect(find.text('What is wrong here?'), findsNothing);
  });

  testWidgets('cancel sends nothing', (tester) async {
    final sink = MemorySink();
    await tester.pumpWidget(app(sink));
    await tester.longPress(find.text('4242 4242'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sink.reports, isEmpty);
    expect(find.text('What is wrong here?'), findsNothing);
  });

  test('Fixable records its call site in debug builds', () {
    final f = Fixable('x', child: const SizedBox());
    expect(f.location, isNotNull);
    expect(f.location, contains('flutterfix_test.dart'));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => count++),
        child: Text('count $count'),
      );
}

void stateTests() {
  testWidgets('the app keeps its state when the overlay switches on and off',
      (tester) async {
    Future<void> show(bool enabled) => tester.pumpWidget(MaterialApp(
          builder: (context, child) =>
              FlutterFix(enabled: enabled, sink: MemorySink(), child: child!),
          home: const Scaffold(body: Center(child: _Counter())),
        ));

    await show(false);
    await tester.tap(find.byType(TextButton));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('count 2'), findsOneWidget);

    await show(true);
    expect(find.text('count 2'), findsOneWidget, reason: 'overlay switched on');
    await show(false);
    expect(find.text('count 2'), findsOneWidget,
        reason: 'overlay switched off');
  });

  testWidgets('the app keeps its state while the comment box opens and closes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: MemorySink(),
        screenshotter: (_) async => null,
        child: child!,
      ),
      home: const Scaffold(body: Center(child: _Counter())),
    ));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    await tester.longPress(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('What is wrong here?'), findsOneWidget);
    expect(find.text('count 1'), findsOneWidget, reason: 'while open');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget, reason: 'after closing');
  });
}

void promptTests() {
  testWidgets(
      'the comment box opens at once, even while the screenshot is slow',
      (tester) async {
    final shot = Completer<Uint8List?>();
    final sink = MemorySink();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: sink,
        screenshotter: (_) => shot.future,
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('Hello'))),
    ));

    await tester.longPress(find.text('Hello'));
    await tester.pump();
    expect(find.text('What is wrong here?'), findsOneWidget,
        reason: 'no waiting for the screenshot');
    expect(sink.reports, isEmpty);

    // Type and send while the screenshot is still being taken: the report
    // waits for it, then goes out with it.
    await tester.enterText(find.byType(TextField), 'Looks off');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(sink.reports, isEmpty, reason: 'waiting for the screenshot');

    shot.complete(Uint8List.fromList([7, 7, 7]));
    await tester.pumpAndSettle();
    expect(sink.reports, hasLength(1));
    expect(sink.reports.single.screenshotPng, [7, 7, 7]);
    expect(sink.reports.single.comment, 'Looks off');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('cancelling before the screenshot arrives is harmless',
      (tester) async {
    final shot = Completer<Uint8List?>();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: MemorySink(),
        screenshotter: (_) => shot.future,
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('Hello'))),
    ));
    await tester.longPress(find.text('Hello'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    shot.complete(Uint8List.fromList([1]));
    await tester.pumpAndSettle();
    expect(find.text('What is wrong here?'), findsNothing);
  });
}

/// A sink that stays "busy" until the test lets it finish.
class _SlowSink extends FlutterFixSink {
  final done = Completer<FixSendResult>();
  final sent = <FixReport>[];
  @override
  Future<FixSendResult> send(FixReport report) {
    sent.add(report);
    return done.future;
  }
}

void optimisticTests() {
  testWidgets('Send closes the box at once and the upload carries on behind it',
      (tester) async {
    final sink = _SlowSink();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: sink,
        screenshotter: (_) async => Uint8List.fromList([1]),
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('Hello'))),
    ));

    await tester.longPress(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Looks off');
    await tester.tap(find.text('Send'));
    await tester.pump();

    // The box is gone while the sink is still working.
    expect(find.text('What is wrong here?'), findsNothing);
    expect(find.text('Sending…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Sending…'), findsOneWidget,
        reason: 'the banner stays up while the upload is in progress');

    sink.done.complete(const FixSendResult.ok('#7'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sent #7 to Claude'), findsOneWidget);
    expect(sink.sent.single.comment, 'Looks off');
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Sent #7 to Claude'), findsNothing);
  });

  testWidgets(
      'a failure that cannot be retried stays on screen long enough to read',
      (tester) async {
    final sink = _SlowSink();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: sink,
        screenshotter: (_) async => null,
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('Hello'))),
    ));
    await tester.longPress(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('Send'));
    await tester.pump();
    sink.done.complete(const FixSendResult.failed('Not allowed to send reports',
        retryable: false));
    await tester.pump();
    expect(find.text('Not allowed to send reports'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Not allowed to send reports'), findsOneWidget,
        reason: 'errors stay up for 6 seconds, not 3');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Not allowed to send reports'), findsNothing);
  });
}
