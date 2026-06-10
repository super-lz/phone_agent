import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/logging/app_logger.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/files/app_file_store.dart';

typedef WebAppResourceReader =
    Future<AppFileReadResult> Function({
      required AgentArtifact webApp,
      required String path,
      required int maxChars,
    });

class WebAppLocalServer {
  WebAppLocalServer({
    required this.webApp,
    required this.resourceReader,
    required this.htmlHeadInjection,
    required this.fallbackHtml,
  });

  final AgentArtifact webApp;
  final WebAppResourceReader resourceReader;
  final String htmlHeadInjection;
  final String fallbackHtml;

  HttpServer? _server;
  late final String _token = _createToken();
  final Map<String, _LocalFileResource> _localFiles = {};

  Future<Uri> start() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    unawaited(_serve(server));
    final entryPath = _entryPath();
    AppLogger.info('webapp.local_server.started', {
      'artifactId': webApp.id,
      'workspaceId': webApp.workspaceId,
      'port': server.port,
      'entry': entryPath,
    });
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['webapps', webApp.id, _token, ...entryPath.split('/')],
    );
  }

  Uri? registerLocalFile({required String path, String? mimeType}) {
    final server = _server;
    final normalizedPath = path.trim();
    if (server == null || normalizedPath.isEmpty) {
      return null;
    }
    final file = File(normalizedPath);
    if (!file.existsSync()) {
      return null;
    }
    final id = _createToken();
    _localFiles[id] = _LocalFileResource(
      path: normalizedPath,
      contentType: mimeType ?? _mimeTypeFor(normalizedPath),
    );
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [
        'webapps',
        webApp.id,
        _token,
        '__phone_agent_media__',
        id,
        _fileNameForPath(normalizedPath),
      ],
    );
  }

  Map<String, Object?> attachLocalFileUrls(Map<String, Object?> bridgeResult) {
    final output = bridgeResult['output'];
    if (output is! Map<Object?, Object?>) {
      return bridgeResult;
    }
    return {...bridgeResult, 'output': _decorateCapabilityOutput(output)};
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    if (server == null) {
      return;
    }
    await server.close(force: true);
    AppLogger.info('webapp.local_server.closed', {'artifactId': webApp.id});
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error('webapp.local_server.serve_failed', error, stackTrace, {
        'artifactId': webApp.id,
      });
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        _writePlainText(request.response, HttpStatus.methodNotAllowed, '405');
        return;
      }

      final localFile = _localFileFor(request.uri);
      if (localFile != null) {
        await _writeLocalFileResource(request, localFile);
        return;
      }
      if (_isLocalFileRequest(request.uri)) {
        _writePlainText(request.response, HttpStatus.notFound, '404');
        return;
      }

      final path = _resourcePathFor(request.uri);
      if (path == null) {
        _writePlainText(request.response, HttpStatus.forbidden, '403');
        return;
      }

      final resource = await _loadResource(path);
      _writeResource(request, resource);
    } on AppFileStoreException catch (error) {
      _writePlainText(
        request.response,
        error.code == 'not_found' ? HttpStatus.notFound : HttpStatus.badRequest,
        error.message,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error('webapp.local_server.request_failed', error, stackTrace, {
        'artifactId': webApp.id,
        'uri': request.uri.toString(),
      });
      _writePlainText(request.response, HttpStatus.internalServerError, '500');
    }
  }

  bool _isLocalFileRequest(Uri uri) {
    final segments = uri.pathSegments;
    return segments.length >= 5 &&
        segments[0] == 'webapps' &&
        segments[1] == webApp.id &&
        segments[2] == _token &&
        segments[3] == '__phone_agent_media__';
  }

  _LocalFileResource? _localFileFor(Uri uri) {
    if (!_isLocalFileRequest(uri)) {
      return null;
    }
    return _localFiles[uri.pathSegments[4]];
  }

  String? _resourcePathFor(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 3 ||
        segments[0] != 'webapps' ||
        segments[1] != webApp.id ||
        segments[2] != _token) {
      return null;
    }
    final rawPath = segments.length == 3
        ? _entryPath()
        : segments.skip(3).join('/');
    return normalizeAppFilePath(rawPath);
  }

  Future<_LocalWebResource> _loadResource(String path) async {
    final entryPath = _entryPath();
    try {
      final result = await resourceReader(
        webApp: webApp,
        path: path,
        maxChars: 20 * 1024 * 1024,
      );
      return _resourceFromContent(path, result.content);
    } on AppFileStoreException catch (error) {
      if (error.code == 'not_found' && path == entryPath) {
        return _resourceFromContent(path, fallbackHtml);
      }
      rethrow;
    }
  }

  _LocalWebResource _resourceFromContent(String path, String content) {
    final mimeType = _mimeTypeFor(path);
    final responseContent = _isHtmlMimeType(mimeType)
        ? _injectBridge(content)
        : content;
    return _LocalWebResource(
      bytes: utf8.encode(responseContent),
      contentType: mimeType,
    );
  }

  Future<void> _writeLocalFileResource(
    HttpRequest request,
    _LocalFileResource resource,
  ) async {
    final file = File(resource.path);
    if (!await file.exists()) {
      _writePlainText(request.response, HttpStatus.notFound, '404');
      return;
    }

    final length = await file.length();
    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      length,
    );
    final start = range?.start ?? 0;
    final end = range?.end ?? max(length - 1, 0);
    final contentLength = length == 0 ? 0 : end - start + 1;
    final response = request.response;
    response.headers
      ..contentType = ContentType.parse(resource.contentType)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    if (range != null) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }
    response.contentLength = contentLength;
    if (request.method != 'HEAD' && contentLength > 0) {
      await response.addStream(file.openRead(start, end + 1));
    }
    await response.close();
  }

  void _writeResource(HttpRequest request, _LocalWebResource resource) {
    final response = request.response;
    response.headers
      ..contentType = ContentType.parse(resource.contentType)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');

    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      resource.bytes.length,
    );
    if (range == null) {
      response.statusCode = HttpStatus.ok;
      response.contentLength = resource.bytes.length;
      if (request.method != 'HEAD') {
        response.add(resource.bytes);
      }
      unawaited(response.close());
      return;
    }

    final chunk = resource.bytes.sublist(range.start, range.end + 1);
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ${range.start}-${range.end}/${resource.bytes.length}',
    );
    response.contentLength = chunk.length;
    if (request.method != 'HEAD') {
      response.add(chunk);
    }
    unawaited(response.close());
  }

  _ByteRange? _parseRange(String? header, int length) {
    if (header == null || length <= 0 || !header.startsWith('bytes=')) {
      return null;
    }
    final parts = header.substring(6).split('-');
    if (parts.length != 2) {
      return null;
    }
    final start = int.tryParse(parts[0]);
    final end = parts[1].isEmpty ? length - 1 : int.tryParse(parts[1]);
    if (start == null || end == null || start < 0 || end < start) {
      return null;
    }
    return _ByteRange(start, min(end, length - 1));
  }

  void _writePlainText(HttpResponse response, int statusCode, String body) {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.text
      ..write(body);
    unawaited(response.close());
  }

  String _injectBridge(String html) {
    final headOpen = RegExp(
      r'<head\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (headOpen != null) {
      return '${html.substring(0, headOpen.end)}$htmlHeadInjection${html.substring(headOpen.end)}';
    }

    final htmlOpen = RegExp(
      r'<html\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (htmlOpen != null) {
      return '${html.substring(0, htmlOpen.end)}<head>$htmlHeadInjection</head>${html.substring(htmlOpen.end)}';
    }

    return '''
<!doctype html>
<html>
<head>$htmlHeadInjection</head>
<body>
$html
</body>
</html>
''';
  }

  String _entryPath() {
    final entry = webApp.metadata['entry'];
    if (entry is String && entry.trim().isNotEmpty) {
      return normalizeAppFilePath(entry);
    }
    return 'index.html';
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html; charset=utf-8';
    }
    if (lower.endsWith('.css')) {
      return 'text/css; charset=utf-8';
    }
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (lower.endsWith('.json') || lower.endsWith('.map')) {
      return 'application/json; charset=utf-8';
    }
    if (lower.endsWith('.svg')) {
      return 'image/svg+xml; charset=utf-8';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.ico')) {
      return 'image/x-icon';
    }
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) {
      return 'audio/mp4';
    }
    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (lower.endsWith('.ogg')) {
      return 'audio/ogg';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.webm')) {
      return 'video/webm';
    }
    if (lower.endsWith('.wasm')) {
      return 'application/wasm';
    }
    return 'text/plain; charset=utf-8';
  }

  bool _isHtmlMimeType(String mimeType) {
    return mimeType.startsWith('text/html');
  }

  String _createToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Map<String, Object?> _decorateCapabilityOutput(
    Map<Object?, Object?> rawOutput,
  ) {
    final output = <String, Object?>{
      for (final entry in rawOutput.entries)
        entry.key.toString(): _decorateCapabilityValue(entry.value),
    };
    final localUrl = _localUrlForOutput(output);
    if (localUrl == null) {
      return output;
    }

    output.putIfAbsent('localUrl', () => localUrl);
    final mediaType = output['mediaType'];
    if (mediaType == 'image' || mediaType == 'video' || mediaType == 'audio') {
      output.putIfAbsent('mediaUrl', () => localUrl);
    } else if (mediaType == 'file') {
      output.putIfAbsent('fileUrl', () => localUrl);
    }
    return output;
  }

  Object? _decorateCapabilityValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _decorateCapabilityOutput(value);
    }
    if (value is List<Object?>) {
      return [for (final item in value) _decorateCapabilityValue(item)];
    }
    return value;
  }

  String? _localUrlForOutput(Map<String, Object?> output) {
    if (output['recording'] == true || output['cancelled'] == true) {
      return null;
    }
    final path = _localPathForOutput(output);
    if (path == null) {
      return null;
    }
    final rawMimeType = output['mimeType'];
    return registerLocalFile(
      path: path,
      mimeType: rawMimeType is String ? rawMimeType : null,
    )?.toString();
  }

  String? _localPathForOutput(Map<String, Object?> output) {
    final path = output['path'];
    if (path is String && path.trim().isNotEmpty) {
      return path.trim();
    }
    final uri = output['uri'];
    if (uri is! String || uri.trim().isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme('file')) {
      return null;
    }
    return parsed.toFilePath();
  }

  String _fileNameForPath(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}

class _LocalWebResource {
  const _LocalWebResource({required this.bytes, required this.contentType});

  final List<int> bytes;
  final String contentType;
}

class _LocalFileResource {
  const _LocalFileResource({required this.path, required this.contentType});

  final String path;
  final String contentType;
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}
