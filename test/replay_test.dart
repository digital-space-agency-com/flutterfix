import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfix/flutterfix.dart';
import 'package:flutterfix/src/replay/probe.dart';
import 'package:flutterfix/src/replay/recorder.dart';

Future<ui.Image> tinyImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 12, 20),
      Paint()..color = const Color(0xFF3366CC));
  return recorder.endRecording().toImage(12, 20);
}

Widget listPage(ValueNotifier<int> items) => Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: items,
        builder: (_, n, __) => ListView.builder(
          itemCount: n,
          itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
        ),
      ),
    );

void main() {
  testWidgets('the probe counts list items and text on screen', (tester) async {
    final items = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(home: listPage(items)));

    var s = TreeProbe.sample(const Size(800, 600));
    expect(s.lists, [0]);
    expect(s.text, 0);

    items.value = 5;
    await tester.pump();
    s = TreeProbe.sample(const Size(800, 600));
    expect(s.lists.single, greaterThanOrEqualTo(5));
    expect(s.text, greaterThanOrEqualTo(5));
  });

  testWidgets('the probe ignores a page hidden behind the current one',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: Scaffold(
          body: ListView(
              children: [for (var i = 0; i < 5; i++) Text('under $i')])),
    ));
    key.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('on top')),
    ));
    await tester.pumpAndSettle();

    final s = TreeProbe.sample(const Size(800, 600));
    expect(s.text, 1, reason: 'only the top page counts');
    expect(s.lists, isEmpty);
  });

  testWidgets('the recorder notices a list that filled late', (tester) async {
    final image = (await tester.runAsync(tinyImage))!;
    final items = ValueNotifier(0);
    final key = GlobalKey<NavigatorState>();
    final sink = MemorySink();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [FlutterFixObserver()],
      builder: (context, child) => FlutterFix(
        sink: sink,
        replay: const ReplayConfig(fps: 4, rollingSeconds: 20),
        frameCapturer: (_) async => image.clone(),
        child: child!,
      ),
      home: const Scaffold(body: Text('Home')),
    ));

    key.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/liked'),
      builder: (_) => listPage(items),
    ));
    // 3 seconds of an empty list, then it fills.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    items.value = 8;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final replay =
        await tester.runAsync(() => ReplayRecorder.current!.snapshotRolling());
    expect(replay, isNotNull);
    expect(replay!.mode, 'rolling');
    expect(replay.frames, greaterThan(0));
    expect(replay.filmstripPng, isNotNull);
    expect(replay.summary, contains('/liked'));
    expect(replay.summary, contains('empty for'));
    expect(replay.timeline.map((e) => e['kind']), contains('route'));

    // Leave the widget tree so the recorder's timers stop.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a manual recording covers what happened since it started',
      (tester) async {
    final image = (await tester.runAsync(tinyImage))!;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FlutterFix(
        sink: MemorySink(),
        replay: const ReplayConfig(rolling: false),
        frameCapturer: (_) async => image.clone(),
        child: child!,
      ),
      home: const Scaffold(body: Text('Home')),
    ));
    final recorder = ReplayRecorder.current!;

    // Rolling is off, so nothing is kept until a recording starts.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    recorder.startManual();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final replay = await tester.runAsync(recorder.stopManual);

    expect(replay, isNotNull);
    expect(replay!.mode, 'manual');
    expect(replay.seconds, greaterThanOrEqualTo(1.5));
    expect(replay.frames, greaterThan(0));
    expect(recorder.manualActive, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('a replay survives the report JSON round trip', () {
    const replay = ReplayAttachment(
      mode: 'rolling',
      seconds: 10,
      frames: 12,
      summary: 'list was empty for 3.0s',
      timeline: [
        {'t': 100, 'kind': 'route', 'name': '/liked'},
      ],
      filmstripPng: [1, 2, 3],
    );
    final back = ReplayAttachment.fromJson(
        Map<String, dynamic>.from(replay.toJson(includeImage: true)));
    expect(back.summary, replay.summary);
    expect(back.timeline.single['name'], '/liked');
    expect(back.filmstripPng, [1, 2, 3]);
    expect(back.frames, 12);
  });
}
