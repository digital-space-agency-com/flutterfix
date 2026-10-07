import 'dart:async';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'filmstrip.dart';
import 'probe.dart';
import 'replay_analyzer.dart';
import 'replay_models.dart';

/// Takes a frame of the app (already scaled down).
typedef FrameCapturer = Future<ui.Image?> Function(double width);

class _Frame {
  _Frame(this.t, this.image);
  final int t;
  final ui.Image image;
}

/// Watches the app while it is enabled: keeps the last few seconds of small
/// frames and an event log (page changes, how many items lists show, slow
/// frames), and turns them into a [ReplayAttachment] on request.
class ReplayRecorder with WidgetsBindingObserver {
  ReplayRecorder({
    required this.config,
    required this.capturer,
    required this.screenSize,
    this.screenName,
    this.onManualTimeout,
  });

  /// The recorder in use, so a `FlutterFixObserver` can reach it.
  static ReplayRecorder? current;

  final ReplayConfig config;
  final FrameCapturer capturer;
  final Size Function() screenSize;
  final String? Function()? screenName;
  final VoidCallback? onManualTimeout;

  // package:clock follows the test framework's simulated time too.
  final Stopwatch _clock = clock.stopwatch()..start();
  final List<_Frame> _frames = [];
  final List<ReplayEvent> _events = [];
  Timer? _timer;
  Timer? _manualTimer;
  bool _capturing = false;
  bool _dirty = true;
  bool _resumed = true;
  int _lastFrameT = -100000;
  int? _manualStart;
  String? _lastScreen;

  int get nowMs => _clock.elapsedMilliseconds;
  bool get manualActive => _manualStart != null;
  int get manualSeconds => manualActive ? (nowMs - _manualStart!) ~/ 1000 : 0;

  void start() {
    current = this;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(
        Duration(milliseconds: (1000 / config.fps).round()), (_) => _tick());
  }

  void dispose() {
    if (current == this) current = null;
    _timer?.cancel();
    _manualTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    for (final f in _frames) {
      f.image.dispose();
    }
    _frames.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
  }

  bool get _active => config.rolling || manualActive;

  void _onTimings(List<FrameTiming> timings) {
    _dirty = true;
    if (!_active) return;
    for (final t in timings) {
      final total = t.totalSpan.inMilliseconds;
      if (total > config.slowFrameMs) {
        _events.add(ReplayEvent(nowMs, 'slow', {
          'ms': total,
          'build': t.buildDuration.inMilliseconds,
          'raster': t.rasterDuration.inMilliseconds,
        }));
      }
    }
  }

  /// A page opened or closed. Called by `FlutterFixObserver`.
  void noteRoute(String action, String? name, String? previous) {
    if (!_active) return;
    _events.add(ReplayEvent(nowMs, 'route', {
      'action': action,
      'name': name ?? 'a page',
      if (previous != null) 'previous': previous,
    }));
  }

  Future<void> _tick() async {
    if (!_resumed || !_active) {
      _evict();
      return;
    }
    // A page change reported through screenName counts as a route event too.
    final name = screenName?.call();
    if (name != null && name != _lastScreen) {
      if (_lastScreen != null) noteRoute('push', name, _lastScreen);
      _lastScreen = name;
    }

    final t = nowMs;
    final s = TreeProbe.sample(screenSize());
    _events.add(ReplayEvent(t, 'sample', {'text': s.text, 'lists': s.lists}));

    final stale = t - _lastFrameT > 1500;
    if ((_dirty || stale) && !_capturing) {
      _capturing = true;
      _dirty = false;
      try {
        final image = await capturer(config.frameWidth.toDouble());
        if (image != null) {
          _frames.add(_Frame(t, image));
          _lastFrameT = t;
        }
      } catch (_) {
        // A frame that cannot be taken is simply missing from the strip.
      } finally {
        _capturing = false;
      }
    }
    _evict();
  }

  void _evict() {
    final keepMs = manualActive
        ? (nowMs - _manualStart!) + 1000
        : config.rollingSeconds * 1000;
    final cutoff = nowMs - keepMs;
    while (_frames.isNotEmpty && _frames.first.t < cutoff) {
      _frames.removeAt(0).image.dispose();
    }
    _events.removeWhere((e) => e.t < cutoff);
  }

  /// The last [ReplayConfig.rollingSeconds], as a report attachment.
  Future<ReplayAttachment?> snapshotRolling() => _compose(
        'rolling',
        (nowMs - config.rollingSeconds * 1000).clamp(0, nowMs),
      );

  void startManual() {
    _manualStart = nowMs;
    _manualTimer?.cancel();
    _manualTimer = Timer(Duration(seconds: config.maxManualSeconds), () {
      onManualTimeout?.call();
    });
  }

  /// Stops a manual recording and returns it.
  Future<ReplayAttachment?> stopManual() async {
    final from = _manualStart;
    _manualTimer?.cancel();
    if (from == null) return null;
    // One last frame so the strip ends on what you were looking at.
    _dirty = true;
    await _tick();
    final result = await _compose('manual', from);
    _manualStart = null;
    return result;
  }

  Future<ReplayAttachment?> _compose(String mode, int from) async {
    final end = nowMs;
    final frames = _frames.where((f) => f.t >= from).toList();
    final events = _events
        .where((e) => e.t >= from)
        .map((e) => ReplayEvent(e.t - from, e.kind, e.data))
        .toList();
    if (frames.isEmpty && events.isEmpty) return null;

    final analysis =
        ReplayAnalyzer.analyze(events, slowFrameMs: config.slowFrameMs);
    final seconds = (end - from) / 1000;

    // Clones, because the buffer may drop its images while we are composing.
    final chosen = Filmstrip.pick(frames);
    final clones = [
      for (final f in chosen) FilmFrame(f.t - from, f.image.clone())
    ];
    List<int>? png;
    try {
      png = await Filmstrip.compose(clones);
    } finally {
      for (final c in clones) {
        c.image.dispose();
      }
    }

    return ReplayAttachment(
      mode: mode,
      seconds: double.parse(seconds.toStringAsFixed(1)),
      frames: frames.length,
      summary: analysis.summaryFor(seconds),
      timeline: analysis.timeline,
      filmstripPng: png,
    );
  }
}
