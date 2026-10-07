import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'report.dart';

/// Where a report goes. Implement this to send reports somewhere else (a
/// Firebase function, a GitHub issue, a chat message, ...).
abstract class FixLensSink {
  const FixLensSink();

  Future<FixSendResult> send(FixReport report);
}

/// Sends to the receiver that runs next to Claude Code on your Mac
/// (`dart run fixlens:receiver`). Works from the iOS simulator and the Android
/// emulator; for a real phone on the same Wi-Fi pass the Mac's address as [host].
class LocalReceiverSink extends FixLensSink {
  const LocalReceiverSink({this.host, this.port = 4747});

  /// Defaults to 10.0.2.2 on Android (the emulator's name for the Mac) and
  /// 127.0.0.1 elsewhere.
  final String? host;
  final int port;

  String get _host =>
      host ??
      (defaultTargetPlatform == TargetPlatform.android
          ? '10.0.2.2'
          : '127.0.0.1');

  @override
  Future<FixSendResult> send(FixReport report) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.post(_host, port, '/report');
      request.headers.contentType = ContentType.json;
      final body = report.toJson()
        ..['screenshotPngBase64'] = report.screenshotPng == null
            ? null
            : base64Encode(report.screenshotPng!);
      request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        return FixSendResult.failed('Receiver said ${response.statusCode}');
      }
      final id = (jsonDecode(text) as Map)['id'] as String?;
      return FixSendResult.ok(id ?? '?');
    } on SocketException {
      return const FixSendResult.failed(
          'Could not reach the receiver. Run: dart run fixlens:receiver');
    } on TimeoutException {
      return const FixSendResult.failed('The receiver took too long to answer');
    } catch (e) {
      return FixSendResult.failed('$e');
    } finally {
      client.close(force: true);
    }
  }
}

/// Keeps reports in memory. For tests and demos.
class MemorySink extends FixLensSink {
  MemorySink();

  final List<FixReport> reports = [];

  @override
  Future<FixSendResult> send(FixReport report) async {
    reports.add(report);
    return FixSendResult.ok('r${reports.length}');
  }
}
