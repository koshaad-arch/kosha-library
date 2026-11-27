import 'dart:convert';

import 'package:flutter/services.dart';

/// Picks or saves files using Android's own file screens (see MainActivity.kt).
class FileChannel {
  static const _ch = MethodChannel('kosha/files');

  /// Returns (file name, bytes) or null if cancelled.
  static Future<(String, Uint8List)?> pick() async {
    try {
      final r = await _ch.invokeMethod<Map<Object?, Object?>>('pickFile');
      if (r == null) return null;
      return ((r['name'] as String?) ?? 'file', r['bytes'] as Uint8List);
    } catch (_) {
      return null;
    }
  }

  static String text(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  /// Lets you choose where to save; returns true when saved.
  static Future<bool> save(String name, String content, {String mime = 'application/json'}) async {
    try {
      final ok = await _ch.invokeMethod<bool>(
          'saveFile', {'name': name, 'mime': mime, 'bytes': Uint8List.fromList(utf8.encode(content))});
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
