import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/book.dart';

/// One book as it appears on a Goodreads shelf RSS feed.
class GrItem {
  final String grId, title, author, isbn, review, imageUrl, description, shelf;
  final double rating;
  final DateTime? readAt, addedAt;
  final int? pages, year;
  GrItem({
    required this.grId,
    required this.title,
    required this.author,
    required this.isbn,
    required this.review,
    required this.imageUrl,
    required this.description,
    required this.shelf,
    required this.rating,
    required this.readAt,
    required this.addedAt,
    required this.pages,
    required this.year,
  });

  ReadStatus get status => switch (shelf) {
        'read' => ReadStatus.read,
        'currently-reading' => ReadStatus.reading,
        _ => ReadStatus.tbr,
      };

  /// Changes only when something on Goodreads changes, so local edits are kept
  /// until you change that book on Goodreads again.
  String get signature =>
      '$shelf|${rating.toStringAsFixed(1)}|${readAt?.toIso8601String() ?? ''}|${review.hashCode}';
}

class GoodreadsAccount {
  final String userId;
  final String key; // present only when the user pasted a private RSS link
  const GoodreadsAccount(this.userId, this.key);
}

class GoodreadsSync {
  static const shelves = ['read', 'currently-reading', 'to-read'];

  /// Accepts a profile link, a shelf link, an RSS link or just the number.
  static GoodreadsAccount? parse(String input) {
    final s = input.trim();
    final id = RegExp(r'(?:user/show|review/list(?:_rss)?|list_rss)/(\d+)').firstMatch(s)?.group(1) ??
        RegExp(r'^(\d+)(?:-|$)').firstMatch(s)?.group(1);
    if (id == null) return null;
    final key = RegExp(r'[?&]key=([^&\s]+)').firstMatch(s)?.group(1) ?? '';
    return GoodreadsAccount(id, key);
  }

  static Future<List<GrItem>> fetchAll(GoodreadsAccount acc) async {
    final all = <GrItem>[];
    for (final shelf in shelves) {
      all.addAll(await _fetchShelf(acc, shelf));
    }
    return all;
  }

  static Future<List<GrItem>> _fetchShelf(GoodreadsAccount acc, String shelf) async {
    final seen = <String>{};
    final out = <GrItem>[];
    for (var page = 1; page <= 20; page++) {
      final params = {'shelf': shelf, 'page': '$page', 'per_page': '100'};
      if (acc.key.isNotEmpty) params['key'] = acc.key;
      final uri = Uri.https('www.goodreads.com', '/review/list_rss/${acc.userId}', params);
      final res = await http.get(uri, headers: {'User-Agent': 'KoshasLibrary/1.0'}).timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) throw const GoodreadsException('Goodreads profile not found. Check the link or number.');
      if (res.statusCode == 403 || res.statusCode == 401) {
        throw const GoodreadsException(
            'Goodreads says this profile is private. Make it public, or paste the RSS link from your Read shelf.');
      }
      if (res.statusCode != 200) throw GoodreadsException('Goodreads did not answer (error ${res.statusCode}). Try again later.');
      final XmlDocument doc;
      try {
        doc = XmlDocument.parse(res.body);
      } catch (_) {
        throw const GoodreadsException(
            'Goodreads returned a page instead of your shelf. Your profile may be private — paste the RSS link from your Read shelf instead.');
      }
      final items = doc.findAllElements('item').map((e) => _item(e, shelf)).toList();
      final fresh = items.where((i) => seen.add(i.grId)).toList();
      out.addAll(fresh);
      if (fresh.isEmpty || items.length < 10) break;
    }
    return out;
  }

  static String _t(XmlElement e, String name) {
    final n = e.findElements(name);
    return n.isEmpty ? '' : n.first.innerText.trim();
  }

  static GrItem _item(XmlElement e, String shelf) {
    final bookEl = e.findElements('book');
    String pagesTxt = '';
    if (bookEl.isNotEmpty) pagesTxt = _t(bookEl.first, 'num_pages');
    final img = [_t(e, 'book_large_image_url'), _t(e, 'book_medium_image_url'), _t(e, 'book_image_url')]
        .firstWhere((u) => u.isNotEmpty && !u.contains('nophoto'), orElse: () => '');
    return GrItem(
      grId: _t(e, 'book_id'),
      title: _t(e, 'title'),
      author: _t(e, 'author_name'),
      isbn: _t(e, 'isbn'),
      review: _stripHtml(_t(e, 'user_review')),
      imageUrl: img,
      description: _stripHtml(_t(e, 'book_description')),
      shelf: shelf,
      rating: double.tryParse(_t(e, 'user_rating')) ?? 0,
      readAt: parseRfc822(_t(e, 'user_read_at')),
      addedAt: parseRfc822(_t(e, 'user_date_added')),
      pages: int.tryParse(pagesTxt),
      year: int.tryParse(_t(e, 'book_published')),
    );
  }

  static String _stripHtml(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  /// "Mon, 06 Mar 2017 12:02:40 -0800" -> DateTime (date part only).
  static DateTime? parseRfc822(String s) {
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4})').firstMatch(s);
    if (m == null) return null;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final mi = months.indexOf(m.group(2)!);
    if (mi < 0) return null;
    return DateTime(int.parse(m.group(3)!), mi + 1, int.parse(m.group(1)!));
  }

  /// Loose key for matching the same book across sources.
  static String matchKey(String title, String author) {
    var t = title.toLowerCase();
    t = t.replaceAll(RegExp(r'\(.*?\)'), '').split(':').first;
    t = t.replaceAll(RegExp(r'^(the|a|an) '), '').replaceAll(RegExp(r'[^a-z0-9]'), '');
    final parts = author.toLowerCase().split(',').first.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last.replaceAll(RegExp(r'[^a-z]'), '');
    return '$t|$last';
  }

  static String amazonUrl(Book b) => b.isbn.isNotEmpty
      ? 'https://www.amazon.in/s?k=${Uri.encodeQueryComponent(b.isbn)}&i=stripbooks'
      : 'https://www.amazon.in/s?k=${Uri.encodeQueryComponent('${b.title} ${b.firstAuthor}')}&i=stripbooks';

  static String goodreadsUrl(Book b) => b.goodreadsId.isNotEmpty
      ? 'https://www.goodreads.com/book/show/${b.goodreadsId}'
      : 'https://www.goodreads.com/search?q=${Uri.encodeQueryComponent(b.isbn.isNotEmpty ? b.isbn : '${b.title} ${b.firstAuthor}')}';
}

class GoodreadsException implements Exception {
  final String message;
  const GoodreadsException(this.message);
  @override
  String toString() => message;
}
