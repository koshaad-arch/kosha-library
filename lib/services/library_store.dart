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
  String statusFilter = 'all'; // all | tbr | reading | read | dnf | fav | own | wish | ownunread | readyr
  int tab = 0; // 0 shelf · 1 read · 2 wishlist · 3 stats
  int page = 0;
  int pageSize = 24; // 0 = all
  int scrollTick = 0; // bumps when the shelf should jump to the book list
  String statsYear = '${DateTime.now().year}'; // or 'all'
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
    pageSize = prefs.getInt('page_size_v1') ?? 24;
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
    await prefs.setInt('page_size_v1', pageSize);
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
          own: g.status == ReadStatus.tbr ? 'wish' : 'none',
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
    page = 0;
    notifyListeners();
  }

  List<Book> get filtered {
    final q = query.trim().toLowerCase();
    final list = _books.where((b) {
      final okStatus = matchesFilter(b, statusFilter);
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

  static bool matchesFilter(Book b, String f) => switch (f) {
        'all' => true,
        'fav' => b.fav,
        'own' => b.isOwned,
        'wish' => b.isWish,
        'ownunread' => b.isOwned && b.status == ReadStatus.tbr,
        'readyr' => b.status == ReadStatus.read && b.end?.year == DateTime.now().year,
        _ => b.status.key == f,
      };

  static const filterNames = {
    'all': 'All', 'reading': 'Reading', 'tbr': 'Want to read', 'read': 'Read', 'dnf': 'Did not finish',
    'fav': 'Favourites', 'own': 'Owned', 'wish': 'Wishlist', 'ownunread': 'Owned, not read yet',
    'readyr': 'Read this year',
  };

  int count(String status) => _books.where((b) => matchesFilter(b, status)).length;

  void setTab(int t) {
    tab = t;
    notifyListeners();
  }

  void setStatsYear(String y) {
    statsYear = y;
    notifyListeners();
  }

  /// Applies a stat-tile shortcut: filters the shelf (tapping the same tile again clears it).
  void goTo(String key) {
    if (key == 'pages' || key == 'year') {
      statsYear = key == 'year' ? '${DateTime.now().year}' : 'all';
      tab = 3;
    } else if (key == 'wish') {
      tab = 2;
    } else {
      statusFilter = statusFilter == key && key != 'readyr' ? 'all' : key;
      query = '';
      genreFilter = '';
      page = 0;
      tab = 0;
      scrollTick++;
    }
    notifyListeners();
  }

  void clearFilters() {
    statusFilter = 'all';
    query = '';
    genreFilter = '';
    page = 0;
    notifyListeners();
  }

  void setPage(int p) {
    page = p;
    scrollTick++;
    notifyListeners();
  }

  void setPageSize(int s) {
    pageSize = s;
    page = 0;
    _scheduleSave();
    notifyListeners();
  }

  void setOwn(Book b, String own) {
    b.own = own;
    touch(b);
  }

  List<Book> get wishlist {
    const order = {'High': 0, 'Medium': 1, 'Low': 2};
    final w = _books.where((b) => b.isWish).toList()
      ..sort((a, b) {
        final c = (order[a.prio] ?? 3).compareTo(order[b.prio] ?? 3);
        return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return w;
  }

  List<Book> get owned => _books.where((b) => b.isOwned).toList();

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
    'Format', 'Favourite', 'Moods', 'Review', 'ISBN', 'Owned', 'Price', 'Amazon link',
  ];

  String toCsv() {
    String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final rows = _books.map((b) => [
          b.title, b.author, b.genre, b.status.label, b.rating == 0 ? '' : b.rating,
          Book.isoDate(b.start), Book.isoDate(b.end), b.pages, b.format, b.fav ? 'Yes' : '',
          b.moods.join('; '), b.review, b.isbn,
          {'own': 'Owned', 'wish': 'Wishlist', 'none': 'Not owned'}[b.own] ?? 'Owned', b.price ?? '', b.amazonLink,
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
      final ownTxt = v(r, 'Owned');
      if (ownTxt.isNotEmpty) b.own = ownTxt == 'Wishlist' ? 'wish' : ownTxt == 'Not owned' ? 'none' : 'own';
      b.price = int.tryParse(v(r, 'Price')) ?? b.price;
      final link = v(r, 'Amazon link');
      if (link.startsWith('https://www.amazon') && link.contains('/dp/')) b.amz = link;
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


  // ---------- helpers shared by imports ----------
  static List<Map<String, String>> csvMaps(String text) {
    final rows = parseCsv(text.replaceFirst('﻿', '').trim());
    if (rows.isEmpty) return [];
    final h = rows.first.map((e) => e.trim()).toList();
    return rows.skip(1).map((r) => {for (var i = 0; i < h.length; i++) h[i]: i < r.length ? r[i].trim() : ''}).toList();
  }

  /// First non-empty value whose header matches one of [names] (letters/digits only, exact then partial).
  static String pick(Map<String, String> r, List<String> names) {
    String k(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final n in names) {
      for (final e in r.entries) {
        if (k(e.key) == n && e.value.trim().isNotEmpty) return e.value.trim();
      }
    }
    for (final n in names) {
      for (final e in r.entries) {
        if (k(e.key).contains(n) && e.value.trim().isNotEmpty) return e.value.trim();
      }
    }
    return '';
  }

  static String normT(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
      .split(':')
      .first
      .trim()
      .replaceFirst(RegExp(r'^(the|a|an)\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  static String surname(String a) =>
      a.split(',').first.trim().split(RegExp(r'\s+')).last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Book? findBook({String title = '', String author = '', String isbn = ''}) {
    if (isbn.isNotEmpty) {
      final b = byIsbn(isbn);
      if (b != null) return b;
    }
    final k = normT(title);
    if (k.isEmpty) return null;
    final c = _books.where((b) => normT(b.title) == k).toList();
    if (c.isEmpty) return null;
    final s = surname(author);
    for (final b in c) {
      if (s.isNotEmpty && surname(b.author) == s) return b;
    }
    if (c.length == 1 && (s.isEmpty || surname(c.first.author).isEmpty)) return c.first;
    return s.isEmpty ? c.first : null;
  }

  String _newId(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}';

  // ---------- owned-books list (CSV / Excel rows) ----------
  /// Returns a summary and the owned books that were NOT in the file.
  (String, List<Book>) importOwned(List<Map<String, String>> rows, String fileName) {
    rows = rows.where((r) => pick(r, ['title', 'booktitle', 'book', 'name']).isNotEmpty).toList();
    if (rows.isEmpty) return ('No titles found — the file needs a Title column.', []);
    const stMap = {
      'read': 'read', 'finished': 'read', 'done': 'read', 'completed': 'read', 'reading': 'reading',
      'currentlyreading': 'reading', 'current': 'reading', 'dnf': 'dnf', 'didnotfinish': 'dnf', 'abandoned': 'dnf',
      'tbr': 'tbr', 'toread': 'tbr', 'wanttoread': 'tbr', 'unread': 'tbr', 'notread': 'tbr',
    };
    final hit = <String>{};
    var added = 0, updated = 0, already = 0;
    for (final r in rows) {
      final t = pick(r, ['title', 'booktitle', 'book', 'name']);
      final a = pick(r, ['author', 'authors', 'writer', 'by']);
      final i = normIsbn(pick(r, ['isbn13', 'isbn', 'isbn10']));
      final p = int.tryParse(pick(r, ['pages', 'numberofpages', 'pagecount']));
      final g = pick(r, ['genre', 'category']);
      final pub = pick(r, ['publisher']);
      final y = int.tryParse(RegExp(r'\d{4}').stringMatch(pick(r, ['year', 'yearpublished', 'published'])) ?? '');
      final fmt = pick(r, ['format', 'binding', 'type']);
      final stRaw = pick(r, ['status', 'readingstatus', 'exclusiveshelf']).toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      final gOk = kGenres.contains(g) ? g : '';
      final b = findBook(title: t, author: a, isbn: i);
      if (b != null) {
        if (!hit.add(b.id)) continue;
        final wasOwned = b.isOwned;
        var changed = 0;
        if (!b.isOwned) {
          b.own = 'own';
          changed++;
        }
        if (i.isNotEmpty && b.isbn.isEmpty) { b.isbn = i; changed++; }
        if (p != null && b.pages == null) { b.pages = p; changed++; }
        if (gOk.isNotEmpty && b.genre.isEmpty) { b.genre = gOk; changed++; }
        if (pub.isNotEmpty && b.publisher.isEmpty) { b.publisher = pub; changed++; }
        if (y != null && b.year == null) { b.year = y; changed++; }
        if (wasOwned && changed == 0) {
          already++;
        } else {
          updated++;
        }
      } else {
        final nb = Book(
          id: _newId('o'),
          title: t,
          author: a,
          isbn: i,
          pages: p,
          genre: gOk,
          publisher: pub,
          year: y,
          own: 'own',
          status: ReadStatusX.parse(stMap[stRaw] ?? 'tbr'),
          format: RegExp(r'kindle|ebook', caseSensitive: false).hasMatch(fmt)
              ? 'Kindle'
              : RegExp(r'audio', caseSensitive: false).hasMatch(fmt)
                  ? 'Audiobook'
                  : RegExp(r'hard', caseSensitive: false).hasMatch(fmt)
                      ? 'Hardcover'
                      : 'Paperback',
        );
        _books.add(nb);
        hit.add(nb.id);
        added++;
      }
    }
    final gone = _books.where((b) => b.isOwned && !hit.contains(b.id)).toList();
    _scheduleSave();
    notifyListeners();
    return ('Owned books from “$fileName”: $added added · $updated marked owned or filled in · $already already up to date.', gone);
  }

  void markNotOwned(List<Book> list) {
    for (final b in list) {
      b.own = 'none';
    }
    _scheduleSave();
    notifyListeners();
  }

  // ---------- Amazon wishlist CSV ----------
  String importAmazon(List<Map<String, String>> rows) {
    rows = rows.where((r) => pick(r, ['title']).isNotEmpty).toList();
    if (rows.isEmpty) return 'That does not look like the Amazon wishlist file.';
    var added = 0, moved = 0, ownedAlready = 0, skipped = 0;
    for (final r in rows) {
      var full = pick(r, ['title']).replaceFirst(RegExp(r'\s*\((paperback|hardcover|kindle edition)\)\s*$', caseSensitive: false), '');
      final a = pick(r, ['author']);
      final price = double.tryParse(pick(r, ['price']).replaceAll(RegExp(r'[^0-9.]'), ''))?.round();
      final link = pick(r, ['amazonlink', 'link', 'url']);
      final asin = pick(r, ['asin']).toUpperCase();
      final isbnRaw = RegExp(r'^\d{9}[\dX]$').hasMatch(asin) ? asin : pick(r, ['isbn']);
      final i = normIsbn(isbnRaw);
      if (i.isEmpty && a.isEmpty && asin.startsWith('B0')) {
        skipped++;
        continue;
      }
      final ser = RegExp(r'\s*\(([^)]*\d[^)]*)\)\s*$').firstMatch(full)?.group(1);
      if (ser != null) full = full.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
      final parts = full.split(RegExp(r':\s+|\s+[–—-]\s+'));
      final t = parts.first.trim().isEmpty ? full : parts.first.trim();
      final sub = [parts.skip(1).join(': ').trim(), ser ?? ''].where((x) => x.isNotEmpty).join(' · ');
      final b = findBook(title: t, author: a, isbn: i);
      if (b != null) {
        if (b.isOwned) {
          ownedAlready++;
          continue;
        }
        b.own = 'wish';
        if (price != null && price > 0) b.price = price;
        if (link.startsWith('https://')) b.amz = link;
        if (i.isNotEmpty && b.isbn.isEmpty) b.isbn = i;
        moved++;
        continue;
      }
      _books.add(Book(
        id: _newId('az'),
        title: t,
        subtitle: sub,
        author: a,
        isbn: i,
        price: (price != null && price > 0) ? price : null,
        amz: link.startsWith('https://') ? link : '',
        own: 'wish',
        format: pick(r, ['title']).toLowerCase().contains('kindle') ? 'Kindle' : 'Paperback',
      ));
      added++;
    }
    _scheduleSave();
    notifyListeners();
    return 'Amazon wishlist: $added added · $moved moved to your wishlist · $ownedAlready skipped (already owned)'
        '${skipped > 0 ? ' · $skipped non-book items left out' : ''}.';
  }

  // ---------- backup ----------
  String backupJson() => const JsonEncoder.withIndent(' ').convert({
        'app': 'kosha-library-android',
        'v': 1,
        'saved': DateTime.now().toIso8601String(),
        'goal': goal,
        'books': _books.map((b) => b.toJson()).toList(),
      });

  String restoreBackup(String text) {
    Map<String, dynamic> d;
    try {
      d = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      return 'That is not a backup file.';
    }
    if (d['app'] != 'kosha-library-android' || d['books'] is! List) return 'That is not a Kosha’s Library app backup.';
    final list = (d['books'] as List).map((e) => Book.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final byId = {for (final b in _books) b.id: b};
    for (final b in list) {
      final i = _books.indexWhere((x) => x.id == b.id);
      if (i >= 0) {
        _books[i] = b;
      } else if (!byId.containsKey(b.id)) {
        _books.add(b);
      }
    }
    if (d['goal'] is int) goal = d['goal'] as int;
    _scheduleSave();
    notifyListeners();
    return 'Restored ${list.length} books from the backup.';
  }

  // ---------- suggestions ----------
  int pickSeed = 0;
  void morePicks() {
    pickSeed++;
    notifyListeners();
  }

  /// Top 3 genres you read (falling back to what's on your shelf), each with up to 4 books you don't have.
  List<(String, int, List<(String, String)>)> picks(Map<String, List<String>> pool) {
    final c = <String, int>{}, rs = <String, double>{};
    for (final b in read) {
      if (b.genre.isNotEmpty && pool.containsKey(b.genre)) {
        c[b.genre] = (c[b.genre] ?? 0) + 1;
        rs[b.genre] = (rs[b.genre] ?? 0) + b.rating;
      }
    }
    var g = c.keys.toList()
      ..sort((a, b) {
        final x = c[b]!.compareTo(c[a]!);
        return x != 0 ? x : rs[b]!.compareTo(rs[a]!);
      });
    if (g.length < 3) {
      final o = <String, int>{};
      for (final b in _books) {
        if (b.genre.isNotEmpty && pool.containsKey(b.genre) && !g.contains(b.genre)) o[b.genre] = (o[b.genre] ?? 0) + 1;
      }
      g = [...g, ...(o.keys.toList()..sort((a, b) => o[b]!.compareTo(o[a]!)))];
    }
    final have = _books.map((b) => normT(b.title)).toSet();
    return g.take(3).map((genre) {
      final list = pool[genre]!
          .map((s) {
            final parts = s.split('|');
            return (parts[0], parts.length > 1 ? parts[1] : '');
          })
          .where((x) => !have.contains(normT(x.$1)))
          .toList();
      final seeded = [...list]..sort((x, y) => (x.$1.hashCode ^ pickSeed * 7919).compareTo(y.$1.hashCode ^ pickSeed * 7919));
      final chosen = seeded.length <= 4 ? seeded : List.generate(4, (k) => seeded[(pickSeed * 4 + k) % seeded.length]);
      return (genre, c[genre] ?? 0, chosen);
    }).toList();
  }

  Book addToWishlist(String title, String author, String genre) {
    final existing = findBook(title: title, author: author);
    if (existing != null) return existing;
    final b = Book(id: _newId('sg'), title: title, author: author, genre: genre, own: 'wish');
    add(b);
    return b;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    super.dispose();
  }
}
