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
