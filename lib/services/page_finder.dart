import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';

/// Looks up a book's real printed page count: Google Books (ISBN) → Open Library (ISBN)
/// → Open Library search (title + author) → Google Books search.
class PageFinder {
  static Future<Map<String, dynamic>?> _getJ(Uri u) async {
    try {
      final r = await http.get(u).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      return null;
    }
  }

  static int? _ok(dynamic v) {
    final n = v is int ? v : int.tryParse('$v');
    return (n != null && n >= 16 && n < 5000) ? n : null;
  }

  static Future<int?> find(Book b) async {
    final isbn = b.isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (isbn.isNotEmpty) {
      final g = await _getJ(Uri.https('www.googleapis.com', '/books/v1/volumes', {'q': 'isbn:$isbn'}));
      for (final it in (g?['items'] as List?) ?? []) {
        final p = _ok((it as Map)['volumeInfo']?['pageCount']);
        if (p != null) return p;
      }
      final o = await _getJ(Uri.https('openlibrary.org', '/api/books', {'bibkeys': 'ISBN:$isbn', 'format': 'json', 'jscmd': 'data'}));
      final p = _ok((o?['ISBN:$isbn'] as Map?)?['number_of_pages']);
      if (p != null) return p;
    }
    final t = b.title.split(':').first.trim();
    if (t.isEmpty) return null;
    final a = b.firstAuthor;
    final s = await _getJ(Uri.https('openlibrary.org', '/search.json',
        {'title': t, if (a.isNotEmpty) 'author': a, 'limit': '3', 'fields': 'number_of_pages_median'}));
    for (final d in (s?['docs'] as List?) ?? []) {
      final p = _ok((d as Map)['number_of_pages_median']);
      if (p != null) return p;
    }
    final g = await _getJ(Uri.https('www.googleapis.com', '/books/v1/volumes',
        {'q': 'intitle:$t${a.isNotEmpty ? ' inauthor:$a' : ''}', 'maxResults': '3'}));
    for (final it in (g?['items'] as List?) ?? []) {
      final p = _ok((it as Map)['volumeInfo']?['pageCount']);
      if (p != null) return p;
    }
    return null;
  }
}
