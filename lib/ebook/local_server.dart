import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// A tiny web server on 127.0.0.1 that only this app uses: it serves the bundled
/// PDF.js reader and the PDF you are reading, so the reader works fully offline.
class LocalServer {
  static HttpServer? _server;
  static final Map<String, String> _files = {};
  static final _rand = Random.secure();

  static Future<int> start() async {
    final s = _server;
    if (s != null) return s.port;
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen(_handle);
    _server = srv;
    return srv.port;
  }

  /// Makes a file readable at /file/<token>.pdf (an unguessable token).
  static String register(String path) {
    final token = List.generate(24, (_) => _rand.nextInt(36).toRadixString(36)).join();
    _files[token] = path;
    return '/file/$token.pdf';
  }

  static String _type(String p) {
    if (p.endsWith('.mjs') || p.endsWith('.js')) return 'text/javascript; charset=utf-8';
    if (p.endsWith('.css')) return 'text/css; charset=utf-8';
    if (p.endsWith('.html')) return 'text/html; charset=utf-8';
    if (p.endsWith('.svg')) return 'image/svg+xml';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  static Future<void> _handle(HttpRequest r) async {
    final path = r.uri.path;
    final res = r.response;
    try {
      res.headers.set('Cache-Control', 'no-store');
      if (path.startsWith('/file/')) {
        final token = path.substring(6).replaceAll('.pdf', '');
        final f = _files[token];
        if (f == null) {
          res.statusCode = 404;
        } else {
          res.headers.set('Content-Type', 'application/pdf');
          await res.addStream(File(f).openRead());
        }
      } else {
        final rel = path == '/' ? '/reader.html' : Uri.decodeComponent(path);
        if (rel.contains('..')) throw Exception('bad path');
        final data = await rootBundle.load('assets/pdfjs$rel');
        res.headers.set('Content-Type', _type(rel));
        res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    } catch (_) {
      res.statusCode = 404;
    }
    await res.close();
  }
}
