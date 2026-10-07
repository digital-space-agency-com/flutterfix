import 'dart:convert';
import 'dart:ui';

import 'replay/replay_models.dart';

/// What was found under the finger.
class ElementInfo {
  const ElementInfo({
    required this.rect,
    required this.kind,
    this.name,
    this.location,
    this.texts = const [],
    this.nearbyTexts = const [],
    this.creatorChain,
  });

  /// Bounds in global (screen) coordinates.
  final Rect rect;

  /// The render object type, e.g. `RenderParagraph`.
  final String kind;

  /// The `Fixable` name, when the element (or an ancestor) was marked.
  final String? name;

  /// `lib/foo.dart:12` of the `Fixable` call site (debug builds only).
  final String? location;

  /// Text drawn inside the element's bounds.
  final List<String> texts;

  /// Text drawn beside it, to help find it in the source.
  final List<String> nearbyTexts;

  /// Widget types leading to this element (debug builds only).
  final String? creatorChain;

  /// A short label for the composer and the report line.
  String get label {
    if (name != null) return name!;
    if (texts.length > 1) {
      return '"${texts.first.replaceAll(RegExp(r'\s+'), ' ')}" +${texts.length - 1} more texts';
    }
    if (texts.isNotEmpty) return '"${texts.first}"';
    return kind;
  }

  factory ElementInfo.fromJson(Map<String, dynamic> j) {
    final r = (j['rect'] as List).cast<num>();
    return ElementInfo(
      rect: Rect.fromLTWH(
          r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble()),
      kind: j['kind'] as String? ?? 'unknown',
      name: j['name'] as String?,
      location: j['location'] as String?,
      texts: (j['texts'] as List?)?.cast<String>() ?? const [],
      nearbyTexts: (j['nearbyTexts'] as List?)?.cast<String>() ?? const [],
      creatorChain: j['creatorChain'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location,
        'kind': kind,
        'rect': [rect.left, rect.top, rect.width, rect.height],
        'texts': texts,
        'nearbyTexts': nearbyTexts,
        'creatorChain': creatorChain,
      };
}

/// One report: the element, the words, and the screenshot.
class FixReport {
  const FixReport({
    required this.comment,
    required this.element,
    required this.touch,
    required this.screenSize,
    this.screenName,
    this.appVersion,
    this.platform,
    this.screenshotPng,
    this.replay,
    this.extra = const {},
  });

  final String comment;
  final ElementInfo? element;
  final Offset touch;
  final Size screenSize;
  final String? screenName;
  final String? appVersion;
  final String? platform;

  /// Screenshot with the element outlined, PNG encoded.
  final List<int>? screenshotPng;

  /// The last seconds (or a manual recording): film strip, timeline, findings.
  final ReplayAttachment? replay;

  /// Anything the app wants to attach (user id, build flavour, ...).
  final Map<String, String> extra;

  factory FixReport.fromJson(Map<String, dynamic> j) {
    final b64 = j['screenshotPngBase64'] as String?;
    final touch = (j['touch'] as List).cast<num>();
    final size = (j['screenSize'] as List).cast<num>();
    return FixReport(
      comment: j['comment'] as String,
      element: j['element'] == null
          ? null
          : ElementInfo.fromJson(
              Map<String, dynamic>.from(j['element'] as Map)),
      touch: Offset(touch[0].toDouble(), touch[1].toDouble()),
      screenSize: Size(size[0].toDouble(), size[1].toDouble()),
      screenName: j['screenName'] as String?,
      appVersion: j['appVersion'] as String?,
      platform: j['platform'] as String?,
      screenshotPng: b64 == null ? null : base64Decode(b64),
      replay: j['replay'] == null
          ? null
          : ReplayAttachment.fromJson(
              Map<String, dynamic>.from(j['replay'] as Map)),
      extra: Map<String, String>.from((j['extra'] as Map?) ?? const {}),
    );
  }

  Map<String, dynamic> toJson({bool includeScreenshot = false}) => {
        'comment': comment,
        'element': element?.toJson(),
        'touch': [touch.dx, touch.dy],
        'screenSize': [screenSize.width, screenSize.height],
        'screenName': screenName,
        'appVersion': appVersion,
        'platform': platform,
        'extra': extra,
        if (replay != null)
          'replay': replay!.toJson(includeImage: includeScreenshot),
        if (includeScreenshot && screenshotPng != null)
          'screenshotPngBase64': base64Encode(screenshotPng!),
      };
}

/// The outcome of sending a report.
class FixSendResult {
  const FixSendResult.ok(this.id)
      : ok = true,
        queued = false,
        retryable = false,
        message = null;

  /// Not sent yet, but saved on the device and will be sent automatically.
  const FixSendResult.queued(this.message)
      : ok = true,
        queued = true,
        retryable = false,
        id = null;

  /// [retryable] is true for problems that may go away (no signal, server
  /// busy) and false for ones that will not (not allowed, bad request).
  const FixSendResult.failed(this.message, {this.retryable = true})
      : ok = false,
        queued = false,
        id = null;

  final bool ok;
  final bool queued;
  final bool retryable;
  final String? id;
  final String? message;
}
