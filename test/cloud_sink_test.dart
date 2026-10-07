import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfix/flutterfix.dart';

FixReport sample([String comment = 'Too small']) => FixReport(
      comment: comment,
      element: const ElementInfo(
        rect: Rect.fromLTWH(10, 20, 100, 40),
        kind: 'RenderParagraph',
        name: 'card.number',
        location: 'lib/card.dart:12',
        texts: ['4242'],
        nearbyTexts: ['Alex'],
        creatorChain: 'Text ← Row',
      ),
      touch: const Offset(15, 25),
      screenSize: const Size(390, 844),
      screenName: 'Wallet',
      appVersion: '1.0.0+1',
      platform: 'iOS',
      screenshotPng: [1, 2, 3, 4],
      extra: const {'user': 'tester'},
    );

/// A tiny server that answers with [status] and remembers what it received.
class FakeServer {
  FakeServer(this.status);
  int status;
  final received = <Map<String, dynamic>>[];
  final headers = <HttpHeaders>[];
  late HttpServer server;

  Future<Uri> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      if (status < 300) {
        received.add(jsonDecode(body) as Map<String, dynamic>);
        headers.add(req.headers);
      }
      req.response
        ..statusCode = status
        ..write(jsonEncode({'id': 'issue-${received.length}'}));
      await req.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/report');
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  test('FixReport survives a JSON round trip, screenshot included', () {
    final back = FixReport.fromJson(
        jsonDecode(jsonEncode(sample().toJson(includeScreenshot: true)))
            as Map<String, dynamic>);
    expect(back.comment, 'Too small');
    expect(back.element?.name, 'card.number');
    expect(back.element?.rect, const Rect.fromLTWH(10, 20, 100, 40));
    expect(back.screenshotPng, [1, 2, 3, 4]);
    expect(back.extra, {'user': 'tester'});
  });

  group('HttpSink', () {
    test('posts the report with headers and reads the id', () async {
      final fake = FakeServer(200);
      final url = await fake.start();
      final sink =
          HttpSink(url, headers: () async => {'Authorization': 'Bearer abc'});
      final result = await sink.send(sample());
      await fake.stop();

      expect(result.ok, isTrue);
      expect(result.id, 'issue-1');
      expect(fake.received.single['comment'], 'Too small');
      expect(fake.received.single['screenshotPngBase64'],
          base64Encode([1, 2, 3, 4]));
      expect(fake.headers.single.value('authorization'), 'Bearer abc');
    });

    test('401 is final, 503 may be retried', () async {
      final fake = FakeServer(401);
      final url = await fake.start();
      final denied = await HttpSink(url).send(sample());
      fake.status = 503;
      final busy = await HttpSink(url).send(sample());
      await fake.stop();
      expect(denied.ok, isFalse);
      expect(denied.retryable, isFalse);
      expect(busy.ok, isFalse);
      expect(busy.retryable, isTrue);
    });

    test('an unreachable server is retryable', () async {
      final result =
          await HttpSink(Uri.parse('http://127.0.0.1:1/report')).send(sample());
      expect(result.ok, isFalse);
      expect(result.retryable, isTrue);
    });
  });

  group('OutboxSink', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('flutterfix_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves when offline and delivers once back online', () async {
      final fake = FakeServer(503);
      final url = await fake.start();
      final outbox = OutboxSink(HttpSink(url), dir: dir);

      final first = await outbox.send(sample('one'));
      final second = await outbox.send(sample('two'));
      expect(first.queued, isTrue);
      expect(second.queued, isTrue);
      expect(outbox.pendingCount, 2);

      fake.status = 200;
      await outbox.flush();
      await fake.stop();

      expect(outbox.pendingCount, 0);
      expect(fake.received.map((r) => r['comment']), ['one', 'two']);
      expect(fake.received.first['screenshotPngBase64'],
          base64Encode([1, 2, 3, 4]));
    });

    test('keeps everything while still offline', () async {
      final outbox = OutboxSink(
          HttpSink(Uri.parse('http://127.0.0.1:1/report')),
          dir: dir);
      await outbox.send(sample());
      await outbox.flush();
      expect(outbox.pendingCount, 1);
    });

    test('does not keep reports the server refuses for good', () async {
      final fake = FakeServer(401);
      final url = await fake.start();
      final outbox = OutboxSink(HttpSink(url), dir: dir);
      final result = await outbox.send(sample());
      await fake.stop();
      expect(result.ok, isFalse);
      expect(outbox.pendingCount, 0);
    });

    test('keeps at most maxItems, dropping the oldest', () async {
      final outbox = OutboxSink(
          HttpSink(Uri.parse('http://127.0.0.1:1/report')),
          dir: dir,
          maxItems: 2);
      for (final c in ['a', 'b', 'c']) {
        await outbox.send(sample(c));
      }
      expect(outbox.pendingCount, 2);
    });
  });
}
