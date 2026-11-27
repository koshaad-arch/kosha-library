import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

/// Finds a cover for a book: your own URL → Google Books (ISBN) → Open Library (ISBN)
/// → Open Library title search → Google Books title search. Results are remembered.
class CoverService {
  CoverService._();
  static final instance = CoverService._();

  static const _kCache = 'cover_cache_v1';
  final Map<String, String> _cache = {};
  final Map<String, ValueNotifier<String?>> _notes = {};
  final List<(String, Book)> _queue = [];
  int _active = 0;
  bool _loaded = false;
  Timer? _saveT;

  static String keyOf(Book b) {
    final i = b.isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (i.isNotEmpty) return i;
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '').split(':').first.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return 't:${n(b.title)}|${n(b.firstAuthor)}';
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kCache);
      if (s != null) _cache.addAll(Map<String, String>.from(jsonDecode(s) as Map));
    } catch (_) {}
  }

  void _save() {
    _saveT?.cancel();
    _saveT = Timer(const Duration(seconds: 2), () async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kCache, jsonEncode(_cache));
    });
  }

  /// Listenable URL for this book's cover: null = still looking, '' = none found.
  ValueNotifier<String?> coverFor(Book b) {
    if (b.coverUrl.startsWith('https://')) return ValueNotifier(b.coverUrl);
    final k = keyOf(b);
    final existing = _notes[k];
    if (existing != null) return existing;
    final n = ValueNotifier<String?>(_cache[k]);
    _notes[k] = n;
    if (!_cache.containsKey(k)) {
      _load().then((_) {
        if (_cache.containsKey(k)) {
          n.value = _cache[k];
        } else {
          _queue.add((k, b));
          _pump();
        }
      });
    }
    return n;
  }

  /// Remember a cover found elsewhere (e.g. by the ISBN lookup when scanning).
  void remember(Book b, String url) {
    if (url.isEmpty) return;
    final k = keyOf(b);
    _cache[k] = url;
    _notes[k]?.value = url;
    _save();
  }

  void _pump() {
    while (_active < 3 && _queue.isNotEmpty) {
      final (k, b) = _queue.removeAt(0);
      _active++;
      _find(b).then((r) {
        final (url, netErr) = r;
        if (url.isNotEmpty || !netErr) {
          _cache[k] = url;
          _save();
        }
        _notes[k]?.value = url;
      }).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  Future<(String, bool)> _find(Book b) async {
    var netErr = false;
    Future<Map<String, dynamic>?> getJ(Uri u) async {
      try {
        final r = await http.get(u).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) {
          if (r.statusCode == 429 || r.statusCode >= 500) netErr = true;
          return null;
        }
        return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      } catch (_) {
        netErr = true;
        return null;
      }
    }

    String gThumb(Map<String, dynamic>? d) {
      final items = d?['items'] as List?;
      if (items == null || items.isEmpty) return '';
      final links = (items.first['volumeInfo']?['imageLinks'] as Map?) ?? {};
      final u = (links['thumbnail'] ?? links['smallThumbnail'] ?? '') as String;
      return u.replaceFirst('http://', 'https://').replaceAll('&edge=curl', '');
    }

    final isbn = b.isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    final t = b.title.split(':').first.trim();
    final a = b.firstAuthor;
    if (isbn.isNotEmpty) {
      final g = gThumb(await getJ(Uri.https('www.googleapis.com', '/books/v1/volumes', {'q': 'isbn:$isbn'})));
      if (g.isNotEmpty) return (g, netErr);
      try {
        final ol = 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
        final r = await http.head(Uri.parse(ol)).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) return (ol, netErr);
      } catch (_) {
        netErr = true;
      }
    }
    if (t.isNotEmpty) {
      final ol = await getJ(Uri.https('openlibrary.org', '/search.json',
          {'title': t, if (a.isNotEmpty) 'author': a, 'limit': '5', 'fields': 'cover_i'}));
      final docs = (ol?['docs'] as List?) ?? [];
      for (final d in docs) {
        final ci = (d as Map)['cover_i'];
        if (ci != null) return ('https://covers.openlibrary.org/b/id/$ci-M.jpg', netErr);
      }
      final g = gThumb(await getJ(Uri.https('www.googleapis.com', '/books/v1/volumes',
          {'q': 'intitle:$t${a.isNotEmpty ? ' inauthor:$a' : ''}', 'maxResults': '1'})));
      if (g.isNotEmpty) return (g, netErr);
    }
    return ('', netErr);
  }
}
