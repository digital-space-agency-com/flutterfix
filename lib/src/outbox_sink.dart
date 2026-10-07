import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'report.dart';
import 'sink.dart';

/// A sink that can hold on to reports and send them later.
abstract interface class FlushableSink {
  /// Tries to send anything that was saved. Safe to call often.
  Future<void> flush();
}

/// Wraps another sink. If sending fails for a reason that may pass (no signal,
/// server busy), the report is saved in [dir] and sent automatically later:
/// on the next app start, when the app returns to the foreground, and after
/// the next successful send. Reports the server refuses for good (not
/// allowed, bad request) are not kept.
///
/// [dir] should be somewhere private and persistent, for example
/// `await getApplicationSupportDirectory()` from `path_provider`.
class OutboxSink extends FlutterFixSink implements FlushableSink {
  OutboxSink(this.inner, {required this.dir, this.maxItems = 20});

  final FlutterFixSink inner;
  final Directory dir;

  /// Oldest reports are dropped beyond this many, so the folder cannot grow
  /// without limit.
  final int maxItems;

  bool _flushing = false;

  @override
  Future<FixSendResult> send(FixReport report) async {
    final result = await inner.send(report);
    if (result.ok || !result.retryable) return result;
    try {
      await _save(report);
    } catch (e) {
      debugPrint('OutboxSink: could not save report: $e');
      return result;
    }
    return const FixSendResult.queued(
        'No connection. Saved on this phone and will be sent automatically.');
  }

  @override
  Future<void> flush() async {
    if (_flushing || !dir.existsSync()) return;
    _flushing = true;
    try {
      for (final file in _pending()) {
        FixReport report;
        try {
          report = FixReport.fromJson(
              jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        } catch (_) {
          await file.delete(); // unreadable, drop it
          continue;
        }
        final result = await inner.send(report);
        if (result.ok || !result.retryable) {
          await file.delete();
        } else {
          break; // still offline: keep the rest, try again later
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// How many reports are waiting. For tests and a "N waiting" indicator.
  int get pendingCount => dir.existsSync() ? _pending().length : 0;

  List<File> _pending() {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.flutterfix.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _save(FixReport report) async {
    await dir.create(recursive: true);
    final stamp =
        DateTime.now().microsecondsSinceEpoch.toString().padLeft(20, '0');
    await File('${dir.path}/$stamp.flutterfix.json')
        .writeAsString(jsonEncode(report.toJson(includeScreenshot: true)));
    final files = _pending();
    for (var i = 0; i < files.length - maxItems; i++) {
      await files[i].delete();
    }
  }
}
