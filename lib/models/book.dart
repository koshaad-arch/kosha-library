import 'dart:convert';

enum ReadStatus { tbr, reading, read, dnf }

extension ReadStatusX on ReadStatus {
  String get label => switch (this) {
        ReadStatus.tbr => 'Want to read',
        ReadStatus.reading => 'Reading',
        ReadStatus.read => 'Read',
        ReadStatus.dnf => 'Did not finish',
      };
  String get key => name;
  static ReadStatus parse(String? s) =>
      ReadStatus.values.firstWhere((e) => e.name == s, orElse: () => ReadStatus.tbr);
}

const kGenres = [
  'Thriller & Mystery', 'Romance', 'Fantasy & Sci-Fi', 'Mythology', 'Literary Fiction',
  'Classics', 'Young Adult', "Children's", 'Self-help', 'Spiritual', 'Non-fiction',
  'Comics', 'Reference', 'Poetry', 'Other',
];

const kMoods = [
  'cozy', 'dark', 'emotional', 'funny', 'romantic', 'mysterious', 'adventurous',
  'inspiring', 'fast-paced', 'slow burn', 'twisty', 'comforting',
];

const kFormats = ['Paperback', 'Hardcover', 'Kindle', 'eBook', 'Audiobook'];

/// own = on your shelf · wish = need to buy · none = read/borrowed, not owned
const kOwnLabels = {'own': '📚 Own it', 'wish': '🛒 Need to buy', 'none': "📖 Don't own"};
const kPriorities = ['High', 'Medium', 'Low'];

class Book {
  String id;
  String title;
  String subtitle;
  String author;
  String genre;
  int? year;
  String publisher;
  int? pages;
  String isbn;
  ReadStatus status;
  DateTime? start;
  DateTime? end;
  String format;
  String summary;
  double rating;
  bool fav;
  List<String> moods;
  String review;
  String quote;
  int currentPage;
  String coverUrl;
  DateTime added;
  String goodreadsId;
  String grSig;
  String asin; // Kindle edition id (B0…)
  List<String> kindleNotes; // highlights imported from Kindle
  String own; // own | wish | none
  int? price; // ₹, for wishlist books
  String prio; // High | Medium | Low
  String amz; // custom Amazon product link

  Book({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.author = '',
    this.genre = '',
    this.year,
    this.publisher = '',
    this.pages,
    this.isbn = '',
    this.status = ReadStatus.tbr,
    this.start,
    this.end,
    this.format = 'Paperback',
    this.summary = '',
    this.rating = 0,
    this.fav = false,
    List<String>? moods,
    this.review = '',
    this.quote = '',
    this.currentPage = 0,
    this.coverUrl = '',
    DateTime? added,
    this.goodreadsId = '',
    this.grSig = '',
    this.asin = '',
    List<String>? kindleNotes,
    this.own = 'own',
    this.price,
    this.prio = '',
    this.amz = '',
  })  : moods = moods ?? [],
        kindleNotes = kindleNotes ?? [],
        added = added ?? DateTime.now();

  double get progress =>
      (pages == null || pages == 0) ? 0 : (currentPage / pages!).clamp(0, 1).toDouble();

  String get firstAuthor => author.split(',').first.trim();

  bool get isOwned => own == 'own';
  bool get isWish => own == 'wish';
  bool get isDigital => format == 'Kindle' || format == 'eBook' || format == 'Audiobook';
  bool get hasReview => review.trim().isNotEmpty;

  /// The Kindle edition's id, typed in or taken from an Amazon Kindle link.
  String get kindleAsin {
    if (asin.trim().isNotEmpty) return asin.trim().toUpperCase();
    return RegExp(r'/(?:dp|gp/product)/(B0[A-Z0-9]{8})').firstMatch(amz)?.group(1) ?? '';
  }

  /// Small badge for the shelf: how you have this book.
  String get formatBadge => switch (format) {
        'Kindle' => '📱 Kindle',
        'eBook' => '💻 eBook',
        'Audiobook' => '🎧 Audio',
        'Hardcover' => '📕 Hardcover',
        _ => '',
      };

  /// Exact Amazon.in product page when we know the ISBN, otherwise a book search.
  String get amazonLink {
    if (amz.startsWith('https://')) return amz;
    final i = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (i.length == 10) return 'https://www.amazon.in/dp/$i';
    if (i.length == 13 && i.startsWith('978')) return 'https://www.amazon.in/dp/${isbn13to10(i)}';
    return 'https://www.amazon.in/s?k=${Uri.encodeQueryComponent('$title $firstAuthor'.trim())}&i=stripbooks';
  }

  static String isbn13to10(String i) {
    final c = i.substring(3, 12);
    var s = 0;
    for (var k = 0; k < 9; k++) {
      s += (10 - k) * int.parse(c[k]);
    }
    final r = (11 - s % 11) % 11;
    return '$c${r == 10 ? 'X' : r}';
  }

  static DateTime? _d(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;
  static String? _ds(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Reads both the compact bundled catalogue (t, a, st…) and the app's own saved format.
  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: (j['title'] ?? j['t'] ?? '') as String,
        subtitle: (j['subtitle'] ?? j['sub'] ?? '') as String,
        author: (j['author'] ?? j['a'] ?? '') as String,
        genre: (j['genre'] ?? j['g'] ?? '') as String,
        year: (j['year'] ?? j['y']) as int?,
        publisher: (j['publisher'] ?? j['pub'] ?? '') as String,
        pages: (j['pages'] ?? j['p']) as int?,
        isbn: (j['isbn'] ?? '').toString(),
        status: ReadStatusX.parse((j['status'] ?? j['st']) as String?),
        start: _d(j['start']),
        end: _d(j['end']),
        format: (j['format'] ?? j['fmt'] ?? 'Paperback') as String,
        summary: (j['summary'] ?? j['sum'] ?? '') as String,
        rating: ((j['rating'] ?? 0) as num).toDouble(),
        fav: (j['fav'] ?? false) as bool,
        moods: ((j['moods'] ?? []) as List).map((e) => e.toString()).toList(),
        review: (j['review'] ?? '') as String,
        quote: (j['quote'] ?? '') as String,
        currentPage: (j['currentPage'] ?? 0) as int,
        coverUrl: (j['coverUrl'] ?? '') as String,
        added: _d(j['added']),
        goodreadsId: (j['goodreadsId'] ?? '').toString(),
        asin: (j['asin'] ?? '') as String,
        kindleNotes: ((j['kn'] ?? []) as List).map((e) => e.toString()).toList(),
        grSig: (j['grSig'] ?? '') as String,
        own: (j['own'] ?? 'own') as String,
        price: (j['price'] as num?)?.toInt(),
        prio: (j['prio'] ?? '') as String,
        amz: (j['amz'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'author': author,
        'genre': genre,
        'year': year,
        'publisher': publisher,
        'pages': pages,
        'isbn': isbn,
        'status': status.key,
        'start': _ds(start),
        'end': _ds(end),
        'format': format,
        'summary': summary,
        'rating': rating,
        'fav': fav,
        'moods': moods,
        'review': review,
        'quote': quote,
        'currentPage': currentPage,
        'coverUrl': coverUrl,
        'added': _ds(added),
        'goodreadsId': goodreadsId,
        'asin': asin,
        'kn': kindleNotes,
        'grSig': grSig,
        'own': own,
        'price': price,
        'prio': prio,
        'amz': amz,
      };

  static String encodeList(List<Book> books) =>
      jsonEncode(books.map((b) => b.toJson()).toList());
  static List<Book> decodeList(String s) => (jsonDecode(s) as List)
      .map((e) => Book.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  static String dateLabel(DateTime? d) {
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  static String? isoDate(DateTime? d) => _ds(d);
}
