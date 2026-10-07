import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'capture.dart';
import 'inspect.dart';
import 'report.dart';
import 'sink.dart';

/// Wrap the app with this (in `MaterialApp.builder`) to let people long press
/// any element and send a report.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => FixLens(
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
class FixLens extends StatefulWidget {
  const FixLens({
    super.key,
    required this.child,
    required this.sink,
    this.enabled = kDebugMode,
    this.screenName,
    this.appVersion,
    this.extra,
    this.holdDuration = const Duration(milliseconds: 600),
    @visibleForTesting this.screenshotter,
  });

  final Widget child;
  final FixLensSink sink;
  final bool enabled;

  /// Name of the screen on display, e.g. from your router. Sent with reports.
  final String? Function()? screenName;

  /// Sent with reports so you know which build the problem is in.
  final String? appVersion;

  /// Extra values attached to every report.
  final Map<String, String> Function()? extra;

  final Duration holdDuration;

  final Future<Uint8List?> Function(Rect? highlight)? screenshotter;

  @override
  State<FixLens> createState() => _FixLensState();
}

class _FixLensState extends State<FixLens> {
  final GlobalKey _boundaryKey = GlobalKey();
  ElementInfo? _element;
  Offset _touch = Offset.zero;
  Uint8List? _screenshot;
  bool _composing = false;
  bool _sending = false;
  String? _banner;
  bool _bannerError = false;
  Timer? _bannerTimer;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ValueNotifier<int> _tick = ValueNotifier(0);
  int _session = 0;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> _onLongPress(LongPressStartDetails d) async {
    if (_composing || _sending) return;
    final screen = MediaQuery.sizeOf(context);
    final info = Inspector.inspect(context, d.globalPosition, screen);
    HapticFeedback.mediumImpact();
    final shot = await _capture(info?.rect);
    if (!mounted) return;
    setState(() {
      _touch = d.globalPosition;
      _element = info;
      _screenshot = shot;
      _composing = true;
      _session++;
      _text.clear();
    });
  }

  Future<Uint8List?> _capture(Rect? rect) async {
    if (widget.screenshotter != null) return widget.screenshotter!(rect);
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    return captureScreenshot(boundary, rect);
  }

  void _cancel() => setState(() => _composing = false);

  Future<void> _send() async {
    final comment = _text.text.trim();
    if (comment.isEmpty || _sending) return;
    setState(() => _sending = true);
    _tick.value++;
    final report = FixReport(
      comment: comment,
      element: _element,
      touch: _touch,
      screenSize: MediaQuery.sizeOf(context),
      screenName: widget.screenName?.call(),
      appVersion: widget.appVersion,
      platform: defaultTargetPlatform.name,
      screenshotPng: _screenshot,
      extra: widget.extra?.call() ?? const {},
    );
    final result = await widget.sink.send(report);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _composing = false;
    });
    _showBanner(
      result.ok
          ? 'Sent ${result.id ?? ''} to Claude'
          : (result.message ?? 'Send failed'),
      error: !result.ok,
    );
  }

  void _showBanner(String text, {required bool error}) {
    _bannerTimer?.cancel();
    setState(() {
      _banner = text;
      _bannerError = error;
    });
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

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
                      child: widget.child,
                    )
                  : widget.child,
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
          if (_banner != null) _bannerView(context),
        ],
      ),
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
          color:
              _bannerError ? const Color(0xFFB3261E) : const Color(0xFF1B7F3B),
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
