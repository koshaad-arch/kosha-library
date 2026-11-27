import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import 'goodreads_sync.dart';

enum SortBy { title, author, rating, finished, shortest, recentlyAdded }

extension SortByX on SortBy {
  String get label => switch (this) {
        SortBy.title => 'Title A–Z',
        SortBy.author => 'Author A–Z',
        SortBy.rating => 'Highest rated',
        SortBy.finished => 'Recently finished',
        SortBy.shortest => 'Shortest first',
        SortBy.recentlyAdded => 'Recently added',
      };
}

/// Holds the whole library, persists it to SharedPreferences and exposes
/// filtered views for the UI.
class LibraryStore extends ChangeNotifier {
  static const _kBooks = 'library_v1';
  static const _kGoal = 'goal_v1';
  static const _kCovers = 'covers_v1';
  static const _kGrLast = 'gr_last_v1';

  final List<Book> _books = [];
  int goal = 24;
  bool showCovers = true;

  // Goodreads sync
  DateTime? grLastSync;
  String syncMessage = '';

  bool loaded = false;

  // UI filter state
  String query = '';
  String statusFilter = 'all'; // all | tbr | reading | read | dnf | fav
  String genreFilter = '';
  SortBy sort = SortBy.title;

  Timer? _saveTimer;

  List<Book> get books => List.unmodifiable(_books);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kBooks);
    if (saved != null) {
      _books.addAll(Book.decodeList(saved));
    } else {
      final raw = await rootBundle.loadString('assets/books.json');
      final list = (jsonDecode(raw) as List)
          .map((e) => Book.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _books.addAll(list);
      await _saveNow();
    }
    goal = prefs.getInt(_kGoal) ?? 24;
    showCovers = prefs.getBool(_kCovers) ?? true;
    final last = prefs.getString(_kGrLast);
    grLastSync = last == null ? null : DateTime.tryParse(last);
    loaded = true;
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBooks, Book.encodeList(_books));
    await prefs.setInt(_kGoal, goal);
    await prefs.setBool(_kCovers, showCovers);
    if (grLastSync != null) await prefs.setString(_kGrLast, grLastSync!.toIso8601String());
  }

  Book? byId(String id) {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  static String normIsbn(String s) => s.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();

  /// Converts ISBN-10 to ISBN-13 so both forms match each other.
  static String isbn13(String s) {
    final n = normIsbn(s);
    if (n.length != 10) return n;
    final core = '978${n.substring(0, 9)}';
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(core[i]) * (i.isEven ? 1 : 3);
    }
    return '$core${(10 - sum % 10) % 10}';
  }

  Book? byIsbn(String isbn) {
    final target = isbn13(isbn);
    if (target.isEmpty) return null;
    for (final b in _books) {
      if (b.isbn.isNotEmpty && isbn13(b.isbn) == target) return b;
    }
    return null;
  }

  void add(Book b) {
    _books.add(b);
    _scheduleSave();
    notifyListeners();
  }

  void remove(Book b) {
    _books.removeWhere((x) => x.id == b.id);
    _scheduleSave();
    notifyListeners();
  }

  /// Call after mutating a book's fields.
  void touch(Book b) {
    _scheduleSave();
    notifyListeners();
  }

  void setStatus(Book b, ReadStatus s) {
    b.status = s;
    final now = DateTime.now();
    if (s == ReadStatus.reading) b.start ??= now;
    if (s == ReadStatus.read) {
      b.end ??= now;
      if (b.pages != null) b.currentPage = b.pages!;
    }
    touch(b);
  }

  void setGoal(int g) {
    goal = g;
    _scheduleSave();
    notifyListeners();
  }

  /// Reads the CSV from Goodreads → My Books → Import and export → Export Library,
  /// and merges it into the shelf. Returns a short summary for the user.
  String importGoodreadsCsv(String text) {
    final rows = parseCsv(text.replaceFirst('﻿', '').trim());
    if (rows.length < 2 || !rows.first.contains('Exclusive Shelf')) {
      return 'That file doesn\'t look like a Goodreads export. Use “Export Library” on goodreads.com.';
    }
    final h = rows.first.map((e) => e.trim()).toList();
    String v(List<String> r, String n) {
      final i = h.indexOf(n);
      if (i < 0 || i >= r.length) return '';
      return r[i].trim().replaceAll(RegExp(r'^="?|"$'), '');
    }

    DateTime? d(String s) {
      final m = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(s);
      return m == null ? null : DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }

    final items = <GrItem>[];
    for (final r in rows.skip(1)) {
      final title = v(r, 'Title');
      if (title.isEmpty) continue;
      final isbn13 = v(r, 'ISBN13');
      items.add(GrItem(
        grId: v(r, 'Book Id'),
        title: title,
        author: v(r, 'Author'),
        isbn: isbn13.isNotEmpty ? isbn13 : v(r, 'ISBN'),
        review: v(r, 'My Review').replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), ''),
        imageUrl: '',
        description: '',
        shelf: v(r, 'Exclusive Shelf'),
        rating: double.tryParse(v(r, 'My Rating')) ?? 0,
        readAt: d(v(r, 'Date Read')),
        addedAt: d(v(r, 'Date Added')),
        pages: int.tryParse(v(r, 'Number of Pages')),
        year: int.tryParse(v(r, 'Original Publication Year')) ?? int.tryParse(v(r, 'Year Published')),
      ));
    }
    final (added, updated) = _mergeGoodreads(items);
    grLastSync = DateTime.now();
    syncMessage = 'Goodreads import: ${items.length} books checked, $added new, $updated updated.';
    _scheduleSave();
    notifyListeners();
    return syncMessage;
  }

  (int, int) _mergeGoodreads(List<GrItem> items) {
    var added = 0, updated = 0;
    final byGr = <String, Book>{};
    final byIsbn = <String, Book>{};
    final byKey = <String, Book>{};
    for (final b in _books) {
      if (b.goodreadsId.isNotEmpty) byGr[b.goodreadsId] = b;
      if (b.isbn.isNotEmpty) byIsbn[isbn13(b.isbn)] = b;
      byKey[GoodreadsSync.matchKey(b.title, b.author)] = b;
    }
    for (final g in items) {
      Book? b = (g.grId.isNotEmpty ? byGr[g.grId] : null) ??
          (g.isbn.isNotEmpty ? byIsbn[isbn13(g.isbn)] : null) ??
          byKey[GoodreadsSync.matchKey(g.title, g.author)];
      var isNew = false;
      if (b == null) {
        final t = g.title;
        final cut = t.indexOf(RegExp(r' \(|: '));
        b = Book(
          id: g.grId.isNotEmpty ? 'g${g.grId}' : 'u${DateTime.now().microsecondsSinceEpoch}$added',
          title: cut > 2 ? t.substring(0, cut) : t,
          subtitle: cut > 2 ? t.substring(cut).replaceAll(RegExp(r'^[ :(]+|\)$'), '') : '',
          author: g.author,
          isbn: g.isbn,
          pages: g.pages,
          year: g.year,
          added: g.addedAt,
        );
        _books.add(b);
        if (g.grId.isNotEmpty) byGr[g.grId] = b;
        isNew = true;
        added++;
      }
      if (g.grId.isNotEmpty) b.goodreadsId = g.grId;
      if (b.isbn.isEmpty && g.isbn.isNotEmpty) b.isbn = g.isbn;
      if (b.pages == null && g.pages != null) b.pages = g.pages;
      if (b.grSig == g.signature) continue; // unchanged on Goodreads since the last import
      b.status = g.status;
      if (g.rating > 0) b.rating = g.rating;
      if (g.readAt != null) b.end = g.readAt;
      if (g.status == ReadStatus.reading) b.start ??= g.addedAt;
      if (g.status == ReadStatus.read && b.pages != null) b.currentPage = b.pages!;
      if (g.review.trim().isNotEmpty) b.review = g.review.trim();
      b.grSig = g.signature;
      if (!isNew) updated++;
    }
    return (added, updated);
  }

  void setShowCovers(bool v) {
    showCovers = v;
    _scheduleSave();
    notifyListeners();
  }

  void setFilter({String? q, String? status, String? genre, SortBy? sortBy}) {
    if (q != null) query = q;
    if (status != null) statusFilter = status;
    if (genre != null) genreFilter = genre;
    if (sortBy != null) sort = sortBy;
    notifyListeners();
  }

  List<Book> get filtered {
    final q = query.trim().toLowerCase();
    final list = _books.where((b) {
      final okStatus = statusFilter == 'all' ||
          (statusFilter == 'fav' ? b.fav : b.status.key == statusFilter);
      final okGenre = genreFilter.isEmpty || b.genre == genreFilter;
      final okQ = q.isEmpty ||
          [b.title, b.subtitle, b.author, b.genre, b.moods.join(' '), b.isbn, b.review]
              .join(' ')
              .toLowerCase()
              .contains(q);
      return okStatus && okGenre && okQ;
    }).toList();
    int byTitle(Book a, Book b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    switch (sort) {
      case SortBy.title:
        list.sort(byTitle);
      case SortBy.author:
        list.sort((a, b) {
          final c = a.author.toLowerCase().compareTo(b.author.toLowerCase());
          return c != 0 ? c : byTitle(a, b);
        });
      case SortBy.rating:
        list.sort((a, b) {
          final c = b.rating.compareTo(a.rating);
          return c != 0 ? c : byTitle(a, b);
        });
      case SortBy.finished:
        list.sort((a, b) => (b.end ?? DateTime(1900)).compareTo(a.end ?? DateTime(1900)));
      case SortBy.shortest:
        list.sort((a, b) => (a.pages ?? 1 << 30).compareTo(b.pages ?? 1 << 30));
      case SortBy.recentlyAdded:
        list.sort((a, b) => b.added.compareTo(a.added));
    }
    return list;
  }

  int count(String status) => status == 'all'
      ? _books.length
      : status == 'fav'
          ? _books.where((b) => b.fav).length
          : _books.where((b) => b.status.key == status).length;

  List<Book> get reading => _books.where((b) => b.status == ReadStatus.reading).toList();
  List<Book> get read => _books.where((b) => b.status == ReadStatus.read).toList();
  List<Book> readInYear(int y) => read.where((b) => b.end?.year == y).toList();
  int get pagesRead => read.fold(0, (s, b) => s + (b.pages ?? 0));

  List<String> get genresInUse {
    final s = _books.map((b) => b.genre).where((g) => g.isNotEmpty).toSet().toList()..sort();
    return s;
  }

  // ---------- CSV (matches the web tracker's "Copy my library as CSV") ----------
  static const csvCols = [
    'Title', 'Author', 'Genre', 'Status', 'Rating', 'Started', 'Finished', 'Pages',
    'Format', 'Favourite', 'Moods', 'Review', 'ISBN',
  ];

  String toCsv() {
    String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final rows = _books.map((b) => [
          b.title, b.author, b.genre, b.status.label, b.rating == 0 ? '' : b.rating,
          Book.isoDate(b.start), Book.isoDate(b.end), b.pages, b.format, b.fav ? 'Yes' : '',
          b.moods.join('; '), b.review, b.isbn,
        ].map(q).join(','));
    return [csvCols.join(','), ...rows].join('\n');
  }

  static List<List<String>> parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQ = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQ) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQ = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        inQ = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((x) => x.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    row.add(cell.toString());
    if (row.any((x) => x.isNotEmpty)) rows.add(row);
    return rows;
  }

  /// Merges a CSV copied from the web tracker. Matches by ISBN, then by title+author.
  /// Returns (updated, added).
  (int, int) importCsv(String text) {
    final rows = parseCsv(text.trim());
    if (rows.length < 2) return (0, 0);
    final h = rows.first.map((e) => e.trim()).toList();
    int col(String n) => h.indexOf(n);
    String v(List<String> r, String n) {
      final i = col(n);
      return (i >= 0 && i < r.length) ? r[i].trim() : '';
    }

    var updated = 0, added = 0;
    for (final r in rows.skip(1)) {
      final title = v(r, 'Title');
      if (title.isEmpty) continue;
      final author = v(r, 'Author');
      final isbn = v(r, 'ISBN');
      Book? b = isbn.isNotEmpty ? byIsbn(isbn) : null;
      b ??= _books.cast<Book?>().firstWhere(
          (x) => x!.title.toLowerCase() == title.toLowerCase() &&
              x.author.toLowerCase() == author.toLowerCase(),
          orElse: () => null);
      final isNew = b == null;
      b ??= Book(id: 'u${DateTime.now().microsecondsSinceEpoch}', title: title, author: author, isbn: isbn);
      final st = ReadStatus.values.firstWhere((s) => s.label == v(r, 'Status'), orElse: () => b!.status);
      b.status = st;
      if (v(r, 'Genre').isNotEmpty) b.genre = v(r, 'Genre');
      b.rating = double.tryParse(v(r, 'Rating')) ?? b.rating;
      b.start = DateTime.tryParse(v(r, 'Started')) ?? b.start;
      b.end = DateTime.tryParse(v(r, 'Finished')) ?? b.end;
      b.pages = int.tryParse(v(r, 'Pages')) ?? b.pages;
      if (v(r, 'Format').isNotEmpty) b.format = v(r, 'Format');
      b.fav = v(r, 'Favourite') == 'Yes' || b.fav;
      final moods = v(r, 'Moods');
      if (moods.isNotEmpty) b.moods = moods.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (v(r, 'Review').isNotEmpty) b.review = v(r, 'Review');
      if (isNew) {
        _books.add(b);
        added++;
      } else {
        updated++;
      }
    }
    _scheduleSave();
    notifyListeners();
    return (updated, added);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    super.dispose();
  }
}
