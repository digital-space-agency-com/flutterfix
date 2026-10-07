import 'package:flutter/widgets.dart';

import 'recorder.dart';

/// Tells the replay when pages open and close. Add it to your navigator:
///
/// ```dart
/// MaterialApp(navigatorObservers: [FlutterFixObserver()], ...)
/// // go_router: GoRouter(observers: [FlutterFixObserver()], ...)
/// ```
///
/// Pages without a name show as their route type; give routes names (or pass
/// `screenName` to `FlutterFix`) for clearer reports.
class FlutterFixObserver extends NavigatorObserver {
  static String? _name(Route<dynamic>? r) =>
      r == null ? null : (r.settings.name ?? r.runtimeType.toString());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ReplayRecorder.current
          ?.noteRoute('push', _name(route), _name(previousRoute));

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ReplayRecorder.current
          ?.noteRoute('pop', _name(route), _name(previousRoute));

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      ReplayRecorder.current
          ?.noteRoute('replace', _name(newRoute), _name(oldRoute));

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ReplayRecorder.current
          ?.noteRoute('remove', _name(route), _name(previousRoute));
}
