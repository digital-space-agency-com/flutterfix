/// Reads Flutter's "A RenderFlex overflowed by 156 pixels on the bottom." errors.
///
/// The full error text names the widget that overflowed and, in debug builds,
/// the file and line that created it:
///
///     The relevant error-causing widget was:
///       Column
///       Column:file:///Users/me/app/lib/screens/card.dart:418:26
class OverflowParser {
  const OverflowParser._();

  static final RegExp _amount = RegExp(
      r'overflowed by ([\d.]+) pixels? on the (left|right|top|bottom)',
      caseSensitive: false);
  static final RegExp _where = RegExp(
      r'The relevant error-causing widget was:\s*\n\s*([A-Za-z0-9_<>?]+)\s*\n\s*[A-Za-z0-9_<>?]+:file:///([^\s]+?\.dart):(\d+):(\d+)');
  static final RegExp _whereLoose =
      RegExp(r'([A-Za-z0-9_<>?]+):file:///([^\s]+?\.dart):(\d+):(\d+)');

  /// Returns `{amount, edge, widget, file, line}` or null when [message] is
  /// not an overflow.
  static Map<String, Object?>? parse(String message, String fullText) {
    final m = _amount.firstMatch(message) ?? _amount.firstMatch(fullText);
    if (m == null) return null;

    final w = _where.firstMatch(fullText);
    String? widget, file;
    int? line;
    if (w != null) {
      widget = w.group(1);
      file = w.group(2);
      line = int.tryParse(w.group(3)!);
    } else {
      final loose = _whereLoose.firstMatch(fullText);
      if (loose != null) {
        widget = loose.group(1);
        file = loose.group(2);
        line = int.tryParse(loose.group(3)!);
      }
    }
    return {
      'amount': double.tryParse(m.group(1)!) ?? 0,
      'edge': m.group(2)!.toLowerCase(),
      if (widget != null) 'widget': widget,
      if (file != null) 'file': _projectPath(file),
      if (line != null) 'line': line,
    };
  }

  /// `Users/me/app/lib/screens/card.dart` becomes `lib/screens/card.dart`.
  static String _projectPath(String path) {
    final i = path.indexOf('/lib/');
    if (i >= 0) return path.substring(i + 1);
    final t = path.indexOf('/test/');
    return t >= 0 ? path.substring(t + 1) : path.split('/').last;
  }
}
