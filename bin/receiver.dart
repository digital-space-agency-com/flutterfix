// Receives FlutterFix reports from a running app and prints one line per report,
// so a Claude Code session can pick them up (start it with the Monitor tool).
//
//   dart run flutterfix:receiver [--port 4747] [--out .flutterfix]
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var port = 4747;
  var out = '.flutterfix';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') port = int.parse(args[i + 1]);
    if (args[i] == '--out') out = args[i + 1];
  }
  final dir = Directory('$out/reports')..createSync(recursive: true);
  var n = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .length;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln(
      'flutterfix receiver listening on :$port, writing to $out/reports');

  await for (final req in server) {
    try {
      if (req.method == 'GET') {
        req.response
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
        await req.response.close();
        continue;
      }
      final body = await utf8.decoder.bind(req).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final id = 'r${++n}';
      final b64 = json.remove('screenshotPngBase64') as String?;
      String? png;
      if (b64 != null) {
        png = '${dir.path}/$id.png';
        File(png).writeAsBytesSync(base64Decode(b64));
      }
      final replay = json['replay'] as Map<String, dynamic>?;
      final stripB64 = replay?.remove('filmstripPngBase64') as String?;
      String? strip;
      if (stripB64 != null) {
        strip = '${dir.path}/$id.replay.png';
        File(strip).writeAsBytesSync(base64Decode(stripB64));
      }
      File('${dir.path}/$id.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

      final el = json['element'] as Map<String, dynamic>?;
      String one(String t) => t.replaceAll(RegExp(r'\s+'), ' ').trim();
      final texts = ((el?['texts'] as List?)?.cast<String>() ?? const [])
          .map(one)
          .toList();
      final near = ((el?['nearbyTexts'] as List?)?.cast<String>() ?? const [])
          .map(one)
          .toList();
      final chain = el?['creatorChain'] as String?;
      final parts = <String>[
        if (el?['name'] != null) el!['name'] as String,
        if (el?['location'] != null) el!['location'] as String,
        if (el != null) el['kind'] as String,
        if (texts.isNotEmpty) 'text ${texts.map((t) => '"$t"').join(', ')}',
        if (near.isNotEmpty)
          'near ${near.take(4).map((t) => '"$t"').join(', ')}',
        if (chain != null) 'in ${chain.split(' ← ').take(6).join(' ← ')}',
        if (json['screenName'] != null) '${json['screenName']} screen',
        if (png != null) png,
      ];
      final comment =
          (json['comment'] as String).replaceAll(RegExp(r'\s+'), ' ');
      stdout.writeln('[fix $id] ${parts.join(' · ')} :: $comment');
      if (replay != null) {
        final summary =
            ((replay['summary'] as String?) ?? '').replaceAll('\n', ' | ');
        stdout.writeln('[fix $id] replay (${replay['mode']}, '
            '${replay['seconds']}s, ${replay['frames']} frames): $summary'
            '${strip != null ? ' · $strip' : ''}');
      }

      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'id': id}));
      await req.response.close();
    } catch (e) {
      stdout.writeln('flutterfix receiver error: $e');
      req.response.statusCode = 500;
      await req.response.close();
    }
  }
}
