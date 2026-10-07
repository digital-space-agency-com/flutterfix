/// FlutterFix: long press any element, describe the problem, and send it to
/// Claude Code with a screenshot.
library;

export 'src/fixable.dart' show Fixable, FixableX;
export 'src/overlay.dart' show FlutterFix;
export 'src/report.dart' show ElementInfo, FixReport, FixSendResult;
export 'src/sink.dart' show FlutterFixSink, LocalReceiverSink, MemorySink;
