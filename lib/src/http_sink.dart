import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'report.dart';
import 'sink.dart';

/// Sends reports to your own server over HTTPS: works from any network,
/// including mobile data. Pair it with [OutboxSink] so reports made without
/// signal are kept and sent later.
///
/// The server gets a JSON body (see [FixReport.toJson]) with the screenshot as
/// `screenshotPngBase64`. [headers] is called for every request, so it can
/// return a fresh sign-in token, e.g. a Firebase ID token:
///
/// ```dart
/// HttpSink(Uri.parse(url), headers: () async => {
///   'Authorization': 'Bearer ${await user.getIdToken()}',
/// })
/// ```
class HttpSink extends FlutterFixSink {
  const HttpSink(
    this.url, {
    this.headers,
    this.timeout = const Duration(seconds: 25),
  });

  final Uri url;
  final Future<Map<String, String>> Function()? headers;
  final Duration timeout;

  @override
  Future<FixSendResult> send(FixReport report) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(url).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final extra = await headers?.call() ?? const <String, String>{};
      extra.forEach(request.headers.set);
      request
          .add(utf8.encode(jsonEncode(report.toJson(includeScreenshot: true))));
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      final code = response.statusCode;
      if (code >= 200 && code < 300) {
        String? id;
        try {
          id = (jsonDecode(body) as Map)['id']?.toString();
        } catch (_) {}
        return FixSendResult.ok(id ?? 'ok');
      }
      if (code == 401 || code == 403) {
        return const FixSendResult.failed('Not allowed to send reports',
            retryable: false);
      }
      if (code == 408 || code == 429 || code >= 500) {
        return FixSendResult.failed('Server busy ($code)');
      }
      return FixSendResult.failed('Server refused the report ($code)',
          retryable: false);
    } on SocketException {
      return const FixSendResult.failed('No connection');
    } on TimeoutException {
      return const FixSendResult.failed('The server took too long');
    } on HandshakeException {
      return const FixSendResult.failed('Secure connection failed');
    } catch (e) {
      return FixSendResult.failed('$e');
    } finally {
      client.close(force: true);
    }
  }
}
