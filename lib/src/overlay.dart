import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'capture.dart';
import 'inspect.dart';
import 'outbox_sink.dart';
import 'replay/recorder.dart';
import 'replay/replay_models.dart';
import 'report.dart';
import 'sink.dart';

/// Wrap the app with this (in `MaterialApp.builder`) to let people long press
/// any element and send a report.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => FlutterFix(
///     enabled: kDebugMode,
///     sink: const LocalReceiverSink(),
///     child: child!,
///   ),
/// )
/// ```
///
/// When [enabled] is false the child is returned unchanged, so a release build
/// pays nothing. For internal test builds, pass a flag you control (Remote
/// Config, a signed-in tester list, ...).
class FlutterFix extends StatefulWidget {
  const FlutterFix({
    super.key,
    required this.child,
    required this.sink,
    this.enabled = kDebugMode,
    this.screenName,
    this.appVersion,
    this.extra,
    this.holdDuration = const Duration(milliseconds: 600),
    this.replay,
    @visibleForTesting this.screenshotter,
    @visibleForTesting this.frameCapturer,
  });

  final Widget child;
  final FlutterFixSink sink;
  final bool enabled;

  /// Name of the screen on display, e.g. from your router. Sent with reports.
  final String? Function()? screenName;

  /// Sent with reports so you know which build the problem is in.
  final String? appVersion;

  /// Extra values attached to every report.
  final Map<String, String> Function()? extra;

  final Duration holdDuration;

  /// Turn on the replay: the last few seconds of the screen are kept so a
  /// report made after something went wrong shows what happened, and you can
  /// record a flow by hand. Off when null. See [ReplayConfig].
  final ReplayConfig? replay;

  final Future<Uint8List?> Function(Rect? highlight)? screenshotter;

  final FrameCapturer? frameCapturer;

  @override
  State<FlutterFix> createState() => _FlutterFixState();
}

class _FlutterFixState extends State<FlutterFix> with WidgetsBindingObserver {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _appKey = GlobalKey();
  ElementInfo? _element;
  Offset _touch = Offset.zero;
  Uint8List? _screenshot;
  bool _composing = false;
  bool _sending = false;
  String? _banner;
  bool _bannerError = false;
  bool _bannerInfo = false;
  Timer? _bannerTimer;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ValueNotifier<int> _tick = ValueNotifier(0);
  int _session = 0;

  ReplayRecorder? _recorder;
  ReplayAttachment? _replay;
  bool _attachReplay = true;
  bool _recording = false;
  bool _preparing = false;
  Future<void>? _prepared;
  Timer? _recTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUpRecorder();
    _flush();
  }

  /// Starts or stops the replay recorder to match the current settings. Called
  /// at start and whenever `enabled` or `replay` changes, for example when a
  /// tester signs in after the app has launched.
  void _setUpRecorder() {
    final wanted = widget.enabled && widget.replay != null;
    if (!wanted) {
      _recorder?.dispose();
      _recorder = null;
      _replay = null;
      return;
    }
    if (_recorder != null) return;
    _recorder = ReplayRecorder(
      config: widget.replay!,
      capturer: widget.frameCapturer ?? _captureFrame,
      screenSize: _screenSize,
      screenName: widget.screenName,
      onManualTimeout: () {
        if (_recording) _stopRecording();
      },
    )..start();
  }

  @override
  void didUpdateWidget(FlutterFix old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled || old.replay != widget.replay) {
      if (old.replay != widget.replay) {
        _recorder?.dispose();
        _recorder = null;
      }
      _setUpRecorder();
      if (!widget.enabled) {
        _composing = false;
        _recording = false;
      } else if (!old.enabled) {
        _flush();
      }
    }
  }

  RenderRepaintBoundary? get _boundary =>
      _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

  Size _screenSize() => _boundary?.size ?? Size.zero;

  Future<ui.Image?> _captureFrame(double width) async {
    final b = _boundary;
    if (b == null || !b.hasSize || b.size.width <= 0) return null;
    return b.toImage(pixelRatio: width / b.size.width);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _tick.value++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flush();
  }

  /// Sends reports that were saved while there was no connection.
  void _flush() {
    final sink = widget.sink;
    if (widget.enabled && sink is FlushableSink) {
      unawaited((sink as FlushableSink).flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recorder?.dispose();
    _recTicker?.cancel();
    _bannerTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> _onLongPress(LongPressStartDetails d) async {
    if (_composing || _sending || _recording) return;
    final screen = MediaQuery.sizeOf(context);
    final info = Inspector.inspect(context, d.globalPosition, screen);
    HapticFeedback.mediumImpact();

    // Take the screenshot and the replay of the last seconds right away, but
    // show the comment box straight away: they finish while you type.
    final recorder = _recorder;
    final shotF = _capture(info?.rect);
    final replayF = recorder != null && recorder.config.rolling
        ? recorder.snapshotRolling()
        : Future<ReplayAttachment?>.value(null);

    setState(() {
      _touch = d.globalPosition;
      _element = info;
      _screenshot = null;
      _replay = null;
      _attachReplay = false;
      _preparing = true;
      _composing = true;
      _session++;
      _text.clear();
    });
    final session = _session;
    _prepared = _finishPreparing(session, shotF, replayF);
  }

  Future<void> _finishPreparing(int session, Future<Uint8List?> shotF,
      Future<ReplayAttachment?> replayF) async {
    Uint8List? shot;
    ReplayAttachment? replay;
    try {
      shot = await shotF;
    } catch (_) {}
    try {
      replay = await replayF;
    } catch (_) {}
    if (!mounted || session != _session) return;
    _screenshot = shot;
    _replay = replay;
    _attachReplay = replay != null;
    _preparing = false;
    _refresh();
  }

  Future<Uint8List?> _capture(Rect? rect) async {
    if (widget.screenshotter != null) return widget.screenshotter!(rect);
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    return captureScreenshot(boundary, rect);
  }

  void _cancel() => setState(() => _composing = false);

  void _startRecording() {
    _recorder?.startManual();
    setState(() {
      _composing = false;
      _recording = true;
    });
    _recTicker?.cancel();
    _recTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recTicker?.cancel();
    final replayF =
        _recorder?.stopManual() ?? Future<ReplayAttachment?>.value(null);
    final shotF = _capture(null);
    setState(() {
      _recording = false;
      _element = null;
      _touch = Offset.zero;
      _screenshot = null;
      _replay = null;
      _attachReplay = false;
      _preparing = true;
      _composing = true;
      _session++;
      _text.clear();
    });
    _prepared = _finishPreparing(_session, shotF, replayF);
  }

  Future<void> _send() async {
    final comment = _text.text.trim();
    if (comment.isEmpty || _sending) return;
    final size = MediaQuery.sizeOf(context);
    setState(() => _sending = true);
    _tick.value++;
    if (_preparing) await _prepared;
    if (!mounted) return;
    final report = FixReport(
      comment: comment,
      element: _element,
      touch: _touch,
      screenSize: size,
      screenName: widget.screenName?.call(),
      appVersion: widget.appVersion,
      platform: defaultTargetPlatform.name,
      screenshotPng: _screenshot,
      replay: _attachReplay ? _replay : null,
      extra: widget.extra?.call() ?? const {},
    );
    final result = await widget.sink.send(report);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _composing = false;
    });
    _showBanner(
      result.queued
          ? (result.message ?? 'Saved. Will send when online.')
          : result.ok
              ? 'Sent ${result.id ?? ''} to Claude'
              : (result.message ?? 'Send failed'),
      error: !result.ok,
      info: result.queued,
    );
    if (result.ok && !result.queued) _flush();
  }

  void _showBanner(String text, {required bool error, bool info = false}) {
    _bannerTimer?.cancel();
    setState(() {
      _banner = text;
      _bannerError = error;
      _bannerInfo = info;
    });
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The app sits under a GlobalKey so Flutter can move it between the
    // positions below without rebuilding it: switching the overlay on or off,
    // or opening the comment box, must never reset the app's own state.
    final app = KeyedSubtree(key: _appKey, child: widget.child);
    if (!widget.enabled) return app;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: {
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: widget.holdDuration),
                (r) => r.onLongPressStart = _onLongPress,
              ),
            },
            child: RepaintBoundary(
              key: _boundaryKey,
              // While the comment box is open the keyboard must not push the
              // app up, or the highlight would no longer sit on the element.
              child: _composing
                  ? MediaQuery(
                      data: MediaQuery.of(context)
                          .removeViewInsets(removeBottom: true),
                      child: app,
                    )
                  : app,
            ),
          ),
          if (_composing)
            Positioned.fill(
              child: Overlay(
                key: ValueKey(_session),
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => ValueListenableBuilder<int>(
                      valueListenable: _tick,
                      builder: (c, _, __) => _composer(c),
                    ),
                  ),
                ],
              ),
            ),
          if (_recording) _recordingPill(context),
          if (_banner != null) _bannerView(context),
        ],
      ),
    );
  }

  Widget _recordingPill(BuildContext context) {
    final secs = _recorder?.manualSeconds ?? 0;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: Center(
        child: GestureDetector(
          onTap: _stopRecording,
          child: Material(
            color: const Color(0xFFB3261E),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '● Recording ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}   Tap to stop',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Under the comment field: what replay is attached, what it found, and a
  /// button to record a flow by hand.
  Widget _replayRow() {
    final r = _replay;
    final firstFinding = r == null || r.summary.startsWith('Nothing stood out')
        ? null
        : r.summary.split('\n').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (firstFinding != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              firstFinding,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: r == null
                  ? Text(_preparing ? 'Preparing replay…' : 'No replay yet',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12))
                  : GestureDetector(
                      onTap: () {
                        _attachReplay = !_attachReplay;
                        _refresh();
                      },
                      child: Row(
                        children: [
                          Icon(
                            _attachReplay
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 18,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Attach replay (${r.seconds}s, ${r.frames} frames)',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            TextButton(
              onPressed: _sending ? null : _startRecording,
              child: const Text('Record'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bannerView(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Material(
          color: _bannerError
              ? const Color(0xFFB3261E)
              : _bannerInfo
                  ? const Color(0xFF8A5A00)
                  : const Color(0xFF1B7F3B),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(_banner!,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final rect = _element?.rect;
    // Keep the box off the element: if the element sits in the part of the
    // screen the box would cover, put the box at the top instead.
    final screen = MediaQuery.sizeOf(context);
    const boxHeight = 190.0;
    final boxTop = screen.height -
        insets.bottom -
        MediaQuery.paddingOf(context).bottom -
        12 -
        boxHeight;
    final atTop = rect != null && rect.bottom > boxTop;
    final label = _element == null
        ? 'Nothing found here'
        : [
            _element!.label,
            if (_element!.location != null) _element!.location!,
          ].join(' · ');

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _cancel,
            child: CustomPaint(painter: _ScrimPainter(rect)),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: atTop ? MediaQuery.paddingOf(context).top + 8 : null,
          bottom: atTop
              ? null
              : insets.bottom + 12 + MediaQuery.paddingOf(context).bottom,
          child: Material(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFF2D55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: const Color(0xFFFF2D55),
                    decoration: const InputDecoration(
                      hintText: 'What is wrong here?',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                  if (_recorder != null) _replayRow(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _sending ? null : _cancel,
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF2D55)),
                        child: Text(_sending ? 'Sending…' : 'Send'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      final rrect =
          RRect.fromRectAndRadius(hole!.inflate(3), const Radius.circular(8));
      canvas.drawPath(
        Path.combine(PathOperation.difference, full, Path()..addRRect(rrect)),
        Paint()..color = const Color(0xB3000000),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFF2D55),
      );
    } else {
      canvas.drawPath(full, Paint()..color = const Color(0xB3000000));
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
