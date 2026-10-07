import 'dart:ui';

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
    if (texts.isNotEmpty) return '"${texts.first}"';
    return kind;
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

  /// Anything the app wants to attach (user id, build flavour, ...).
  final Map<String, String> extra;

  Map<String, dynamic> toJson({bool includeScreenshot = false}) => {
        'comment': comment,
        'element': element?.toJson(),
        'touch': [touch.dx, touch.dy],
        'screenSize': [screenSize.width, screenSize.height],
        'screenName': screenName,
        'appVersion': appVersion,
        'platform': platform,
        'extra': extra,
      };
}

/// The outcome of sending a report.
class FixSendResult {
  const FixSendResult.ok(this.id)
      : ok = true,
        message = null;
  const FixSendResult.failed(this.message)
      : ok = false,
        id = null;

  final bool ok;
  final String? id;
  final String? message;
}
