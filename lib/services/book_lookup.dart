import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';
import 'library_store.dart';

/// A book found online, before it is added to the shelf.
class FoundBook {
  final String title, subtitle, author, publisher, isbn, description, coverUrl, genre;
  final int? year, pages;
  FoundBook({
    required this.title,
    this.subtitle = '',
    this.author = '',
    this.publisher = '',
    this.isbn = '',
    this.description = '',
    this.coverUrl = '',
    this.genre = '',
    this.year,
    this.pages,
  });

  Book toBook(ReadStatus status, {String own = 'own'}) {
    final now = DateTime.now();
    return Book(
      id: 'u${now.microsecondsSinceEpoch}',
      title: title,
      subtitle: subtitle,
      author: author,
      publisher: publisher,
      isbn: isbn,
      summary: description,
      coverUrl: coverUrl,
      genre: genre,
      year: year,
      pages: pages,
      status: status,
      start: status == ReadStatus.reading ? now : null,
      end: status == ReadStatus.read ? now : null,
      currentPage: status == ReadStatus.read ? (pages ?? 0) : 0,
      own: own,
    );
  }
}

/// Looks books up on Google Books first, then Open Library. No API keys needed.
class BookLookup {
  static const _timeout = Duration(seconds: 12);

  static bool looksLikeIsbn(String s) {
    final n = LibraryStore.normIsbn(s);
    return n.length == 13 && (n.startsWith('978') || n.startsWith('979')) || n.length == 10;
  }

  static Future<List<FoundBook>> byIsbn(String raw) async {
    final isbn = LibraryStore.normIsbn(raw);
    final g = await _google('isbn:$isbn', fallbackIsbn: isbn);
    if (g.isNotEmpty) return g.take(3).toList();
    final o = await _openLibraryIsbn(isbn);
    return o == null ? [] : [o];
  }

  static Future<List<FoundBook>> search(String text) async {
    final g = await _google(text);
    if (g.isNotEmpty) return g;
    return _openLibrarySearch(text);
  }

  static Future<List<FoundBook>> _google(String q, {String fallbackIsbn = ''}) async {
    try {
      final uri = Uri.https('www.googleapis.com', '/books/v1/volumes',
          {'q': q, 'maxResults': '15', 'printType': 'books'});
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final items = (jsonDecode(res.body)['items'] as List?) ?? [];
      return items.map((it) {
        final v = Map<String, dynamic>.from(it['volumeInfo'] as Map);
        final ids = ((v['industryIdentifiers'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        String isbn = fallbackIsbn;
        for (final t in ['ISBN_13', 'ISBN_10']) {
          final m = ids.where((e) => e['type'] == t);
          if (m.isNotEmpty) {
            isbn = m.first['identifier'] as String;
            break;
          }
        }
        final links = (v['imageLinks'] as Map?) ?? {};
        final cover = ((links['thumbnail'] ?? links['smallThumbnail'] ?? '') as String)
            .replaceFirst('http://', 'https://');
        final cats = ((v['categories'] as List?) ?? []).map((e) => e.toString()).toList();
        return FoundBook(
          title: (v['title'] ?? 'Untitled') as String,
          subtitle: (v['subtitle'] ?? '') as String,
          author: ((v['authors'] as List?) ?? []).join(', '),
          publisher: (v['publisher'] ?? '') as String,
          year: int.tryParse(((v['publishedDate'] ?? '') as String).split('-').first),
          pages: v['pageCount'] as int?,
          description: (v['description'] ?? '') as String,
          coverUrl: cover,
          isbn: isbn,
          genre: guessGenre(cats.join(' ')),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<FoundBook?> _openLibraryIsbn(String isbn) async {
    try {
      final uri = Uri.https('openlibrary.org', '/api/books',
          {'bibkeys': 'ISBN:$isbn', 'format': 'json', 'jscmd': 'data'});
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map;
      final d = m['ISBN:$isbn'];
      if (d == null) return null;
      final v = Map<String, dynamic>.from(d as Map);
      final cover = (v['cover'] as Map?)?['medium'] as String? ?? '';
      final subjects =
          ((v['subjects'] as List?) ?? []).map((e) => (e as Map)['name'].toString()).join(' ');
      return FoundBook(
        title: (v['title'] ?? 'Untitled') as String,
        subtitle: (v['subtitle'] ?? '') as String,
        author: ((v['authors'] as List?) ?? []).map((e) => (e as Map)['name']).join(', '),
        publisher: ((v['publishers'] as List?) ?? []).map((e) => (e as Map)['name']).join(', '),
        year: int.tryParse(RegExp(r'\d{4}').stringMatch((v['publish_date'] ?? '') as String) ?? ''),
        pages: v['number_of_pages'] as int?,
        coverUrl: cover,
        isbn: isbn,
        genre: guessGenre(subjects),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<FoundBook>> _openLibrarySearch(String text) async {
    try {
      final uri = Uri.https('openlibrary.org', '/search.json', {
        'q': text,
        'limit': '15',
        'fields': 'title,author_name,first_publish_year,isbn,number_of_pages_median,cover_i,publisher,subject',
      });
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final docs = (jsonDecode(res.body)['docs'] as List?) ?? [];
      return docs.map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        final isbns = ((v['isbn'] as List?) ?? []).map((x) => x.toString()).toList();
        final isbn = isbns.firstWhere((x) => x.length == 13, orElse: () => isbns.isEmpty ? '' : isbns.first);
        final coverId = v['cover_i'];
        return FoundBook(
          title: (v['title'] ?? 'Untitled') as String,
          author: ((v['author_name'] as List?) ?? []).join(', '),
          year: v['first_publish_year'] as int?,
          pages: v['number_of_pages_median'] as int?,
          publisher: ((v['publisher'] as List?) ?? []).take(1).join(),
          isbn: isbn,
          coverUrl: coverId == null ? '' : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
          genre: guessGenre(((v['subject'] as List?) ?? []).take(12).join(' ')),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Maps online categories to the app's genre list.
  static String guessGenre(String cats) {
    final c = cats.toLowerCase();
    if (c.isEmpty) return '';
    const map = <String, List<String>>{
      "Children's": ['juvenile', 'children'],
      'Young Adult': ['young adult'],
      'Thriller & Mystery': ['thriller', 'mystery', 'crime', 'detective', 'suspense'],
      'Romance': ['romance', 'love stories'],
      'Fantasy & Sci-Fi': ['fantasy', 'science fiction', 'magic', 'dystopia'],
      'Mythology': ['mythology', 'hindu', 'legends'],
      'Self-help': ['self-help', 'self help', 'personal growth', 'success', 'business', 'psychology', 'finance'],
      'Spiritual': ['religion', 'spiritual', 'meditation', 'philosophy'],
      'Comics': ['comics', 'graphic novel'],
      'Poetry': ['poetry'],
      'Classics': ['classic'],
      'Non-fiction': ['biography', 'history', 'science', 'memoir', 'true crime', 'nonfiction'],
      'Literary Fiction': ['fiction', 'literary'],
    };
    for (final e in map.entries) {
      if (e.value.any(c.contains)) return e.key;
    }
    return 'Other';
  }
}
