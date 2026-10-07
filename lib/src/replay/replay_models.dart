import 'dart:convert';

/// One thing that happened while recording, in milliseconds since the
/// recorder started.
class ReplayEvent {
  const ReplayEvent(this.t, this.kind, [this.data = const {}]);

  final int t;

  /// `route`, `sample` or `slow`.
  final String kind;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {'t': t, 'kind': kind, ...data};
}

/// Settings for the replay.
class ReplayConfig {
  const ReplayConfig({
    this.rolling = true,
    this.rollingSeconds = 10,
    this.maxManualSeconds = 30,
    this.fps = 4,
    this.frameWidth = 240,
    this.slowFrameMs = 32,
  });

  /// Keep the last [rollingSeconds] at all times, so a report made after
  /// something went wrong includes what just happened.
  final bool rolling;
  final int rollingSeconds;

  /// A manual recording stops by itself after this long.
  final int maxManualSeconds;

  /// Frames per second kept (a few is enough to see a list fill in).
  final int fps;

  /// Width of each stored frame in pixels.
  final int frameWidth;

  /// A frame that takes longer than this to build and draw counts as slow.
  final int slowFrameMs;
}

/// What is attached to a report.
class ReplayAttachment {
  const ReplayAttachment({
    required this.mode,
    required this.seconds,
    required this.frames,
    required this.summary,
    required this.timeline,
    this.filmstripPng,
  });

  /// `rolling` or `manual`.
  final String mode;
  final double seconds;
  final int frames;

  /// Plain-English findings: slow frames, empty or slow lists.
  final String summary;

  /// The condensed event log, for the report.
  final List<Map<String, Object?>> timeline;

  /// All frames laid out in one picture with a time on each.
  final List<int>? filmstripPng;

  factory ReplayAttachment.fromJson(Map<String, dynamic> j) {
    final b64 = j['filmstripPngBase64'] as String?;
    return ReplayAttachment(
      mode: j['mode'] as String? ?? 'rolling',
      seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
      frames: (j['frames'] as num?)?.toInt() ?? 0,
      summary: j['summary'] as String? ?? '',
      timeline: [
        for (final e in (j['timeline'] as List?) ?? const [])
          Map<String, Object?>.from(e as Map),
      ],
      filmstripPng: b64 == null ? null : base64Decode(b64),
    );
  }

  Map<String, Object?> toJson({bool includeImage = false}) => {
        'mode': mode,
        'seconds': seconds,
        'frames': frames,
        'summary': summary,
        'timeline': timeline,
        if (includeImage && filmstripPng != null)
          'filmstripPngBase64': base64Encode(filmstripPng!),
      };
}
