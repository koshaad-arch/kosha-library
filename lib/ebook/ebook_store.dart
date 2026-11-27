import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import 'epub.dart';

class Highlight {
  final String id;
  final int section;
  final String text;
  String color; // y b p o
  String note;
  final DateTime created;
  Highlight(this.id, this.section, this.text, this.color, this.note, this.created);
  Map<String, dynamic> toJson() =>
      {'id': id, 's': section, 'text': text, 'c': color, 'note': note, 'at': created.toIso8601String()};
  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(j['id'] as String, j['s'] as int, j['text'] as String,
      (j['c'] ?? 'y') as String, (j['note'] ?? '') as String, DateTime.tryParse('${j['at']}') ?? DateTime.now());
}

class Bookmark {
  final String id;
  final int section;
  final double frac;
  final String label;
  final DateTime created;
  Bookmark(this.id, this.section, this.frac, this.label, this.created);
  Map<String, dynamic> toJson() => {'id': id, 's': section, 'f': frac, 'label': label, 'at': created.toIso8601String()};
  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(j['id'] as String, j['s'] as int,
      (j['f'] as num).toDouble(), (j['label'] ?? '') as String, DateTime.tryParse('${j['at']}') ?? DateTime.now());
}

class Ebook {
  final String id;
  String title, author, bookId;
  final String file;
  String coverFile;
  int section;
  double frac;
  double progress; // 0..1 of the whole book
  int readSeconds, pagesTurned;
  DateTime? lastOpened;
  final DateTime added;
  final List<Highlight> highlights;
  final List<Bookmark> bookmarks;

  Ebook({
    required this.id,
    required this.title,
    required this.author,
    required this.file,
    this.bookId = '',
    this.coverFile = '',
    this.section = 0,
    this.frac = 0,
    this.progress = 0,
    this.readSeconds = 0,
    this.pagesTurned = 0,
    this.lastOpened,
    DateTime? added,
    List<Highlight>? highlights,
    List<Bookmark>? bookmarks,
  })  : added = added ?? DateTime.now(),
        highlights = highlights ?? [],
        bookmarks = bookmarks ?? [];

  /// Average seconds per page, from your own reading (Kindle-style "time left").
  double get secPerPage => pagesTurned >= 5 ? readSeconds / pagesTurned : 75;

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'author': author, 'file': file, 'bookId': bookId, 'cover': coverFile,
        's': section, 'f': frac, 'p': progress, 'sec': readSeconds, 'turns': pagesTurned,
        'opened': lastOpened?.toIso8601String(), 'added': added.toIso8601String(),
        'hl': highlights.map((h) => h.toJson()).toList(), 'bm': bookmarks.map((b) => b.toJson()).toList(),
      };

  factory Ebook.fromJson(Map<String, dynamic> j) => Ebook(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        author: (j['author'] ?? '') as String,
        file: j['file'] as String,
        bookId: (j['bookId'] ?? '') as String,
        coverFile: (j['cover'] ?? '') as String,
        section: (j['s'] ?? 0) as int,
        frac: ((j['f'] ?? 0) as num).toDouble(),
        progress: ((j['p'] ?? 0) as num).toDouble(),
        readSeconds: (j['sec'] ?? 0) as int,
        pagesTurned: (j['turns'] ?? 0) as int,
        lastOpened: DateTime.tryParse('${j['opened']}'),
        added: DateTime.tryParse('${j['added']}'),
        highlights: ((j['hl'] ?? []) as List).map((e) => Highlight.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        bookmarks: ((j['bm'] ?? []) as List).map((e) => Bookmark.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class ReaderSettings {
  double fontSize;
  String font; // serif | sans | condensed | mono
  double lineHeight;
  int margin; // px
  String theme; // white | sepia | green | dark | black
  bool justify;
  ReaderSettings({this.fontSize = 19, this.font = 'serif', this.lineHeight = 1.6, this.margin = 22, this.theme = 'white', this.justify = true});
  Map<String, dynamic> toJson() =>
      {'size': fontSize, 'font': font, 'lh': lineHeight, 'm': margin, 'theme': theme, 'j': justify};
  factory ReaderSettings.fromJson(Map<String, dynamic> j) => ReaderSettings(
        fontSize: ((j['size'] ?? 19) as num).toDouble(),
        font: (j['font'] ?? 'serif') as String,
        lineHeight: ((j['lh'] ?? 1.6) as num).toDouble(),
        margin: (j['m'] ?? 22) as int,
        theme: (j['theme'] ?? 'white') as String,
        justify: (j['j'] ?? true) as bool,
      );
}

/// A free book from Project Gutenberg (via the Gutendex catalogue).
class FreeBook {
  final int id;
  final String title, author, epubUrl, coverUrl;
  final int downloads;
  FreeBook(this.id, this.title, this.author, this.epubUrl, this.coverUrl, this.downloads);
}

class EbookStore extends ChangeNotifier {
  static const _k = 'ebooks_v1';
  static const _kSet = 'reader_settings_v1';
  final List<Ebook> ebooks = [];
  ReaderSettings settings = ReaderSettings();
  bool loaded = false;
  final Map<String, EpubBook> _parsed = {};
  Timer? _t;
  late Directory _dir;

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/ebooks');
    if (!await _dir.exists()) await _dir.create(recursive: true);
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s != null) {
      ebooks.addAll((jsonDecode(s) as List).map((e) => Ebook.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    final rs = p.getString(_kSet);
    if (rs != null) settings = ReaderSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rs) as Map));
    loaded = true;
    notifyListeners();
  }

  void save() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 600), () async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, jsonEncode(ebooks.map((e) => e.toJson()).toList()));
      await p.setString(_kSet, jsonEncode(settings.toJson()));
    });
  }

  void changed() {
    save();
    notifyListeners();
  }

  Ebook? forBook(String bookId) {
    for (final e in ebooks) {
      if (e.bookId == bookId) return e;
    }
    return null;
  }

  List<Ebook> get recent => [...ebooks]..sort((a, b) => (b.lastOpened ?? b.added).compareTo(a.lastOpened ?? a.added));

  Future<EpubBook> open(Ebook e) async {
    final cached = _parsed[e.id];
    if (cached != null) return cached;
    final bytes = await File(e.file).readAsBytes();
    final b = await compute(EpubBook.parse, bytes);
    _parsed
      ..clear()
      ..[e.id] = b;
    return b;
  }

  /// Saves an EPUB into the app, links it to a shelf book (creating one if needed).
  Future<Ebook> importEpub(Uint8List bytes, LibraryStore library, {String fallbackTitle = '', String fallbackAuthor = ''}) async {
    final parsed = await compute(EpubBook.parse, bytes);
    final id = 'e${DateTime.now().microsecondsSinceEpoch}';
    final file = File('${_dir.path}/$id.epub');
    await file.writeAsBytes(bytes, flush: true);
    var cover = '';
    if (parsed.cover != null) {
      final cf = File('${_dir.path}/$id.cover');
      await cf.writeAsBytes(parsed.cover!, flush: true);
      cover = cf.path;
    }
    final title = parsed.title == 'Untitled' && fallbackTitle.isNotEmpty ? fallbackTitle : parsed.title;
    final author = parsed.author.isNotEmpty ? parsed.author : fallbackAuthor;
    var book = library.findBook(title: title, author: author);
    if (book == null) {
      book = Book(id: 'eb$id', title: title.split(':').first.trim(), author: author, own: 'own', format: 'eBook');
      library.add(book);
    } else if (book.format != 'eBook' && !book.isOwned) {
      book.own = 'own';
      library.touch(book);
    }
    final e = Ebook(id: id, title: title, author: author, file: file.path, bookId: book.id, coverFile: cover);
    ebooks.add(e);
    _parsed
      ..clear()
      ..[id] = parsed;
    changed();
    return e;
  }

  Future<void> remove(Ebook e) async {
    ebooks.removeWhere((x) => x.id == e.id);
    try {
      await File(e.file).delete();
      if (e.coverFile.isNotEmpty) await File(e.coverFile).delete();
    } catch (_) {}
    changed();
  }

  // ---------- free classics (Project Gutenberg) ----------
  static const _ua = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 16; SM-S901E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  static FreeBook gutenberg(int id, String title, String author) => FreeBook(
        id,
        title,
        author,
        'https://www.gutenberg.org/ebooks/$id.epub3.images',
        'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg',
        0,
      );

  /// Well-known classics shown instantly (no catalogue needed).
  static final popular = <FreeBook>[
    gutenberg(1342, 'Pride and Prejudice', 'Jane Austen'),
    gutenberg(158, 'Emma', 'Jane Austen'),
    gutenberg(161, 'Sense and Sensibility', 'Jane Austen'),
    gutenberg(1260, 'Jane Eyre', 'Charlotte Brontë'),
    gutenberg(768, 'Wuthering Heights', 'Emily Brontë'),
    gutenberg(514, 'Little Women', 'Louisa May Alcott'),
    gutenberg(64317, 'The Great Gatsby', 'F. Scott Fitzgerald'),
    gutenberg(1661, 'The Adventures of Sherlock Holmes', 'Arthur Conan Doyle'),
    gutenberg(2852, 'The Hound of the Baskervilles', 'Arthur Conan Doyle'),
    gutenberg(244, 'A Study in Scarlet', 'Arthur Conan Doyle'),
    gutenberg(108, 'The Return of Sherlock Holmes', 'Arthur Conan Doyle'),
    gutenberg(84, 'Frankenstein', 'Mary Shelley'),
    gutenberg(345, 'Dracula', 'Bram Stoker'),
    gutenberg(43, 'The Strange Case of Dr Jekyll and Mr Hyde', 'Robert Louis Stevenson'),
    gutenberg(120, 'Treasure Island', 'Robert Louis Stevenson'),
    gutenberg(174, 'The Picture of Dorian Gray', 'Oscar Wilde'),
    gutenberg(98, 'A Tale of Two Cities', 'Charles Dickens'),
    gutenberg(1400, 'Great Expectations', 'Charles Dickens'),
    gutenberg(46, 'A Christmas Carol', 'Charles Dickens'),
    gutenberg(730, 'Oliver Twist', 'Charles Dickens'),
    gutenberg(11, "Alice's Adventures in Wonderland", 'Lewis Carroll'),
    gutenberg(16, 'Peter Pan', 'J. M. Barrie'),
    gutenberg(55, 'The Wonderful Wizard of Oz', 'L. Frank Baum'),
    gutenberg(236, 'The Jungle Book', 'Rudyard Kipling'),
    gutenberg(74, 'The Adventures of Tom Sawyer', 'Mark Twain'),
    gutenberg(76, 'Adventures of Huckleberry Finn', 'Mark Twain'),
    gutenberg(35, 'The Time Machine', 'H. G. Wells'),
    gutenberg(36, 'The War of the Worlds', 'H. G. Wells'),
    gutenberg(2701, 'Moby-Dick', 'Herman Melville'),
    gutenberg(1184, 'The Count of Monte Cristo', 'Alexandre Dumas'),
    gutenberg(2600, 'War and Peace', 'Leo Tolstoy'),
    gutenberg(2554, 'Crime and Punishment', 'Fyodor Dostoyevsky'),
    gutenberg(5200, 'Metamorphosis', 'Franz Kafka'),
    gutenberg(2814, 'Dubliners', 'James Joyce'),
    gutenberg(33, 'The Scarlet Letter', 'Nathaniel Hawthorne'),
    gutenberg(1952, 'The Yellow Wallpaper', 'Charlotte Perkins Gilman'),
    gutenberg(1513, 'Romeo and Juliet', 'William Shakespeare'),
    gutenberg(1524, 'Hamlet', 'William Shakespeare'),
    gutenberg(2591, "Grimms' Fairy Tales", 'Jacob and Wilhelm Grimm'),
    gutenberg(1232, 'The Prince', 'Niccolò Machiavelli'),
    gutenberg(132, 'The Art of War', 'Sun Tzu'),
    gutenberg(2680, 'Meditations', 'Marcus Aurelius'),
    gutenberg(205, 'Walden', 'Henry David Thoreau'),
    gutenberg(1727, 'The Odyssey', 'Homer'),
    gutenberg(996, 'Don Quixote', 'Miguel de Cervantes'),
  ];

  static Future<List<FreeBook>> searchFree(String q) async {
    if (q.trim().isEmpty) return popular;
    // 1) Gutendex catalogue
    try {
      final uri = Uri.https('gutendex.com', '/books/', {'search': q.trim(), 'mime_type': 'application/epub'});
      final r = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map;
        final list = ((d['results'] as List?) ?? []).map((x) {
          final m = Map<String, dynamic>.from(x as Map);
          final names = ((m['authors'] as List?) ?? []).map((a) {
            final n = ((a as Map)['name'] ?? '') as String;
            final parts = n.split(', ');
            return parts.length == 2 ? '${parts[1]} ${parts[0]}' : n;
          }).join(', ');
          return gutenberg(m['id'] as int, (m['title'] ?? '') as String, names);
        }).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    // 2) Project Gutenberg's own search (OPDS feed)
    final r = await http
        .get(Uri.parse('https://www.gutenberg.org/ebooks/search.opds/?query=${Uri.encodeQueryComponent(q.trim())}'), headers: _ua)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('The free library did not answer (${r.statusCode}).');
    final out = <FreeBook>[];
    final seen = <int>{};
    for (final m in RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(r.body)) {
      final e = m.group(1)!;
      final id = int.tryParse(RegExp(r'/ebooks/(\d+)').firstMatch(e)?.group(1) ?? '');
      if (id == null || !seen.add(id)) continue;
      String clean(String s) => s
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&#39;', "'")
          .replaceAll('&quot;', '"')
          .trim();
      final title = clean(RegExp(r'<title[^>]*>([\s\S]*?)</title>').firstMatch(e)?.group(1) ?? '');
      final author = clean(RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(e)?.group(1) ?? '');
      if (title.isEmpty) continue;
      out.add(gutenberg(id, title, author));
    }
    return out;
  }

  Future<Ebook> downloadFree(FreeBook f, LibraryStore library) async {
    var r = await http.get(Uri.parse(f.epubUrl), headers: _ua).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200 || r.bodyBytes.length < 1000 || r.bodyBytes[0] != 0x50) {
      // some books only have the older EPUB format
      r = await http.get(Uri.parse('https://www.gutenberg.org/ebooks/${f.id}.epub.images'), headers: _ua)
          .timeout(const Duration(seconds: 90));
    }
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty && r.bodyBytes[0] != 0x50) {
      throw Exception('Project Gutenberg sent a web page instead of the book. Try again in a minute.');
    }
    if (r.statusCode != 200) throw Exception('Download failed (${r.statusCode}).');
    return importEpub(r.bodyBytes, library, fallbackTitle: f.title, fallbackAuthor: f.author);
  }
}
